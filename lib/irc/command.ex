defmodule Matrix2051.Irc.Command do
  @enforce_keys [:command, :params]
  defstruct [{:tags, %{}}, :source, :command, :params, {:is_echo, false}]

  @doc ~S"""
    Parses an IRC line into the `Matrix2051.Irc.Command` structure.

    ## Examples

        iex> Matrix2051.Irc.Command.parse("PRIVMSG #chan :hello\r\n")
        {:ok,
         %Matrix2051.Irc.Command{
           command: "PRIVMSG",
           params: ["#chan", "hello"]
         }}

        iex> Matrix2051.Irc.Command.parse("@+typing=active TAGMSG #chan\r\n")
        {:ok,
         %Matrix2051.Irc.Command{
           tags: %{"+typing" => "active"},
           command: "TAGMSG",
           params: ["#chan"]
         }}

        iex> Matrix2051.Irc.Command.parse("@msgid=foo :nick!user@host PRIVMSG #chan :hello\r\n")
        {:ok,
         %Matrix2051.Irc.Command{
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
        {Map.new(Regex.split(~r/;/, tags), fn s -> Matrix2051.Irc.Command.parse_tag(s) end), rest}
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
       # TODO: unescape
       _ -> value
     end}
  end

  @doc ~S"""
    Formats an IRC line from the `Matrix2051.Irc.Command` structure.

    ## Examples

        iex> Matrix2051.Irc.Command.format(%Matrix2051.Irc.Command{
        ...>   command: "PRIVMSG",
        ...>   params: ["#chan", "hello"]
        ...> })
        "PRIVMSG #chan :hello\r\n"

        iex> Matrix2051.Irc.Command.format(%Matrix2051.Irc.Command{
        ...>   tags: %{"+typing" => "active"},
        ...>   command: "TAGMSG",
        ...>   params: ["#chan"]
        ...> })
        "@+typing=active TAGMSG :#chan\r\n"

        iex> Matrix2051.Irc.Command.format(%Matrix2051.Irc.Command{
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
                # TODO: escape
                Enum.map(Map.to_list(command.tags), fn {key, value} ->
                  case value do
                    nil -> key
                    _ -> key <> "=" <> value
                  end
                end),
                ";"
              )
            | tokens
          ]
      end

    Enum.join(tokens, " ") <> "\r\n"
  end

  @doc ~S"""
    Rewrites the command to remove features the IRC client does not support

    # Example

        iex> cmd = %Matrix2051.Irc.Command{
        ...>   tags: %{"account" => "abcd"},
        ...>   command: "JOIN",
        ...>   params: ["#foo", "account", "realname"]
        ...> }
        iex> Matrix2051.Irc.Command.downgrade(cmd, [:extended_join])
        %Matrix2051.Irc.Command{
             tags: %{},
             command: "JOIN",
             params: ["#foo", "account", "realname"]
           }

  """
  def downgrade(command, capabilities) do
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
                "msgid" -> Enum.member?(capabilities, :message_tags)
                "time" -> Enum.member?(capabilities, :server_time)
                _ -> false
              end
            end
          end)
          |> Enum.filter(&(&1 != nil))
          |> Map.new()

        %Matrix2051.Irc.Command{command | tags: tags}
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

        _ ->
          command
      end

    command
  end
end
