{parsed, []} =
  OptionParser.parse!(
    System.argv(),
    strict: [matrix_id: :string]
  )

matrix_id = parsed[:matrix_id]

{:ok, matrix2051} = Matrix2051.start(:normal, [matrix_id: matrix_id])

[{Matrix2051.Supervisor, supervisor, _, _}]  = Supervisor.which_children(matrix2051)
children = Supervisor.which_children(supervisor)
IO.inspect(children)
