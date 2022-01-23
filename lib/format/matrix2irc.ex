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

defmodule M51.Format.Matrix2Irc do
  @simple_tags M51.Format.matrix2irc_map()

  def transform(s, _current_color) when is_binary(s) do
    s
  end

  def transform({"a", attributes, children}, current_color) do
    case attributes |> Map.new() |> Map.get("href") do
      nil ->
        transform_children(children, current_color)

      link ->
        case Regex.named_captures(~R(https://matrix.to/#/@(?<userid>.*\)), link) do
          nil ->
            "#{transform_children(children, current_color)} <#{link}>"

          %{"userid" => user_id} ->
            user_id
        end
    end
  end

  def transform({"img", attributes, children}, current_color) do
    attributes = attributes |> Map.new()
    src = attributes |> Map.get("src")
    alt = attributes |> Map.get("alt")
    title = attributes |> Map.get("title")

    case {src, alt, title} do
      {nil, nil, nil} -> transform_children(children, current_color)
      {nil, nil, title} -> title
      {nil, alt, _} -> alt
      {link, nil, nil} -> format_url(link)
      {link, nil, title} -> "#{title} <#{format_url(link)}>"
      {link, alt, _} -> "#{alt} <#{format_url(link)}>"
    end
  end

  def transform({"br", _, []}, _current_color) do
    "\n"
  end

  def transform({tag, _, children}, current_color) when tag in ["ol", "ul"] do
    "\n" <> transform_children(children, current_color)
  end

  def transform({"li", _, children}, current_color) do
    "* " <> transform_children(children, current_color) <> "\n"
  end

  def transform({tag, attributes, children}, current_color) when tag in ["font", "span"] do
    attributes = Map.new(attributes)
    fg = Map.get(attributes, "data-mx-color")
    bg = Map.get(attributes, "data-mx-bg-color")

    case {fg, bg} do
      {nil, nil} ->
        transform_children(children, current_color)

      _ ->
        restored_colors =
          case current_color do
            # reset
            {nil, nil} -> "\x0399,99"
            {fg, bg} -> "\x04#{fg || "000000"},#{bg || "FFFFFF"}"
          end

        ~s(\x04#{fg || "000000"},#{bg || "FFFFFF"}) <>
          transform_children(children, {fg, bg}) <> restored_colors
    end
  end

  def transform({"mx-reply", _, _}, _color) do
    ""
  end

  def transform({tag, _, children}, current_color) do
    char = Map.get(@simple_tags, tag, "")
    transform_children(children, current_color, char)
  end

  defp transform_children(children, current_color, char \\ "") do
    Stream.concat([
      [char],
      Stream.map(children, fn child -> transform(child, current_color) end),
      [char]
    ])
    |> Enum.join()
  end

  @doc "Transforms a mxc:// \"URL\" into an actually usable URL."
  def format_url(url) do
    case URI.parse(url) do
      %{scheme: "mxc", host: host, path: path} ->
        "https://#{host}/_matrix/media/r0/download/#{host}#{path}"

      _ ->
        url
    end
  end
end
