defmodule Matrix2051.IrcConn.Handler do
  @moduledoc """
    Receives commands from the reader and dispatches them.
  """

  use Task, restart: :permanent

  def start_link(args) do
    {sup_mod, sup_pid} = args
    Task.start_link(__MODULE__, :run, [sup_mod, sup_pid])
  end

  # set of capabilities that we will show in CAP LS and accept with ACK;
  # along with their value (shown in CAP LS 302)
  @capabilities %{
    # https://github.com/ircv3/ircv3-specifications/pull/435
    "draft/account-registration" => {:account_registration, "before-connect"},
    # https://ircv3.net/specs/extensions/extended-join.html
    "extended-join" => {:extended_join, nil},
    # https://ircv3.net/specs/extensions/labeled-response
    "labeled-response" => {:labeled_response, nil},
    # https://ircv3.net/specs/extensions/sasl-3.1
    "sasl" => {:sasl, "PLAIN"}
  }

  @doc """
    Main loop.

    Starts by calling loop_connreg, which deals with the connection registration
    (https://modern.ircdocs.horse/#connection-registration) and returns when
    it is done.
    Then loops forever.
  """
  def run(sup_mod, sup_pid) do
    loop_connreg(sup_mod, sup_pid)
    loop(sup_mod, sup_pid)
  end

  defp loop(sup_mod, sup_pid) do
    receive do
      command ->
        handle(sup_mod, sup_pid, command)
    end

    loop(sup_mod, sup_pid)
  end

  defp loop_connreg(
         sup_mod,
         sup_pid,
         nick \\ nil,
         gecos \\ nil,
         user_id \\ nil,
         waiting_cap_end \\ false
       ) do
    writer = sup_mod.writer(sup_pid)
    send = fn cmd -> Matrix2051.IrcConn.Writer.write_command(writer, cmd) end

    receive do
      command ->
        {nick, gecos, user_id, waiting_cap_end} =
          case handle_connreg(sup_mod, sup_pid, command, nick) do
            nil -> {nick, gecos, user_id, waiting_cap_end}
            {:nick, nick} -> {nick, gecos, user_id, waiting_cap_end}
            {:user, gecos} -> {nick, gecos, user_id, waiting_cap_end}
            {:authenticate, user_id} -> {nick, gecos, user_id, waiting_cap_end}
            :got_cap_ls -> {nick, gecos, user_id, true}
            :got_cap_end -> {nick, gecos, user_id, false}
          end

        if nick != nil && gecos != nil && !waiting_cap_end do
          # Registration finished. Send welcome messages and return to the main loop
          state = sup_mod.state(sup_pid)

          Matrix2051.IrcConn.State.set_nick(state, nick)
          Matrix2051.IrcConn.State.set_gecos(state, gecos)
          Matrix2051.IrcConn.State.set_registered(state)

          case user_id do
            # all good
            ^nick ->
              send_welcome(sup_mod, sup_pid, command)

            nil ->
              send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["You must authenticate."]})
              close_connection(sup_mod, sup_pid)

            _ ->
              # Nick does not match the matrix user id, forcefully change it.
              send_welcome(sup_mod, sup_pid, command)
              Matrix2051.IrcConn.State.set_nick(state, user_id)
              send.(%Matrix2051.Irc.Command{source: nick, command: "NICK", params: [user_id]})
          end
        else
          loop_connreg(sup_mod, sup_pid, nick, gecos, user_id, waiting_cap_end)
        end
    end
  end

  # Returns a function that can be used to reply to the given command
  defp make_send_function(command, sup_mod, sup_pid) do
    writer = sup_mod.writer(sup_pid)
    state = sup_mod.state(sup_pid)
    capabilities = Matrix2051.IrcConn.State.capabilities(state)

    fn cmd ->
      tags = cmd.tags

      tags =
        case {Enum.member?(capabilities, :labeled_response), Map.get(command.tags, "label")} do
          {true, label} when label != nil -> Map.put_new(tags, "label", label)
          _ -> tags
        end

      cmd = %Matrix2051.Irc.Command{cmd | tags: tags}
      Matrix2051.IrcConn.Writer.write_command(writer, cmd)
    end
  end

  # Handles a connection registration command, ie. only NICK/USER/CAP/AUTHENTICATE.
  # Returns nil, {:nick, new_nick}, {:user, new_gecos}, {:authenticate, user_id},
  # :got_cap_ls, or :got_cap_end.
  defp handle_connreg(sup_mod, sup_pid, command, nick) do
    send = make_send_function(command, sup_mod, sup_pid)

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{command: numeric, params: ["*" | params]})
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
            {atom, _} = Map.get(@capabilities, cap)
            atom
          end)

        all_caps_known = Enum.all?(cap_atoms, fn atom -> atom != nil end)

        if all_caps_known do
          send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "ACK", caps]})
          state = sup_mod.state(sup_pid)
          Matrix2051.IrcConn.State.add_capabilities(state, cap_atoms)
        else
          send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "NAK", caps]})
        end

        nil

      {"CAP", ["END" | _]} ->
        :got_cap_end

      {"CAP", [subcommand | _]} ->
        # ERR_INVALIDCAPCMD
        send.(%Matrix2051.Irc.Command{
          command: "410",
          params: ["*", subcommand, "Invalid CAP subcommand"]
        })

        nil

      {"CAP", []} ->
        # ERR_NEEDMOREPARAMS
        send.(%Matrix2051.Irc.Command{
          command: "410",
          params: ["*", "CAP", "Missing CAP subcommand"]
        })

        nil

      {"AUTHENTICATE", ["PLAIN" | _]} ->
        send.(%Matrix2051.Irc.Command{command: "AUTHENTICATE", params: ["+"]})
        nil

      {"AUTHENTICATE", [param | _]} ->
        # this catches both invalid mechs and actual PLAIN message.
        # FIXME: add some state to tell the two apart.

        # TODO: support multi-line AUTHENTICATE

        matrix_client = sup_mod.matrix_client(sup_pid)

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
                            send_numeric.("900", [
                              "*",
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
                send_numeric.("907", ["*", "PLAIN", "is the only available SASL mechanism"])
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
            register(sup_mod, sup_pid, command, nick, email, password)
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
            register(sup_mod, sup_pid, command, nick, email, password)

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
        close_connection(sup_mod, sup_pid)

      {"QUIT", [reason | _]} ->
        send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["Quit: " <> reason]})
        close_connection(sup_mod, sup_pid)

      _ ->
        send_numeric.("421", [command.command, "Unknown command (you are not registered)"])
        nil
    end
  end

  # Sends the burst of post-registration messages
  defp send_welcome(sup_mod, sup_pid, command) do
    send = make_send_function(command, sup_mod, sup_pid)

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{command: numeric, params: ["*" | params]})
    end

    # RPL_WELCOME
    send_numeric.("001", ["*", "Welcome to this Matrix bouncer."])
    # RPL_ISUPPORT
    send_numeric.("005", ["*", "CASEMAPPING=rfc3454", "CHANLIMIT=", "TARGMAX=JOIN:1,PART:1"])
    # RPL_MOTDSTART
    send_numeric.("375", ["*", "- Message of the day"])
    # RPL_MOTD
    send_numeric.("372", ["*", "Welcome to Matrix2051, a Matrix bouncer."])
    # RPL_ENDOFMOTD
    send_numeric.("376", ["*", "End of /MOTD command."])
  end

  # Handles the REGISTER command
  defp register(sup_mod, sup_pid, command, user_id, _email, password) do
    matrix_client = sup_mod.matrix_client(sup_pid)

    send = make_send_function(command, sup_mod, sup_pid)

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{command: numeric, params: ["*" | params]})
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

        send_numeric.("900", ["*", user_id, "You are now logged in as " <> user_id])

        # TODO: change nick if it does not match user_id

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
  defp handle(sup_mod, sup_pid, command) do
    state = sup_mod.state(sup_pid)
    matrix_client = sup_mod.matrix_client(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(state)
    capabilities = Matrix2051.IrcConn.State.capabilities(state)

    send = make_send_function(command, sup_mod, sup_pid)

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{command: numeric, params: ["*" | params]})
    end

    send_needmoreparams = fn ->
      send_numeric.("461", [command.command, "Need more parameters"])
    end

    send_ack = fn ->
      case {Enum.member?(capabilities, :labeled_response), Map.get(command.tags, "label")} do
        {true, label} when label != nil ->
          send.(%Matrix2051.Irc.Command{command: "ACK", params: []})

        _ ->
          nil
      end
    end

    case {command.command, command.params} do
      {"NICK", [new_nick | _]} ->
        # ERR_ERRONEUSNICKNAME; only the MatrixID is allowed as nick
        send.(%Matrix2051.Irc.Command{
          command: "432",
          params: [nick, new_nick, "You may not change your nickname."]
        })

      {"NICK", _} ->
        send_needmoreparams.()

      {"USER", _} ->
        nil

      {"CAP", ["LIST" | _]} ->
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LIST", "sasl"]})

      {"CAP", [subcommand | _]} ->
        # ERR_INVALIDCAPCMD
        send.(%Matrix2051.Irc.Command{
          command: "410",
          params: ["*", subcommand, "Invalid CAP subcommand"]
        })

      {"CAP", []} ->
        # ERR_NEEDMOREPARAMS
        send.(%Matrix2051.Irc.Command{
          command: "410",
          params: ["*", "CAP", "Missing CAP subcommand"]
        })

      {"PING", [cookie]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})

      {"PING", [_, cookie | _]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})

      {"PING", []} ->
        send_needmoreparams.()

      {"QUIT", []} ->
        send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["Client quit"]})
        close_connection(sup_mod, sup_pid)

      {"QUIT", [reason | _]} ->
        send.(%Matrix2051.Irc.Command{command: "ERROR", params: ["Quit: " <> reason]})
        close_connection(sup_mod, sup_pid)

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
            account_name = nick
            # TODO: get the actual display name
            real_name = nick

            send.(%Matrix2051.Irc.Command{
              source: nick,
              command: "JOIN",
              params:
                if Enum.member?(capabilities, :extended_join) do
                  [channel, account_name, real_name]
                else
                  [channel]
                end
            })

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

      _ ->
        send_numeric.("421", [command.command, "Unknown command"])
    end
  end

  defp close_connection(sup_mod, sup_pid) do
    writer = sup_mod.writer(sup_pid)
    Matrix2051.IrcConn.Writer.close(writer)
    sup_mod.terminate()
  end
end
