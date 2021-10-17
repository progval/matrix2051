##
# Copyright (C) 2021  Valentin Lorentz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License version 3,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
###

defmodule Matrix2051.IrcConn.Handler do
  @moduledoc """
    Receives commands from the reader and dispatches them.
  """

  use Task, restart: :permanent

  def start_link(args) do
    Task.start_link(__MODULE__, :run, [args])
  end

  # the max-bytes value is completely arbitrary, as I can't find a way for
  # Matrix clients to figure out the actual limit from
  # https://matrix.org/docs/spec/client_server/r0.6.1#size-limits
  # 8kB should be a reasonable limit to remain under the allowed 65kB even
  # with large signatures and many escapes.
  @multiline_max_bytes 8192

  # set of capabilities that we will show in CAP LS and accept with ACK;
  # along with their value (shown in CAP LS 302)
  @capabilities %{
    # https://github.com/ircv3/ircv3-specifications/pull/435
    "draft/account-registration" => {:account_registration, "before-connect"},

    # https://ircv3.net/specs/extensions/account-tag.html
    "account-tag" => {:account_tag, nil},

    # https://ircv3.net/specs/extensions/batch
    "batch" => {:batch, nil},

    # https://ircv3.net/specs/extensions/echo-message.html
    "echo-message" => {:echo_message, nil},

    # https://ircv3.net/specs/extensions/extended-join.html
    "extended-join" => {:extended_join, nil},

    # https://ircv3.net/specs/extensions/labeled-response
    "labeled-response" => {:labeled_response, nil},

    # https://ircv3.net/specs/extensions/message-tags and enables these too:
    # * https://ircv3.net/specs/extensions/message-ids
    # * https://ircv3.net/specs/client-tags/reply
    "message-tags" => {:message_tags, nil},

    # https://ircv3.net/specs/extensions/multiline
    "draft/multiline" => {:multiline, "max-bytes=#{@multiline_max_bytes}"},

    # https://ircv3.net/specs/extensions/sasl-3.1
    "sasl" => {:sasl, "PLAIN"},

    # https://ircv3.net/specs/extensions/server-time
    "server-time" => {:server_time, nil}
  }

  @valid_batch_types ["draft/multiline"]

  @doc """
    Main loop.

    Starts by calling loop_connreg, which deals with the connection registration
    (https://modern.ircdocs.horse/#connection-registration) and returns when
    it is done.
    Then loops forever.
  """
  def run(args) do
    {sup_pid} = args
    Registry.register(Matrix2051.Registry, {sup_pid, :irc_handler}, nil)
    state = Matrix2051.IrcConn.Supervisor.state(sup_pid)

    if !Matrix2051.IrcConn.State.registered(state) do
      loop_connreg(sup_pid)
    end

    loop(sup_pid)
  end

  defp loop(sup_pid) do
    receive do
      command ->
        handle(sup_pid, command)
    end

    loop(sup_pid)
  end

  defp loop_connreg(
         sup_pid,
         nick \\ nil,
         gecos \\ nil,
         user_id \\ nil,
         waiting_cap_end \\ false
       ) do
    writer = Matrix2051.IrcConn.Supervisor.writer(sup_pid)
    send = fn cmd -> Matrix2051.IrcConn.Writer.write_command(writer, cmd) end

    receive do
      command ->
        {nick, gecos, user_id, waiting_cap_end} =
          case handle_connreg(sup_pid, command, nick) do
            nil -> {nick, gecos, user_id, waiting_cap_end}
            {:nick, nick} -> {nick, gecos, user_id, waiting_cap_end}
            {:user, gecos} -> {nick, gecos, user_id, waiting_cap_end}
            {:authenticate, user_id} -> {nick, gecos, user_id, waiting_cap_end}
            :got_cap_ls -> {nick, gecos, user_id, true}
            :got_cap_end -> {nick, gecos, user_id, false}
          end

        if nick != nil && gecos != nil && !waiting_cap_end do
          # Registration finished. Send welcome messages and return to the main loop
          state = Matrix2051.IrcConn.Supervisor.state(sup_pid)

          Matrix2051.IrcConn.State.set_nick(state, nick)
          Matrix2051.IrcConn.State.set_gecos(state, gecos)

          case user_id do
            # all good
            ^nick ->
              send_welcome(sup_pid, command)

              Matrix2051.IrcConn.State.set_registered(state)

              case Registry.lookup(Matrix2051.Registry, {sup_pid, :matrix_poller}) do
                [{matrix_poller, _}] -> send(matrix_poller, :start_polling)
                [] -> nil
              end

            nil ->
              send.(%Matrix2051.Irc.Command{
                command: "FAIL",
                params: ["*", "ACCOUNT_REQUIRED", "You must authenticate."]
              })

              close_connection(sup_pid)

            _ ->
              # Nick does not match the matrix user id, forcefully change it.
              send_welcome(sup_pid, command)
              Matrix2051.IrcConn.State.set_nick(state, user_id)

              send.(%Matrix2051.Irc.Command{
                source: nick <> "!" <> String.replace(user_id, ~r/:/, "@"),
                command: "NICK",
                params: [user_id]
              })

              Matrix2051.IrcConn.State.set_registered(state)

              case Registry.lookup(Matrix2051.Registry, {sup_pid, :matrix_poller}) do
                [{matrix_poller, _}] -> send(matrix_poller, :start_polling)
                [] -> nil
              end
          end
        else
          loop_connreg(sup_pid, nick, gecos, user_id, waiting_cap_end)
        end
    end
  end

  # Returns a function that can be used to reply to the given command
  defp make_send_function(command, sup_pid) do
    writer = Matrix2051.IrcConn.Supervisor.writer(sup_pid)
    state = Matrix2051.IrcConn.Supervisor.state(sup_pid)
    capabilities = Matrix2051.IrcConn.State.capabilities(state)

    fn cmd ->
      tags =
        case Map.get(command.tags, "label") do
          nil -> cmd.tags
          label -> Map.put_new(cmd.tags, "label", label)
        end

      cmd = %Matrix2051.Irc.Command{cmd | tags: tags}

      Matrix2051.IrcConn.Writer.write_command(
        writer,
        Matrix2051.Irc.Command.downgrade(cmd, capabilities)
      )
    end
  end

  # Returns a function that can be used to reply to the given command with multiple replies
  defp make_send_label_batch_function(command, sup_pid) do
    writer = Matrix2051.IrcConn.Supervisor.writer(sup_pid)
    state = Matrix2051.IrcConn.Supervisor.state(sup_pid)
    capabilities = Matrix2051.IrcConn.State.capabilities(state)

    fn commands ->
      case Map.get(command.tags, "label") do
        nil ->
          # no label, don't use a batch.
          commands
          |> Enum.map(fn cmd ->
            Matrix2051.IrcConn.Writer.write_command(
              writer,
              Matrix2051.Irc.Command.downgrade(cmd, capabilities)
            )
          end)

        label ->
          batch_id =
            :crypto.strong_rand_bytes(20)
            |> Base.url_encode64(padding: false)
            |> String.replace(~r"_", "")

          open_batch = %Matrix2051.Irc.Command{
            tags: %{"label" => label},
            command: "BATCH",
            params: ["+" <> batch_id, "labeled-response"]
          }

          close_batch = %Matrix2051.Irc.Command{command: "BATCH", params: ["-" <> batch_id]}

          Stream.concat([
            [open_batch],
            commands
            |> Stream.map(fn cmd -> %{cmd | tags: Map.put(cmd.tags, "batch", batch_id)} end),
            [close_batch]
          ])
          |> Stream.map(fn cmd ->
            Matrix2051.IrcConn.Writer.write_command(
              writer,
              Matrix2051.Irc.Command.downgrade(cmd, capabilities)
            )
          end)
          |> Stream.run()
      end
    end
  end

  # Handles a connection registration command, ie. only NICK/USER/CAP/AUTHENTICATE.
  # Returns nil, {:nick, new_nick}, {:user, new_gecos}, {:authenticate, user_id},
  # :got_cap_ls, or :got_cap_end.
  defp handle_connreg(sup_pid, command, nick) do
    send = make_send_function(command, sup_pid)

    send_numeric = fn numeric, params ->
      first_param =
        case nick do
          nil -> "*"
          _ -> nick
        end

      send.(%Matrix2051.Irc.Command{
        source: "server",
        command: numeric,
        params: [first_param | params]
      })
    end

    send_needmoreparams = fn ->
      send_numeric.("461", [command.command, "Invalid number of parameters"])
    end

    case {command.command, command.params} do
      {"NICK", [nick | _]} ->
        {:nick, nick}

      {"NICK", _} ->
        send_needmoreparams.()
        nil

      {"USER", [_, _, _, gecos | _]} ->
        {:user, gecos}

      {"USER", _} ->
        send_needmoreparams.()
        nil

      {"CAP", ["LS", "302"]} ->
        caps =
          @capabilities
          |> Map.to_list()
          |> Enum.sort_by(fn {k, _v} -> k end)
          |> Enum.map(fn {k, {_, v}} ->
            case v do
              nil -> k
              _ -> k <> "=" <> v
            end
          end)
          |> Enum.join(" ")

        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LS", caps]})
        :got_cap_ls

      {"CAP", ["LS" | _]} ->
        caps =
          @capabilities
          |> Map.to_list()
          |> Enum.sort_by(fn {k, {_, _v}} -> k end)
          |> Enum.map(fn {k, _v} -> k end)
          |> Enum.join(" ")

        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LS", caps]})
        :got_cap_ls

      {"CAP", ["LIST" | _]} ->
        # TODO: return sasl when relevant
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LIST"]})
        nil

      {"CAP", ["REQ", caps | _]} ->
        cap_atoms =
          caps
          |> String.split(" ", trim: true)
          |> Enum.map(fn cap ->
            case Map.get(@capabilities, cap) do
              {atom, _} -> atom
              nil -> nil
            end
          end)

        all_caps_known = Enum.all?(cap_atoms, fn atom -> atom != nil end)

        if all_caps_known do
          send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "ACK", caps]})
          state = Matrix2051.IrcConn.Supervisor.state(sup_pid)
          Matrix2051.IrcConn.State.add_capabilities(state, cap_atoms)
        else
          send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "NAK", caps]})
        end

        nil

      {"CAP", ["END" | _]} ->
        :got_cap_end

      {"CAP", [subcommand | _]} ->
        # ERR_INVALIDCAPCMD
        send_numeric.("410", [subcommand, "Invalid CAP subcommand"])

        nil

      {"CAP", []} ->
        # ERR_NEEDMOREPARAMS
        send_numeric.("461", ["CAP", "Missing CAP subcommand"])

        nil

      {"AUTHENTICATE", ["PLAIN" | _]} ->
        send.(%Matrix2051.Irc.Command{command: "AUTHENTICATE", params: ["+"]})
        nil

      {"AUTHENTICATE", [param | _]} ->
        # this catches both invalid mechs and actual PLAIN message.
        # FIXME: add some state to tell the two apart.

        # TODO: support multi-line AUTHENTICATE

        matrix_client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)

        case Matrix2051.MatrixClient.Client.user_id(matrix_client) do
          nil ->
            case Base.decode64(param) do
              {:ok, sasl_message} ->
                case String.split(sasl_message, "\x00") do
                  [_authzid, authcid, passwd] ->
                    case Matrix2051.Matrix.Misc.parse_userid(authcid) do
                      {:ok, {local_name, hostname}} ->
                        user_id = authcid

                        case Matrix2051.MatrixClient.Client.connect(
                               matrix_client,
                               local_name,
                               hostname,
                               passwd
                             ) do
                          {:ok} ->
                            # RPL_LOGGEDIN
                            nuh =
                              case nick do
                                nil -> "*"
                                _ -> "#{nick}!#{local_name}@#{hostname}"
                              end

                            send_numeric.("900", [
                              nuh,
                              user_id,
                              "You are now logged in as " <> user_id
                            ])

                            # RPL_SASLSUCCESS
                            send_numeric.("903", ["Authentication successful"])
                            {:authenticate, user_id}

                          {:error, _, error_message} ->
                            # ERR_SASLFAIL
                            send_numeric.("904", [error_message])
                            nil
                        end

                      {:error, error_message} ->
                        # ERR_SASLFAIL
                        send_numeric.("904", ["Invalid account/user id: " <> error_message])
                        nil
                    end

                  _ ->
                    # ERR_SASLFAIL
                    send_numeric.("904", [
                      "Invalid format. If you are a developer, see https://datatracker.ietf.org/doc/html/rfc4616#section-2"
                    ])

                    nil
                end

              {:error} ->
                # RPL_SASLMECHS
                send_numeric.("907", ["PLAIN", "is the only available SASL mechanism"])
            end

          user_id ->
            send_numeric.("907", ["You are already authenticated, as " <> user_id])
            nil
        end

      {"REGISTER", ["*", email, password | _]} ->
        case nick do
          nil ->
            send.("FAIL", [
              "REGISTER",
              "NEED_NICK",
              "*",
              "You must have a nickname set before registering"
            ])

          _ ->
            register(sup_pid, command, nick, nick, email, password)
        end

      {"REGISTER", [account_name, email, password | _]} ->
        case nick do
          nil ->
            send.(%Matrix2051.Irc.Command{
              command: "FAIL",
              params: [
                "REGISTER",
                "NEED_NICK",
                "*",
                "You must have a nickname set before registering"
              ]
            })

          ^account_name ->
            register(sup_pid, command, nick, nick, email, password)

          _ ->
            send.(%Matrix2051.Irc.Command{
              command: "FAIL",
              params: [
                "REGISTER",
                "ACCOUNT_NAME_MUST_BE_NICK",
                account_name,
                "Your account name must be the same as your nick (" <>
                  nick <> "); cannot register " <> account_name
              ]
            })
        end

      {"REGISTER", _} ->
        send_needmoreparams.()
        nil

      {"VERIFY", _} ->
        send.(%Matrix2051.Irc.Command{
          command: "FAIL",
          params: [
            "VERIFY",
            "TEMPORARILY_UNAVAILABLE",
            nick,
            "Verification is not implemented yet."
          ]
        })

      {"PING", [cookie]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})
        nil

      {"PING", [_, cookie | _]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})
        nil

      {"PING", []} ->
        send_needmoreparams.()
        nil

      {"QUIT", []} ->
        send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["Client quit"]})
        close_connection(sup_pid)

      {"QUIT", [reason | _]} ->
        send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["Quit: " <> reason]})
        close_connection(sup_pid)

      _ ->
        send_numeric.("421", [command.command, "Unknown command (you are not registered)"])
        nil
    end
  end

  # Sends the burst of post-registration messages
  defp send_welcome(sup_pid, command) do
    send = make_send_function(command, sup_pid)
    state = Matrix2051.IrcConn.Supervisor.state(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(state)

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{source: "server", command: numeric, params: [nick | params]})
    end

    # RPL_WELCOME
    send_numeric.("001", ["Welcome to this Matrix bouncer."])
    # RPL_ISUPPORT
    send_numeric.("005", [
      "CASEMAPPING=rfc3454",
      "CLIENTTAGDENY=*,-draft/reply",
      "CHANLIMIT=",
      "CHANTYPES=#!",
      "TARGMAX=JOIN:1,PART:1",
      "UTF8ONLY",
      "are supported by this server"
    ])

    # RPL_MOTDSTART
    send_numeric.("375", ["- Message of the day"])
    # RPL_MOTD
    send_numeric.("372", ["Welcome to Matrix2051, a Matrix bouncer."])
    # RPL_ENDOFMOTD
    send_numeric.("376", ["End of /MOTD command."])
  end

  # Handles the REGISTER command
  defp register(sup_pid, command, nick, user_id, _email, password) do
    matrix_client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)

    send = make_send_function(command, sup_pid)

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{source: "server", command: numeric, params: [nick | params]})
    end

    # This function is only called if the nick matches the user_id, and the
    # nick was already validated.
    {:ok, {local_name, hostname}} = Matrix2051.Matrix.Misc.parse_userid(user_id)

    case Matrix2051.MatrixClient.Client.register(matrix_client, local_name, hostname, password) do
      {:ok, user_id} ->
        send.(%Matrix2051.Irc.Command{
          command: "REGISTER",
          params: ["SUCCESS", user_id, "You are now registered as " <> user_id]
        })

        send_numeric.("900", [nick2nuh(user_id), user_id, "You are now logged in as " <> user_id])

        {:authenticate, user_id}

      {:error, :invalid_username, message} ->
        send.(%Matrix2051.Irc.Command{
          command: "FAIL",
          params: ["REGISTER", "BAD_ACCOUNT_NAME", user_id, "Bad account name: " <> message]
        })

        nil

      {:error, :user_in_use, message} ->
        send.(%Matrix2051.Irc.Command{
          command: "FAIL",
          params: ["REGISTER", "ACCOUNT_EXISTS", user_id, "Account already exists: " <> message]
        })

        nil

      {:error, :exclusive, message} ->
        send.(%Matrix2051.Irc.Command{
          command: "FAIL",
          params: [
            "REGISTER",
            "BAD_ACCOUNT_NAME",
            user_id,
            "Account name is exclusive: " <> message
          ]
        })

        nil

      {:error, :unknown, message} ->
        send.(%Matrix2051.Irc.Command{
          command: "FAIL",
          params: [
            "REGISTER",
            "TEMPORARILY_UNAVAILABLE",
            user_id,
            "Could not register: " <> message
          ]
        })

        nil
    end
  end

  # Handles a command (after connection registration is finished)
  defp handle(sup_pid, command) do
    state = Matrix2051.IrcConn.Supervisor.state(sup_pid)

    case command.tags do
      %{"batch" => reference_tag} ->
        Matrix2051.IrcConn.State.add_batch_command(state, reference_tag, command)

      _ ->
        handle_unbatched(sup_pid, command)
    end
  end

  # Called by handle/3 when the command isn't part of a batch
  defp handle_unbatched(sup_pid, command) do
    state = Matrix2051.IrcConn.Supervisor.state(sup_pid)
    matrix_state = Matrix2051.IrcConn.Supervisor.matrix_state(sup_pid)
    matrix_client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(state)

    send = make_send_function(command, sup_pid)
    send_label_batch = make_send_label_batch_function(command, sup_pid)

    make_numeric = fn numeric, params ->
      first_param =
        case nick do
          nil -> "*"
          _ -> nick
        end

      %Matrix2051.Irc.Command{source: "server", command: numeric, params: [first_param | params]}
    end

    send_numeric = fn numeric, params ->
      send.(make_numeric.(numeric, params))
    end

    send_needmoreparams = fn ->
      send_numeric.("461", [command.command, "Need more parameters"])
    end

    send_ack = fn -> send.(%Matrix2051.Irc.Command{command: "ACK", params: []}) end

    case {command.command, command.params} do
      {"NICK", [new_nick | _]} ->
        # ERR_ERRONEUSNICKNAME; only the MatrixID is allowed as nick
        send_numeric.("432", [new_nick, "You may not change your nickname."])

      {"NICK", _} ->
        send_needmoreparams.()

      {"USER", _} ->
        nil

      {"CAP", ["LIST" | _]} ->
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LIST", "sasl"]})

      {"CAP", [subcommand | _]} ->
        # ERR_INVALIDCAPCMD
        send_numeric.("410", [subcommand, "Invalid CAP subcommand"])

      {"CAP", []} ->
        # ERR_NEEDMOREPARAMS
        send_numeric.("410", ["CAP", "Missing CAP subcommand"])

      {"PING", [cookie]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})

      {"PING", [_, cookie | _]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})

      {"PING", []} ->
        send_needmoreparams.()

      {"QUIT", []} ->
        send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["Client quit"]})
        close_connection(sup_pid)

      {"QUIT", [reason | _]} ->
        send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["Quit: " <> reason]})
        close_connection(sup_pid)

      {"REGISTER", _} ->
        send.(%Matrix2051.Irc.Command{
          command: "FAIL",
          params: ["REGISTER", "ALREADY_AUTHENTICATED", nick, "You are already authenticated."]
        })

      {"VERIFY", _} ->
        send.(%Matrix2051.Irc.Command{
          command: "FAIL",
          params: ["VERIFY", "ALREADY_AUTHENTICATED", nick, "You are already authenticated."]
        })

      {"JOIN", [channel | _]} ->
        case Matrix2051.MatrixClient.Client.join_room(matrix_client, channel) do
          {:ok, _room_id} ->
            # Should we send a JOIN?
            send_ack.()

          {:error, :already_joined, _room_id} ->
            send_ack.()

          {:error, :banned_or_missing_invite, message} ->
            # ERR_BANNEDFROMCHAN
            send_numeric.("474", [channel, "Cannot join channel: " <> message])

          {:error, :unknown, message} ->
            # ERR_NOSUCHCHANNEL
            send_numeric.("403", [channel, "Cannot join channel: " <> message])
        end

      {"JOIN", _} ->
        send_needmoreparams.()

      {"PRIVMSG", [channel, text | _]} ->
        send_message(
          sup_pid,
          Map.get(command.tags, "+draft/reply"),
          Map.get(command.tags, "label"),
          :privmsg,
          channel,
          text
        )

      {"PRIVMSG", _} ->
        send_needmoreparams.()

      {"NOTICE", [channel, text | _]} ->
        send_message(
          sup_pid,
          Map.get(command.tags, "+draft/reply"),
          Map.get(command.tags, "label"),
          :notice,
          channel,
          text
        )

      {"NOTICE", _} ->
        send_needmoreparams.()

      {"TAGMSG", [_channel | _]} ->
        nil

      {"TAGMSG", _} ->
        send_needmoreparams.()

      {"WHO", [target, "o" | _]} ->
        # no RPL_WHOREPLY because no operators

        # RPL_ENDOFWHO
        send_numeric.(315, [target, "End of WHO list"])

      {"WHO", [target | _]} ->
        if Enum.member?(["#", "!"], String.slice(target, 0, 1)) do
          channel = target

          Matrix2051.MatrixClient.State.queue_on_channel_sync(
            matrix_state,
            channel,
            fn _room_id, room ->
              commands =
                room.members
                |> Stream.map(fn member ->
                  [local_name, hostname] = String.split(nick, ":", parts: 2)
                  # RPL_WHOREPLY
                  make_numeric.("352", [
                    target,
                    local_name,
                    hostname,
                    "*",
                    member,
                    "H",
                    "0 " <> member
                  ])
                end)

              # RPL_ENDOFWHO
              last_command = make_numeric.(315, [target, "End of WHO list"])

              send_label_batch.(Stream.concat(commands, [last_command]))
            end
          )
        else
          # target is a nick
          [local_name, hostname] = String.split(target, ":", parts: 2)

          send_label_batch.([
            make_numeric.("352", ["*", local_name, hostname, "*", target, "H", "0 " <> target]),
            make_numeric.(315, [target, "End of WHO list"])
          ])
        end

      {"WHO", _} ->
        send_needmoreparams.()

      {"BATCH", [first_param | params]} ->
        {first_char, reference_tag} = String.split_at(first_param, 1)

        case {first_char, params} do
          {"+", [type | _other_params]} ->
            # Opening batch
            if Enum.member?(@valid_batch_types, type) do
              Matrix2051.IrcConn.State.create_batch(state, reference_tag, command)
            else
              # Ignore the batch.
            end

          {"-", []} ->
            # Closing batch
            handle_batch(
              sup_pid,
              reference_tag,
              Matrix2051.IrcConn.State.pop_batch(state, reference_tag)
            )

          _ ->
            send.(%Matrix2051.Irc.Command{
              command: "ERROR",
              params: ["Invalid BATCH arguments: " <> Enum.join(command.params, " ")]
            })

            close_connection(sup_pid)
        end

      {"BATCH", _} ->
        send_needmoreparams.()

      _ ->
        send_numeric.("421", [command.command, "Unknown command"])
    end
  end

  defp handle_batch(__sup_pid, _reference_tag, nil) do
    # Closing a non-existing batch; just ignore it.
  end

  defp handle_batch(sup_pid, _reference_tag, {opening_command, commands}) do
    send = make_send_function(opening_command, sup_pid)

    inner_commands =
      commands |> Enum.map(fn msg -> msg.command end) |> MapSet.new() |> Enum.to_list()

    type_and_channel =
      case {opening_command.params, inner_commands} do
        {[], _} ->
          # Missing tag, should have been caught earlier.
          nil

        {[_tag], _} ->
          send.(%Matrix2051.Irc.Command{
            command: "ERROR",
            params: ["multiline batch is missing a type and a target."]
          })

          close_connection(sup_pid)
          nil

        {[_tag, _type], _} ->
          send.(%Matrix2051.Irc.Command{
            command: "ERROR",
            params: ["multiline batch is missing a target."]
          })

          close_connection(sup_pid)
          nil

        {[_tag, _type, channel | _], ["PRIVMSG"]} ->
          {:privmsg, channel}

        {[_tag, _type, channel | _], ["NOTICE"]} ->
          {:notice, channel}

        {_, [command]} ->
          send.(%Matrix2051.Irc.Command{
            command: "ERROR",
            params: ["command #{command} not allowed in multiline batches."]
          })

          close_connection(sup_pid)
          nil

        {_, []} ->
          # Empty multiline batch; just ignore it.
          nil

        {_, commands} ->
          send.(%Matrix2051.Irc.Command{
            command: "ERROR",
            params: ["inconsistent commands in multiline batch: " <> Kernel.inspect(commands)]
          })

          close_connection(sup_pid)
          nil
      end

    case type_and_channel do
      nil ->
        nil

      {type, channel} ->
        text =
          commands
          |> Enum.map(fn command ->
            case command do
              %Matrix2051.Irc.Command{
                tags: %{"draft/multiline-concat" => _},
                params: [_target, text | _]
              } ->
                text

              %Matrix2051.Irc.Command{params: [_target, text | _]} ->
                "\n" <> text
            end
          end)
          |> Enum.join("")
          |> String.replace_leading("\n", "")

        send_message(
          sup_pid,
          Map.get(opening_command.tags, "+draft/reply"),
          Map.get(opening_command.tags, "label"),
          type,
          channel,
          text
        )
    end
  end

  defp send_message(sup_pid, reply_to, label, type, channel, text) do
    writer = Matrix2051.IrcConn.Supervisor.writer(sup_pid)
    matrix_client = Matrix2051.IrcConn.Supervisor.matrix_client(sup_pid)
    send = fn cmd -> Matrix2051.IrcConn.Writer.write_command(writer, cmd) end

    # If the client provided a label, use it as txnId on Matrix's side.
    # This way we can parse it when receiving the echo from Matrix's event
    # stream instead of storing state.
    # Otherwise, generate a random transaction id.
    {msgtype, body} =
      case type do
        :privmsg ->
          case Regex.named_captures(~r/\x01ACTION (?P<body>.*)\x01/s, text) do
            %{"body" => body} -> {"m.emote", body}
            _ -> {"m.text", text}
          end

        :notice ->
          {"m.notice", text}
      end

    event = %{"msgtype" => msgtype, "body" => body}

    event =
      case reply_to do
        nil ->
          event

        _ ->
          Map.put(event, "m.relates_to", %{
            "m.in_reply_to" => %{
              "event_id" => reply_to
            }
          })
      end

    result =
      Matrix2051.MatrixClient.Client.send_event(
        matrix_client,
        channel,
        label,
        "m.room.message",
        event
      )

    case result do
      {:ok, _} ->
        nil

      {:error, error} ->
        send.(%Matrix2051.Irc.Command{
          source: "server",
          command: "NOTICE",
          params: [channel, "Error while sending message: " <> Kernel.inspect(error)]
        })
    end
  end

  defp close_connection(sup_pid) do
    writer = Matrix2051.IrcConn.Supervisor.writer(sup_pid)
    Matrix2051.IrcConn.Writer.close(writer)
    DynamicSupervisor.terminate_child(Matrix2051.IrcServer, sup_pid)
  end

  defp nick2nuh(nick) do
    [local_name, hostname] = String.split(nick, ":", parts: 2)
    "#{nick}!#{local_name}@#{hostname}"
  end
end
