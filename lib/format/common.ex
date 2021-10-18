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

defmodule Matrix2051.Format do
  # pairs of {irc_code, matrix_html_tag}
  # this excludes color ("\x03"), which must be handled with specific code.
  @translations [
    {"\x02", "strong"},
    {"\x02", "b"},
    {"\x11", "pre"},
    {"\x11", "code"},
    {"\x1d", "em"},
    {"\x1d", "i"},
    {"\x1f", "u"},
    {"\x1e", "strike"},
    {"\n", "p"}
  ]

  def matrix2irc_map() do
    @translations
    |> Enum.map(fn {irc, matrix} -> {matrix, irc} end)
    |> Map.new()
  end

  @doc ~S"""
    Converts "org.matrix.custom.html" to IRC formatting.

    ## Examples

        iex> Matrix2051.Format.matrix2irc(~s(<b>foo</b>))
        "\x02foo\x02"

        iex> Matrix2051.Format.matrix2irc(~s(<a href="https://example.org">foo</a>))
        "foo <https://example.org>"

        iex> Matrix2051.Format.matrix2irc(~s(foo<br/>bar))
        "foo\nbar"
  """
  def matrix2irc(html) do
    {:ok, {parts, [], [], []}} =
      Saxy.parse_string(
        "<root>" <> Regex.replace(~r/< *br *>/, html, "<br/>") <> "</root>",
        Matrix2051.Format.Matrix2Irc.Handler,
        {[], [], [], []}
      )

    String.trim(Enum.join(Enum.reverse(parts)))
  end
end
