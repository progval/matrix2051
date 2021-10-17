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

{_parsed, []} =
  OptionParser.parse!(
    System.argv(),
    strict: []
  )

{:ok, matrix2051} = Matrix2051.start(:normal, [])

[{Matrix2051.Supervisor, supervisor, _, _}]  = Supervisor.which_children(matrix2051)
children = Supervisor.which_children(supervisor)
IO.inspect(children)
