# Matrix2051

An IRC server backed by Matrix. You can also see it as an IRC bouncer that
connects to Matrix homeservers instead of IRC servers.

## Supervision tree and module description

* matrix2051.exc starts Matrix2051, which starts Matrix2051.Supervisor, which
  supervises:
  * Matrix2051.Config: global config agent
  * Matrix2051.MatrixClient: handles connections to the Matrix homeserver
    (only one, for now)
  * Matrix2051.IrcServer: handles connections from IRC clients.
    * Matrix2051.IrcConnSupervisor: spawned for each client connection
      * Matrix2051.IrcConnState: stores the state of the connection
      * Matrix2051.IrcConnWriter: genserver holding the socket and allowing
        to write lines to it (and batches of lines in the future)
      * Matrix2051.IrcConnReader: task busy-waiting on the incoming lines,
        and dispatches them
