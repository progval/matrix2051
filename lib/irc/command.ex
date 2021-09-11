defmodule Matrix2051.Irc.Command do
  @enforce_keys [:command, :params]
  defstruct [{:tags, %{}}, :origin, :command, :params]

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
           origin: "nick!user@host",
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
    {origin, tokens} =
      if String.starts_with?(hd(tokens), ":") do
        [origin | rest] = tokens
        {_, origin} = String.split_at(origin, 1)
        {origin, rest}
      else
        {nil, tokens}
      end

    [command | params] = tokens

    parsed_line = %__MODULE__{
      tags: tags,
      origin: origin,
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
        ...>   origin: "nick!user@host",
        ...>   command: "PRIVMSG",
        ...>   params: ["#chan", "hello"]
        ...> })
        "@msgid=foo :nick!user@host PRIVMSG #chan :hello\r\n"
  """
  def format(command) do
    reversed_params =
      reversed_params =
      case Enum.reverse(command.params) do
        # Prepend trailing with ":"
        [head | tail] -> [":" <> head | tail]
        [] -> []
      end

    tokens = [command.command | Enum.reverse(reversed_params)]

    tokens =
      case command.origin do
        nil -> tokens
        "" -> tokens
        _ -> [":" <> command.origin | tokens]
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
                Enum.map(Map.to_list(command.tags), fn {key, value} -> key <> "=" <> value end),
                ";"
              )
            | tokens
          ]
      end

    Enum.join(tokens, " ") <> "\r\n"
  end
end
