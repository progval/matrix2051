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

defmodule M51.Format.Matrix2Irc.State do
  defstruct homeserver: nil,
            preserve_whitespace: false,
            color: {nil, nil}
end

defmodule M51.Format.Matrix2Irc do
  @simple_tags M51.Format.matrix2irc_map()

  def transform(s, state) when is_binary(s) do
    # Pure text; just replace sequences of newlines with a space
    # (unless there is already a space)
    if state.preserve_whitespace do
      s
    else
      Regex.replace(~r/([\n\r]+ ?[\n\r]*| [\n\r]+)/, s, " ")
    end
  end

  def transform({"a", attributes, children}, state) do
    case attributes |> Map.new() |> Map.get("href") do
      nil ->
        transform_children(children, state)

      link ->
        case Regex.named_captures(
               ~r{https://matrix.to/#/((@|%40)(?<userid>[^/?]*)|(!|%21)(?<roomid>[^/#]*)|(#|%23)(?<roomalias>[^/?]*))(/.*)?(\?.*)?},
               link
             ) do
          %{"userid" => encoded_user_id} when encoded_user_id != "" ->
            URI.decode(encoded_user_id)

          %{"roomid" => encoded_room_id} when encoded_room_id != "" ->
            "!" <> URI.decode(encoded_room_id)

          %{"roomalias" => encoded_room_alias} when encoded_room_alias != "" ->
            "#" <> URI.decode(encoded_room_alias)

          _ ->
            text = transform_children(children, state)

            if text == link do
              link
            else
              "#{text} <#{link}>"
            end
        end
    end
  end

  def transform({"img", attributes, children}, state) do
    attributes = attributes |> Map.new()
    src = attributes |> Map.get("src")
    alt = attributes |> Map.get("alt")
    title = attributes |> Map.get("title")

    alt =
      if useless_img_alt?(alt) do
        nil
      else
        alt
      end

    case {src, alt, title} do
      {nil, nil, nil} -> transform_children(children, state)
      {nil, nil, title} -> title
      {nil, alt, _} -> alt
      {link, nil, nil} -> format_url(link, state.homeserver)
      {link, nil, title} -> "#{title} <#{format_url(link, state.homeserver)}>"
      {link, alt, _} -> "#{alt} <#{format_url(link, state.homeserver)}>"
    end
  end

  def transform({"br", _, []}, _state) do
    "\n"
  end

  def transform({tag, _, children}, state) when tag in ["ol", "ul"] do
    "\n" <> transform_children(children, state)
  end

  def transform({"li", _, children}, state) do
    "* " <> transform_children(children, state) <> "\n"
  end

  def transform({tag, attributes, children}, state) when tag in ["font", "span"] do
    attributes = Map.new(attributes)
    fg = Map.get(attributes, "data-mx-color")
    bg = Map.get(attributes, "data-mx-bg-color")

    case {fg, bg} do
      {nil, nil} ->
        transform_children(children, state)

      _ ->
        fg = fg && String.trim_leading(fg, "#")
        bg = bg && String.trim_leading(bg, "#")

        restored_colors = get_color_code(state.color)

        state = %M51.Format.Matrix2Irc.State{state | color: {fg, bg}}

        get_color_code({fg, bg}) <>
          transform_children(children, state) <> restored_colors
    end
  end

  def transform({"mx-reply", _, _}, _color) do
    ""
  end

  def transform({tag, _, children}, state) do
    char = Map.get(@simple_tags, tag, "")
    children = paragraph_to_newline(children, [])

    state =
      case tag do
        "pre" -> %M51.Format.Matrix2Irc.State{state | preserve_whitespace: true}
        _ -> state
      end

    transform_children(children, state, char)
  end

  def get_color_code({fg, bg}) do
    case {fg, bg} do
      # reset
      {nil, nil} -> "\x0399,99"
      {fg, nil} -> "\x04#{fg}"
      # set both fg and bg, then reset fg
      {nil, bg} -> "\x04000000,#{bg}\x0399"
      {fg, bg} -> "\x04#{fg},#{bg}"
    end
  end

  defp transform_children(children, state, char \\ "") do
    Stream.concat([
      [char],
      Stream.map(children, fn child -> transform(child, state) end),
      [char]
    ])
    |> Enum.join()
  end

  defp paragraph_to_newline([], acc) do
    Enum.reverse(acc)
  end

  defp paragraph_to_newline([{"p", _, children1}, {"p", _, children2} | tail], acc) do
    paragraph_to_newline(tail, [
      {"span", [], children2},
      {"br", [], []},
      {"span", [], children1}
      | acc
    ])
  end

  defp paragraph_to_newline([{"p", _, text} | tail], acc) do
    paragraph_to_newline(tail, [
      {"br", [], []},
      {"span", [], text},
      {"br", [], []}
      | acc
    ])
  end

  defp paragraph_to_newline([head | tail], acc) do
    paragraph_to_newline(tail, [head | acc])
  end

  @doc "Transforms a mxc:// \"URL\" into an actually usable URL."
  def format_url(url, homeserver \\ nil, filename \\ nil) do
    case URI.parse(url) do
      %{scheme: "mxc", host: host, path: path} ->
        # prefer the homeserver when available, it is more reliable than arbitrary
        # hosts chosen by message senders
        homeserver = homeserver || host

        base_url = M51.MatrixClient.Client.get_base_url(homeserver, M51.Config.httpoison())

        case filename do
          nil ->
            "#{base_url}/_matrix/media/r0/download/#{urlquote(host)}#{path}"

          _ ->
            "#{base_url}/_matrix/media/r0/download/#{urlquote(host)}#{path}/#{urlquote(filename)}"
        end

      _ ->
        url
    end
  end

  @doc """
    Returns whether the given string is a useless alt that should not
    be displayed (eg. a stock filename).
  """
  def useless_img_alt?(s) do
    s == nil or String.match?(s, ~r/(image|unknown)\.(png|jpe?g|gif)/i)
  end

  defp urlquote(s) do
    M51.Matrix.Utils.urlquote(s)
  end
end
