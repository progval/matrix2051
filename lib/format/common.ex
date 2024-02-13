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

defmodule M51.Format do
  # pairs of {irc_code, matrix_html_tag}
  # this excludes color ("\x03"), which must be handled with specific code.
  @translations [
    {"\x02", "strong"},
    {"\x02", "b"},
    {"\x11", "pre"},
    {"\x11", "code"},
    {"\x1d", "em"},
    {"\x1d", "i"},
    {"\x1e", "del"},
    {"\x1e", "strike"},
    {"\x1f", "u"},
    {"\n", "br"}
  ]

  def matrix2irc_map() do
    @translations
    |> Enum.map(fn {irc, matrix} -> {matrix, irc} end)
    |> Map.new()
  end

  def irc2matrix_map() do
    @translations
    |> Map.new()
  end

  @doc ~S"""
    Converts "org.matrix.custom.html" to IRC formatting.

    ## Examples

        iex> M51.Format.matrix2irc(~s(<b>foo</b>))
        "\x02foo\x02"

        iex> M51.Format.matrix2irc(~s(<a href="https://example.org">foo</a>))
        "foo <https://example.org>"

        iex> M51.Format.matrix2irc(~s(foo<br/>bar))
        "foo\nbar"

        iex> M51.Format.matrix2irc(~s(foo <font data-mx-color="#FF0000">bar</font> baz))
        "foo \x04FF0000bar\x0399,99 baz"
  """
  def matrix2irc(html, homeserver \\ nil) do
    tree = :mochiweb_html.parse("<html>" <> html <> "</html>")

    String.trim(
      M51.Format.Matrix2Irc.transform(tree, %M51.Format.Matrix2Irc.State{homeserver: homeserver})
    )
  end

  @doc ~S"""
    Converts IRC formatting to Matrix's plain text flavor and "org.matrix.custom.html"

    ## Examples

        iex> M51.Format.irc2matrix("\x02foo\x02")
        {"*foo*", "<b>foo</b>"}

        iex> M51.Format.irc2matrix("foo https://example.org bar")
        {"foo https://example.org bar", ~s(foo <a href="https://example.org">https://example.org</a> bar)}

        iex> M51.Format.irc2matrix("foo\nbar")
        {"foo\nbar", ~s(foo<br/>bar)}

        iex> M51.Format.irc2matrix("foo \x0304bar")
        {"foo bar", ~s(foo <font data-mx-color="#FF0000">bar</font>)}

  """
  def irc2matrix(text, nicklist \\ []) do
    stateful_tokens =
      (text <> "\x0f")
      |> M51.Format.Irc2Matrix.tokenize()
      |> Stream.transform(%M51.Format.Irc2Matrix.State{}, fn token, state ->
        {new_state, new_token} = M51.Format.Irc2Matrix.update_state(state, token)
        {[{state, new_state, new_token}], new_state}
      end)
      |> Enum.to_list()

    plain_text =
      stateful_tokens
      |> Enum.map(fn {previous_state, state, token} ->
        M51.Format.Irc2Matrix.make_plain_text(previous_state, state, token)
      end)
      |> Enum.join()

    html_tree =
      stateful_tokens
      |> Enum.flat_map(fn {previous_state, state, token} ->
        M51.Format.Irc2Matrix.make_html(previous_state, state, token, nicklist)
      end)

    html =
      {"html", [], html_tree}
      |> :mochiweb_html.to_html()
      |> IO.iodata_to_binary()

    html = Regex.replace(~R(<html>(.*\)</html>), html, fn _, content -> content end)
    # more compact
    html = Regex.replace(~R(<br />), html, fn _ -> "<br/>" end)

    {plain_text, html}
  end
end
