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

defmodule M51.Format.Irc2Matrix.State do
  defstruct bold: false,
            italic: false,
            underlined: false,
            stroke: false,
            monospace: false,
            color: {nil, nil}
end

defmodule M51.Format.Irc2Matrix do
  @simple_tags M51.Format.irc2matrix_map()
  @chars ["\x0f" | Map.keys(@simple_tags)]
  @digits Enum.to_list(?0..?9)
  @hexdigits Enum.concat(Enum.to_list(?0..?9), Enum.to_list(?A..?F))

  # References:
  # * https://modern.ircdocs.horse/formatting.html#colors
  # * https://modern.ircdocs.horse/formatting.html#colors-16-98
  @color2hex {
    # 00, white
    "#FFFFFF",
    # 01, black
    "#000000",
    # 02, blue
    "#0000FF",
    # 03, green
    "#009300",
    # 04, red
    "#FF0000",
    # 05, brown
    "#7F0000",
    # 06, magenta
    "#9C009C",
    # 07, orange
    "#FC7F00",
    # 08, yellow
    "#FFFF00",
    # 09, light green
    "#00FC00",
    # 10, cyan
    "#009393",
    # 11, light cyan
    "#00FFFF",
    # 12, light blue
    "#0080FF",
    # 13, pink
    "#FF00FF",
    # 14, grey
    "#7F7F7F",
    # 15, light grey
    "#D2D2D2",
    # 16
    "#470000",
    # 17
    "#472100",
    # 18
    "#474700",
    # 19
    "#324700",
    # 20
    "#004700",
    # 21
    "#00472C",
    # 22
    "#004747",
    # 23
    "#002747",
    # 24
    "#000047",
    # 25
    "#2E0047",
    # 26
    "#470047",
    # 27
    "#47002A",
    # 28
    "#740000",
    # 29
    "#743A00",
    # 30
    "#747400",
    # 31
    "#517400",
    # 32
    "#007400",
    # 33
    "#007449",
    # 34
    "#007474",
    # 35
    "#004074",
    # 36
    "#000074",
    # 37
    "#4B0074",
    # 38
    "#740074",
    # 39
    "#740045",
    # 40
    "#B50000",
    # 41
    "#B56300",
    # 42
    "#B5B500",
    # 43
    "#7DB500",
    # 44
    "#00B500",
    # 45
    "#00B571",
    # 46
    "#00B5B5",
    # 47
    "#0063B5",
    # 48
    "#0000B5",
    # 49
    "#7500B5",
    # 50
    "#B500B5",
    # 51
    "#B5006B",
    # 52
    "#FF0000",
    # 53
    "#FF8C00",
    # 54
    "#FFFF00",
    # 55
    "#B2FF00",
    # 56
    "#00FF00",
    # 57
    "#00FFA0",
    # 58
    "#00FFFF",
    # 59
    "#008CFF",
    # 60
    "#0000FF",
    # 61
    "#A500FF",
    # 62
    "#FF00FF",
    # 63
    "#FF0098",
    # 64
    "#FF5959",
    # 65
    "#FFB459",
    # 66
    "#FFFF71",
    # 67
    "#CFFF60",
    # 68
    "#6FFF6F",
    # 69
    "#65FFC9",
    # 70
    "#6DFFFF",
    # 71
    "#59B4FF",
    # 72
    "#5959FF",
    # 73
    "#C459FF",
    # 74
    "#FF66FF",
    # 75
    "#FF59BC",
    # 76
    "#FF9C9C",
    # 77
    "#FFD39C",
    # 78
    "#FFFF9C",
    # 79
    "#E2FF9C",
    # 80
    "#9CFF9C",
    # 81
    "#9CFFDB",
    # 82
    "#9CFFFF",
    # 83
    "#9CD3FF",
    # 84
    "#9C9CFF",
    # 85
    "#DC9CFF",
    # 86
    "#FF9CFF",
    # 87
    "#FF94D3",
    # 88
    "#000000",
    # 89
    "#131313",
    # 90
    "#282828",
    # 91
    "#363636",
    # 92
    "#4D4D4D",
    # 93
    "#656565",
    # 94
    "#818181",
    # 95
    "#9F9F9F",
    # 96
    "#BCBCBC",
    # 97
    "#E2E2E2",
    # 98
    "#FFFFFF",
    # 99, reset
    nil
  }

  def tokenize(text) do
    text
    |> String.to_charlist()
    |> do_tokenize([''])
    |> Enum.reverse()
    |> Stream.map(fn token -> token |> Enum.reverse() |> to_string() end)
  end

  defp do_tokenize([], acc) do
    acc
  end

  defp do_tokenize([c | tail], acc) when <<c>> in @chars do
    # new token
    do_tokenize(tail, ['' | [[c] | acc]])
  end

  defp do_tokenize([0x03 | tail], acc) do
    # new token, color.
    # see https://modern.ircdocs.horse/formatting.html#forms-of-color-codes for details
    # on this awful format
    {tail, normalized_color} =
      case tail do
        [a, b, ?,, c, d | tail]
        when a in @digits and b in @digits and c in @digits and d in @digits ->
          {tail, [a, b, ?,, c, d]}

        [a, b, ?,, c | tail] when a in @digits and b in @digits and c in @digits ->
          {tail, [a, b, ?,, ?0, c]}

        [a, b, ?, | tail] when a in @digits and b in @digits ->
          {tail, [a, b, ?,]}

        [a, b | tail] when a in @digits and b in @digits ->
          {tail, [a, b, ?,]}

        [a, ?,, c, d | tail] when a in @digits and c in @digits and d in @digits ->
          {tail, [a, ?,, c, d]}

        [a, ?,, c | tail] when a in @digits and c in @digits ->
          {tail, [?0, a, ?,, ?0, c]}

        [a, ?, | tail] when a in @digits ->
          {tail, [?0, a, ?,]}

        [a | tail] when a in @digits ->
          {tail, [?0, a, ?,]}

        tail ->
          {tail, []}
      end

    do_tokenize(tail, ['' | [Enum.reverse([0x03 | normalized_color]) | acc]])
  end

  defp do_tokenize([0x04 | tail], acc) do
    # new token, hex color.
    {tail, normalized_color} =
      case tail do
        [a, b, c, d, e, f, ?,, g, h, i, j, k, l | tail]
        when a in @hexdigits and b in @hexdigits and c in @hexdigits and d in @hexdigits and
               e in @hexdigits and f in @hexdigits and g in @hexdigits and h in @hexdigits and
               i in @hexdigits and j in @hexdigits and k in @hexdigits and l in @hexdigits ->
          {tail, [a, b, c, d, e, f, ?,, g, h, i, j, k, l]}

        [a, b, c, d, e, f, ?, | tail]
        when a in @hexdigits and b in @hexdigits and c in @hexdigits and d in @hexdigits and
               e in @hexdigits and f in @hexdigits ->
          {tail, [a, b, c, d, e, f, ?,]}

        [a, b, c, d, e, f | tail]
        when a in @hexdigits and b in @hexdigits and c in @hexdigits and d in @hexdigits and
               e in @hexdigits and f in @hexdigits ->
          {tail, [a, b, c, d, e, f, ?,]}

        tail ->
          {tail, []}
      end

    do_tokenize(tail, ['' | [Enum.reverse([0x04 | normalized_color]) | acc]])
  end

  defp do_tokenize([c | tail], [head | acc]) do
    # append to the current token
    do_tokenize(tail, [[c | head] | acc])
  end

  defp color2hex(color) do
    # this is safe because color is computed a string with 2 decimal digits,
    # and tuple_size(@color2hex) == 100
    elem(@color2hex, color)
  end

  def update_state(_state, "\x0f") do
    # reset state
    {%M51.Format.Irc2Matrix.State{}, ""}
  end

  def update_state(state, token) do
    key =
      case token do
        "\x02" ->
          :bold

        "\x11" ->
          :monospace

        "\x1d" ->
          :italic

        "\x1e" ->
          :stroke

        "\x1f" ->
          :underlined

        <<0x03, a, b, ?,, c, d>> ->
          {:color, color2hex((a - ?0) * 10 + (b - ?0)), color2hex((c - ?0) * 10 + (d - ?0))}

        <<0x03, a, b, ?,>> ->
          {:color, color2hex((a - ?0) * 10 + (b - ?0)), nil}

        <<0x03>> ->
          {:color, nil, nil}

        <<0x04, a, b, c, d, e, f, ?,, g, h, i, j, k, l>> ->
          {:color, "#" <> <<a, b, c, d, e, f>>, "#" <> <<g, h, i, j, k, l>>}

        <<0x04, a, b, c, d, e, f, ?,>> ->
          {:color, "#" <> <<a, b, c, d, e, f>>, nil}

        <<0x04>> ->
          {:color, nil, nil}

        _ ->
          nil
      end

    case key do
      nil -> {state, token}
      {:color, fg, bg} -> {state |> Map.put(:color, {fg, bg}), ""}
      _ -> {Map.update!(state, key, fn old_value -> !old_value end), ""}
    end
  end

  def make_plain_text(previous_state, state, token) do
    replacement =
      [
        {:bold, "*"},
        {:monospace, "`"},
        {:italic, "/"},
        {:underlined, "_"},
        {:stroke, "~"}
      ]
      |> Enum.map(fn {key, action} ->
        if Map.get(previous_state, key) != Map.get(state, key) do
          action
        else
          ""
        end
      end)
      |> Enum.join()

    case replacement do
      "" -> token
      _ -> replacement
    end
  end

  defp linkify_urls(text) when is_binary(text) do
    # yet another shitty URL detection regexp
    [first_part | other_parts] =
      Regex.split(
        ~r/(mailto:|[a-z][a-z0-9]+:\/\/)\S+(?=\s|>|$)/,
        text,
        include_captures: true
      )

    other_parts =
      other_parts
      |> Enum.map_every(
        2,
        fn url -> {"a", [{"href", url}], [url]} end
      )

    [first_part | other_parts]
  end

  defp linkify_urls({tag, attributes, children}) do
    [{tag, attributes, Enum.flat_map(children, &linkify_urls/1)}]
  end

  defp linkify_nicks(text, nicklist) when is_binary(text) do
    [first_part | other_parts] =
      Regex.split(
        ~r/\b[a-zA-Z0-9._=\/-]+:\S+\b/,
        text,
        include_captures: true
      )

    other_parts =
      other_parts
      |> Enum.map_every(
        2,
        fn userid ->
          [localpart, _] = String.split(userid, ":", parts: 2)

          if Enum.member?(nicklist, userid) do
            {"a", [{"href", "https://matrix.to/#/@#{userid}"}], [localpart]}
          else
            userid
          end
        end
      )

    [first_part | other_parts]
  end

  defp linkify_nicks({tag, attributes, children}, nicklist) do
    [{tag, attributes, Enum.flat_map(children, fn child -> linkify_nicks(child, nicklist) end)}]
  end

  def make_html(_previous_state, state, token, nicklist) do
    tree =
      token
      # replace formatting chars
      |> String.graphemes()
      |> Enum.filter(fn char -> char == "\n" || !Enum.member?(@chars, char) end)
      |> Enum.join()
      # newlines to <br/>:
      |> String.split("\n")
      |> Enum.intersperse({"br", [], []})
      # URLs:
      |> Enum.flat_map(&linkify_urls/1)
      # Nicks:
      |> Enum.flat_map(fn subtree -> linkify_nicks(subtree, nicklist) end)

    case tree do
      # don't bother formatting empty strings
      [""] ->
        []

      _ ->
        [
          {:bold, "b"},
          {:monospace, "code"},
          {:italic, "i"},
          {:underlined, "u"},
          {:stroke, "strike"},
          {:color,
           fn color, tree ->
             case color do
               {nil, nil} -> tree
               {fg, nil} -> [{"font", [{"data-mx-color", fg}], tree}]
               {nil, bg} -> [{"font", [{"data-mx-bg-color", bg}], tree}]
               {fg, bg} -> [{"font", [{"data-mx-color", fg}, {"data-mx-bg-color", bg}], tree}]
             end
           end}
        ]
        |> Enum.reduce(tree, fn {key, action}, tree ->
          case Map.get(state, key) do
            true -> [{action, [], tree}]
            false -> tree
            value -> action.(value, tree)
          end
        end)
    end
  end
end
