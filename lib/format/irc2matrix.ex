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

defmodule Matrix2051.Format.Irc2Matrix.State do
  defstruct bold: false,
            italic: false,
            underlined: false,
            stroke: false,
            monospace: false,
            fg: nil,
            bg: nil
end

defmodule Matrix2051.Format.Irc2Matrix do
  @simple_tags Matrix2051.Format.irc2matrix_map()
  @chars ["\x0f" | Map.keys(@simple_tags)]

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

  defp do_tokenize([c | tail], [head | acc]) do
    # append to the current token
    do_tokenize(tail, [[c | head] | acc])
  end

  def update_state(_state, "\x0f") do
    # reset state
    %Matrix2051.Format.Irc2Matrix.State{}
  end

  def update_state(state, token) do
    key =
      case token do
        "\x02" -> :bold
        "\x11" -> :monospace
        "\x1d" -> :italic
        "\x1e" -> :underlined
        "\x1f" -> :stroke
        _ -> nil
      end

    case key do
      nil -> state
      _ -> Map.update!(state, key, fn old_value -> !old_value end)
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
      "" ->
        case token do
          "\x0f" -> ""
          _ -> token
        end

      _ ->
        replacement
    end
  end

  def make_html(previous_state, state, token) do
    replacement =
      [
        {:bold, "b"},
        {:monospace, "code"},
        {:italic, "i"},
        {:underlined, "u"},
        {:stroke, "strike"}
      ]
      |> Enum.map(fn {key, action} ->
        case {Map.get(previous_state, key), Map.get(state, key)} do
          {false, true} -> "<#{action}>"
          {true, false} -> "</#{action}>"
          _ -> ""
        end
      end)
      |> Enum.join()

    case replacement do
      "" ->
        case token do
          "\x0f" -> ""
          _ -> token
        end

      _ ->
        replacement
    end
  end

  def finalize_html(html, nicklist) do
    html = String.replace(html, "\n", "<br/>")

    # yet another shitty URL detection regexp
    html =
      Regex.replace(
        ~r/(mailto:|[a-z][a-z0-9]+:\/\/)\S+(?=\s|>|$)/,
        html,
        fn url -> ~s(<a href="#{url}\">#{url}</a>) end
      )

    # from https://matrix.org/docs/spec/appendices#user-identifiers
    html =
      Regex.replace(
        ~r/\b([a-z0-9._=\/-]+):\S+\b/,
        html,
        fn userid, localpart ->
          if Enum.member?(nicklist, userid) do
            ~s(<a href="https://matrix.to/#/@#{userid}\">#{localpart}</a>)
          else
            userid
          end
        end
      )

    html
  end
end
