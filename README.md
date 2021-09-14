# Matrix2051

An IRC server backed by Matrix. You can also see it as an IRC bouncer that
connects to Matrix homeservers instead of IRC servers.

## Module structure

### In supervision tree

* `matrix2051.exs` starts Matrix2051, which starts Matrix2051.Supervisor, which
  supervises:
  * `config.ex`: global config agent
  * `client_supervisor.ex`: supervises Matrix clients
    * `matrix/client.ex`: handles one connection to a Matrix homeserver, as a single user
  * `irc_server.ex`: handles connections from IRC clients.
    * `irc_conn/supervisor.ex`: spawned for each client connection
      * `irc_conn/state.ex`: stores the state of the connection
      * `irc_conn/writer.ex`: genserver holding the socket and allowing
        to write lines to it (and batches of lines in the future)
      * `irc_conn/handler.ex`: task busy-waiting on the incoming commands
        from the reader, answers to the simple ones, and dispatches more complex
        commands
      * `irc_conn/reader.ex`: task busy-waiting on the incoming lines,
        and sends them to the handler

### Outside supervision tree

* Matrix:
  * `matrix/raw_client.ex`: low-level Matrix client / thin wrapper around HTTP requests
* IRC:
  * `irc/command.ex`: IRC line manipulation
