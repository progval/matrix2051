defmodule Matrix2051.IrcConn.Handler do
  @moduledoc """
    Receives commands from the reader and dispatches them.
  """

  use Task, restart: :permanent

  def start_link(args) do
    {sup_mod, sup_pid} = args
    Task.start_link(__MODULE__, :loop, [sup_mod, sup_pid])
  end

  @doc """
    Main loop.

    Starts by calling loop_serve_registration, which deals with the registration
    (https://modern.ircdocs.horse/#connection-registration) and returns when
    registration is done
  """
  def loop(sup_mod, sup_pid) do
    loop_registration(sup_mod, sup_pid)

    receive do
      command ->
        handle(sup_mod, sup_pid, command)
    end

    loop(sup_mod, sup_pid)
  end

  defp loop_registration(
         sup_mod,
         sup_pid,
         nick \\ nil,
         gecos \\ nil,
         waiting_cap_end \\ false
       ) do
    receive do
      command ->
        {nick, gecos, waiting_cap_end} =
          case handle_registration(sup_mod, sup_pid, command) do
            nil -> {nick, gecos, waiting_cap_end}
            {:nick, nick} -> {nick, gecos, waiting_cap_end}
            {:user, gecos} -> {nick, gecos, waiting_cap_end}
            :got_cap_ls -> {nick, gecos, true}
            :got_cap_end -> {nick, gecos, false}
          end

        if nick != nil && gecos != nil && !waiting_cap_end do
          # Registration finished. Send welcome messages and return to the main loop
          state = sup_mod.state(sup_pid)
          Matrix2051.IrcConn.State.set_gecos(state, gecos)
          Matrix2051.IrcConn.State.set_registered(state)
          send_welcome(sup_mod, sup_pid, nick)
        else
          loop_registration(sup_mod, sup_pid, nick, gecos, waiting_cap_end)
        end
    end
  end

  # Handles a registration command, ie. only NICK/USER/CAP.
  # Returns nil, {:nick, new_nick}, {:user, new_gecos}, :got_cap_ls, or :got_cap_end.
  defp handle_registration(sup_mod, sup_pid, command) do
    writer = sup_mod.writer(sup_pid)

    send = fn cmd -> Matrix2051.IrcConn.Writer.write_command(writer, cmd) end

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{command: numeric, params: ["*" | params]})
    end

    send_needmoreparams = fn ->
      send_numeric.("461", [command.command, "Invalid number of parameters"])
    end

    case {command.command, command.params} do
      {"NICK", [nick | _]} ->
        # We have to somehow accept it (or force users to configure the correct one
        # in their client right away); so we just forcefully change the client's nick ASAP
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
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LS", ""]})
        :got_cap_ls

      {"CAP", ["LS" | _]} ->
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LS", ""]})
        :got_cap_ls

      {"CAP", ["LIST" | _]} ->
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LIST", ""]})
        nil

      {"CAP", ["REQ", caps | _]} ->
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "NAK", caps]})
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

      {"PING", [cookie]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})
        nil

      {"PING", [_, cookie | _]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})
        nil

      {"PING", []} ->
        send_needmoreparams.()
        nil

      _ ->
        send_numeric.("421", [command.command, "Unknown command (you are not registered)"])
        nil
    end
  end

  # Sends the burst of post-registration messages
  defp send_welcome(sup_mod, sup_pid, current_nick) do
    writer = sup_mod.writer(sup_pid)
    send = fn cmd -> Matrix2051.IrcConn.Writer.write_command(writer, cmd) end

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

    new_nick = Matrix2051.Config.matrix_id()

    if current_nick != new_nick do
      send.(%Matrix2051.Irc.Command{source: current_nick, command: "NICK", params: [new_nick]})
    end
  end

  # Handles a command (after registration is finished)
  defp handle(sup_mod, sup_pid, command) do
    state = sup_mod.state(sup_pid)
    writer = sup_mod.writer(sup_pid)
    nick = Matrix2051.IrcConn.State.nick(state)

    send = fn cmd -> Matrix2051.IrcConn.Writer.write_command(writer, cmd) end

    send_numeric = fn numeric, params ->
      send.(%Matrix2051.Irc.Command{command: numeric, params: ["*" | params]})
    end

    send_needmoreparams = fn ->
      send_numeric.("461", [command.command, "Need more parameters"])
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
        send.(%Matrix2051.Irc.Command{command: "CAP", params: ["*", "LIST", ""]})

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
        nil

      {"PING", [_, cookie | _]} ->
        send.(%Matrix2051.Irc.Command{command: "PONG", params: [cookie]})
        nil

      {"PING", []} ->
        send_needmoreparams.()
        nil

      _ ->
        send_numeric.("421", [command.command, "Unknown command"])
    end
  end
end
