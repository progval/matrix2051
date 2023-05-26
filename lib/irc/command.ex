##
# Copyright (C) 2021-2023  Valentin Lorentz
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

defmodule M51.Irc.Command do
  @enforce_keys [:command, :params]
  defstruct [{:tags, %{}}, :source, :command, :params, {:is_echo, false}]

  @doc ~S"""
    Parses an IRC line into the `M51.Irc.Command` structure.

    ## Examples

        iex> M51.Irc.Command.parse("PRIVMSG #chan :hello\r\n")
        {:ok,
         %M51.Irc.Command{
           command: "PRIVMSG",
           params: ["#chan", "hello"]
         }}

        iex> M51.Irc.Command.parse("@+typing=active TAGMSG #chan\r\n")
        {:ok,
         %M51.Irc.Command{
           tags: %{"+typing" => "active"},
           command: "TAGMSG",
           params: ["#chan"]
         }}

        iex> M51.Irc.Command.parse("@msgid=foo :nick!user@host PRIVMSG #chan :hello\r\n")
        {:ok,
         %M51.Irc.Command{
           tags: %{"msgid" => "foo"},
           source: "nick!user@host",
           command: "PRIVMSG",
           params: ["#chan", "hello"]
         }}
  """
  def parse(line) do
    line = Regex.replace(~r/[\r\n]+/, line, "")

    # IRCv3 message-tags https://ircv3.net/specs/extensions/message-tags
    {tags, rfc1459_line} =
      if String.starts_with?(line, "@") do
        [tags | [rest]] = Regex.split(~r/ +/, line, parts: 2)
        {_, tags} = String.split_at(tags, 1)
        {Map.new(Regex.split(~r/;/, tags), fn s -> M51.Irc.Command.parse_tag(s) end), rest}
      else
        {%{}, line}
      end

    # Tokenize
    tokens =
      case Regex.split(~r/ +:/, rfc1459_line, parts: 2) do
        [main] -> Regex.split(~r/ +/, main)
        [main, trailing] -> Regex.split(~r/ +/, main) ++ [trailing]
      end

    # aka "prefix" or "source"
    {source, tokens} =
      if String.starts_with?(hd(tokens), ":") do
        [source | rest] = tokens
        {_, source} = String.split_at(source, 1)
        {source, rest}
      else
        {nil, tokens}
      end

    [command | params] = tokens

    parsed_line = %__MODULE__{
      tags: tags,
      source: source,
      command: String.upcase(command),
      params: params
    }

    {:ok, parsed_line}
  end

  def parse_tag(s) do
    captures = Regex.named_captures(~r/^(?<key>[a-zA-Z0-9\/+-]+)(=(?<value>.*))?$/U, s)
    %{"key" => key, "value" => value} = captures

    {key,
     case value do
       nil -> ""
       _ -> unescape_tag_value(value)
     end}
  end

  @doc ~S"""
    Formats an IRC line from the `M51.Irc.Command` structure.

    ## Examples

        iex> M51.Irc.Command.format(%M51.Irc.Command{
        ...>   command: "PRIVMSG",
        ...>   params: ["#chan", "hello"]
        ...> })
        "PRIVMSG #chan :hello\r\n"

        iex> M51.Irc.Command.format(%M51.Irc.Command{
        ...>   tags: %{"+typing" => "active"},
        ...>   command: "TAGMSG",
        ...>   params: ["#chan"]
        ...> })
        "@+typing=active TAGMSG :#chan\r\n"

        iex> M51.Irc.Command.format(%M51.Irc.Command{
        ...>   tags: %{"msgid" => "foo"},
        ...>   source: "nick!user@host",
        ...>   command: "PRIVMSG",
        ...>   params: ["#chan", "hello"]
        ...> })
        "@msgid=foo :nick!user@host PRIVMSG #chan :hello\r\n"
  """
  def format(command) do
    reversed_params =
      case Enum.reverse(command.params) do
        # Prepend trailing with ":"
        [head | tail] -> [":" <> head | tail]
        [] -> []
      end

    tokens = [command.command | Enum.reverse(reversed_params)]

    tokens =
      case command.source do
        nil -> tokens
        "" -> tokens
        _ -> [":" <> command.source | tokens]
      end

    tokens =
      case command.tags do
        nil ->
          tokens

        tags when map_size(tags) == 0 ->
          tokens

        _ ->
          [
            "@" <>
              Enum.join(
                Enum.map(Map.to_list(command.tags), fn {key, value} ->
                  case value do
                    nil -> key
                    _ -> key <> "=" <> escape_tag_value(value)
                  end
                end),
                ";"
              )
            | tokens
          ]
      end

    # Sanitize tokens, just in case (None of these should be generated from well-formed
    # Matrix events; but servers do not validate them).
    # So instead of exhaustively sanitizing in every part of the code, we do it here
    tokens =
      tokens
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {token, i} ->
        Regex.replace(~r/[\0\r\n ]/, token, fn <<char>> ->
          case char do
            0 ->
              "\\0"

            ?\r ->
              "\\r"

            ?\n ->
              "\\n"

            ?\s ->
              if i == 0 && String.starts_with?(token, ":") do
                # trailing param; no need to escape spaces
                " "
              else
                "\\s"
              end
          end
        end)
      end)
      |> Enum.reverse()

    Enum.join(tokens, " ") <> "\r\n"
  end

  # https://ircv3.net/specs/extensions/message-tags#escaping-values
  @escapes [
    {";", "\\:"},
    {" ", "\\s"},
    {"\\", "\\\\"},
    {"\r", "\\r"},
    {"\n", "\\n"}
  ]
  @escape_map Map.new(@escapes)
  @escaped_re Regex.compile!(
                "[" <>
                  (@escapes
                   |> Enum.map(fn {char, _escape} -> Regex.escape(char) end)
                   |> Enum.join()) <> "]"
              )
  @unescape_map Map.new(Enum.map(@escapes, fn {char, escape} -> {escape, char} end))
  @unescaped_re Regex.compile!(
                  "(" <>
                    (@escapes
                     |> Enum.map(fn {_char, escape} -> Regex.escape(escape) end)
                     |> Enum.join("|")) <> ")"
                )

  defp escape_tag_value(value) do
    Regex.replace(@escaped_re, value, fn char -> Map.get(@escape_map, char) end)
  end

  defp unescape_tag_value(value) do
    Regex.replace(@unescaped_re, value, fn escape -> Map.get(@unescape_map, escape) end)
  end

  @doc ~S"""
    Rewrites the command to remove features the IRC client does not support

    # Example

        iex> cmd = %M51.Irc.Command{
        ...>   tags: %{"account" => "abcd"},
        ...>   command: "JOIN",
        ...>   params: ["#foo", "account", "realname"]
        ...> }
        iex> M51.Irc.Command.downgrade(cmd, [:extended_join])
        %M51.Irc.Command{
             tags: %{},
             command: "JOIN",
             params: ["#foo", "account", "realname"]
           }

  """
  def downgrade(command, capabilities) do
    original_tags = command.tags

    # downgrade echo-message
    command =
      if Enum.member?(capabilities, :echo_message) do
        command
      else
        case command do
          %{is_echo: true, command: "PRIVMSG"} -> nil
          %{is_echo: true, command: "NOTICE"} -> nil
          %{is_echo: true, command: "TAGMSG"} -> nil
          _ -> command
        end
      end

    # downgrade tags
    command =
      if command == nil do
        command
      else
        tags =
          command.tags
          |> Map.to_list()
          |> Enum.filter(fn {key, _value} ->
            if String.starts_with?(key, "+") do
              Enum.member?(capabilities, :message_tags)
            else
              case key do
                "account" -> Enum.member?(capabilities, :account_tag)
                "batch" -> Enum.member?(capabilities, :batch)
                "label" -> Enum.member?(capabilities, :labeled_response)
                "draft/multiline-concat" -> Enum.member?(capabilities, :multiline)
                "msgid" -> Enum.member?(capabilities, :message_tags)
                "time" -> Enum.member?(capabilities, :server_time)
                _ -> false
              end
            end
          end)
          |> Enum.filter(&(&1 != nil))
          |> Map.new()

        %M51.Irc.Command{command | tags: tags}
      end

    # downgrade commands
    command =
      case command do
        %{command: "JOIN", params: params} ->
          [channel, _account_name, _real_name] = params

          if Enum.member?(capabilities, :extended_join) do
            command
          else
            %{command | params: [channel]}
          end

        %{command: "ACK"} ->
          if Map.has_key?(command.tags, "label") do
            command
          else
            nil
          end

        %{command: "BATCH"} ->
          if Enum.member?(capabilities, :batch) do
            command
          else
            nil
          end

        %{command: "REDACT"} ->
          if Enum.member?(capabilities, :message_redaction) do
            command
          else
            sender = Map.get(original_tags, "account")

            display_name =
              case Map.get(original_tags, "+draft/display-name", nil) do
                dn when is_binary(dn) -> " (#{dn})"
                _ -> ""
              end

            tags = Map.drop(command.tags, ["+draft/display-name", "account"])

            command =
              case command do
                %{params: [channel, msgid, reason]} ->
                  %M51.Irc.Command{
                    tags: Map.put(tags, "+draft/reply", msgid),
                    source: "server.",
                    command: "NOTICE",
                    params: [channel, "#{sender}#{display_name} deleted an event: #{reason}"]
                  }

                %{params: [channel, msgid]} ->
                  %M51.Irc.Command{
                    tags: Map.put(tags, "+draft/reply", msgid),
                    source: "server.",
                    command: "NOTICE",
                    params: [channel, "#{sender}#{display_name} deleted an event"]
                  }

                _ ->
                  # shouldn't happen
                  nil
              end

            # run downgrade() recursively in order to drop the new tags if necessary
            downgrade(command, capabilities)
          end

        %{command: "TAGMSG"} ->
          if Enum.member?(capabilities, :message_tags) do
            command
          else
            nil
          end

        %{command: "353", params: params} ->
          if Enum.member?(capabilities, :userhost_in_names) do
            command
          else
            [client, symbol, channel, userlist] = params

            nicklist =
              userlist
              |> String.split()
              |> Enum.map(fn item ->
                # item is a NUH, possibly with one (or more) prefix char.
                [nick | _] = String.split(item, "!")
                nick
              end)
              |> Enum.join(" ")

            %M51.Irc.Command{command | params: [client, symbol, channel, nicklist]}
          end

        _ ->
          command
      end

    command
  end

  @doc ~S"""
    Splits the line so that it does not exceed the protocol's 512 bytes limit
    in the non-tags part.

    ## Examples

        iex> M51.Irc.Command.linewrap(%M51.Irc.Command{
        ...>   command: "PRIVMSG",
        ...>   params: ["#chan", "hello world"]
        ...> }, 25)
        [
          %M51.Irc.Command{
            tags: %{},
            source: nil,
            command: "PRIVMSG",
            params: ["#chan", "hello "]
          },
          %M51.Irc.Command{
            tags: %{"draft/multiline-concat" => nil},
            source: nil,
            command: "PRIVMSG",
            params: ["#chan", "world"]
          }
        ]

  """
  def linewrap(command, nbytes \\ 512) do
    case command do
      %M51.Irc.Command{command: "PRIVMSG", params: [target, text]} ->
        do_linewrap(command, nbytes, target, text)

      %M51.Irc.Command{command: "NOTICE", params: [target, text]} ->
        do_linewrap(command, nbytes, target, text)

      _ ->
        command
    end
  end

  defp do_linewrap(command, nbytes, target, text) do
    overhead = byte_size(M51.Irc.Command.format(%{command | tags: %{}, params: [target, ""]}))

    case M51.Irc.WordWrap.split(text, nbytes - overhead) do
      [] ->
        # line is empty, send it as-is.
        [command]

      [_line] ->
        # no change needed
        [command]

      [first_line | next_lines] ->
        make_command = fn text -> %{command | params: [target, text]} end

        [
          make_command.(first_line)
          | Enum.map(next_lines, fn line ->
              cmd = make_command.(line)
              %{cmd | tags: Map.put(cmd.tags, "draft/multiline-concat", nil)}
            end)
        ]
    end
  end
end
