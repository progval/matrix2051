{_parsed, []} =
  OptionParser.parse!(
    System.argv(),
    strict: []
  )

{:ok, matrix2051} = Matrix2051.start(:normal, [])

[{Matrix2051.Supervisor, supervisor, _, _}]  = Supervisor.which_children(matrix2051)
children = Supervisor.which_children(supervisor)
IO.inspect(children)
