defmodule Matrix2051.Irc.WordWrap do
  @doc ~S"""
    Splits text into lines not larger than the specified number of bytes.

    The resulting list contains all characters in the original output,
    even spaces.

    The input is assumed to be free of newline characters.

    graphemes are never split between lines, even if they are larger than
    the specified number of bytes.

    ## Examples

        iex> Matrix2051.Irc.WordWrap.split("foo bar baz", 20)
        ["foo bar baz"]

        iex> Matrix2051.Irc.WordWrap.split("foo bar baz", 10)
        ["foo bar ", "baz"]

        iex> Matrix2051.Irc.WordWrap.split("foo bar baz", 4)
        ["foo ", "bar ", "baz"]

        iex> Matrix2051.Irc.WordWrap.split("foo bar baz", 3)
        ["foo", " ", "bar", " ", "baz"]

        iex> Matrix2051.Irc.WordWrap.split("abcdefghijk", 10)
        ["abcdefghij", "k"]

        iex> Matrix2051.Irc.WordWrap.split("abcdefghijk", 4)
        ["abcd", "efgh", "ijk"]

        iex> Matrix2051.Irc.WordWrap.split("réellement", 2)
        ["r", "é", "el", "le", "me", "nt"]

  """
  def split(text, nbytes) do
    if byte_size(text) <= nbytes do
      # Shortcut for small strings
      [text]
    else
      # Split after each whitespace
      Regex.split(~r/((?<=\s)|(?=\s))/, text)
      |> join_reverse_tokens(0, [], [], nbytes)
      |> Enum.reverse()
    end
  end

  defp join_reverse_tokens([], _current_size, reversed_current_line, other_lines, _nbytes) do
    [Enum.join(Enum.reverse(reversed_current_line)) | other_lines]
  end

  defp join_reverse_tokens(
         [token | next_tokens],
         current_size,
         reversed_current_line,
         other_lines,
         nbytes
       ) do
    token_size = byte_size(token)

    cond do
      current_size + token_size <= nbytes ->
        # The token fits in the current line. Add it.
        join_reverse_tokens(
          next_tokens,
          current_size + token_size,
          [token | reversed_current_line],
          other_lines,
          nbytes
        )

      token_size > nbytes ->
        # The token is larger than the max line size. Split it.
        graphemes = String.graphemes(token)

        {first_part, rest} = split_graphemes_at(graphemes, nbytes - current_size)

        {middle_parts, last_part} = split_graphemes(rest, nbytes)

        join_reverse_tokens(
          next_tokens,
          byte_size(last_part),
          [last_part],
          Enum.reverse(middle_parts) ++
            [Enum.join(Enum.reverse([first_part | reversed_current_line]))] ++ other_lines,
          nbytes
        )

      true ->
        # It doesn't. Flush the current line, and create a new one.
        join_reverse_tokens(
          next_tokens,
          token_size,
          [token],
          [Enum.join(Enum.reverse(reversed_current_line)) | other_lines],
          nbytes
        )
    end
  end

  @doc """
    Splits an enumerable of graphemes into {left, right} just before
    the specified number of bytes, so that 'left' is the maximal substring
    of 'graphemes' smaller than 'nbytes' without splitting a grapheme.

    ## Examples

        iex> Matrix2051.Irc.WordWrap.split_graphemes_at(String.graphemes("foobar"), 2)
        {["f", "o"], ["o", "b", "a", "r"]}

        iex> Matrix2051.Irc.WordWrap.split_graphemes_at(String.graphemes("réel"), 2)
        {["r"], ["é", "e", "l"]}
  """
  def split_graphemes_at(graphemes, nbytes) do
    {first_part, rest} = split_reverse_graphemes_at(graphemes, [], nbytes)
    {Enum.reverse(first_part), rest}
  end

  defp split_reverse_graphemes_at([], acc, _nbytes) do
    {acc, []}
  end

  defp split_reverse_graphemes_at([first_grapheme | other_graphemes] = graphemes, acc, nbytes) do
    first_grapheme_size = byte_size(first_grapheme)

    if first_grapheme_size <= nbytes do
      split_reverse_graphemes_at(
        other_graphemes,
        [first_grapheme | acc],
        nbytes - first_grapheme_size
      )
    else
      {acc, graphemes}
    end
  end

  @doc """
    Splits an enumerable of graphemes into a list of strings such that all item
    in the list is smaller than 'nbytes', without splitting a grapheme.

    The last item of the list it returned separately, as it may be significantly
    smaller than the byte limit.

    ## Examples

        iex> Matrix2051.Irc.WordWrap.split_graphemes(String.graphemes("foobar"), 2)
        {["fo", "ob"], "ar"}

        iex> Matrix2051.Irc.WordWrap.split_graphemes(String.graphemes("réellement"), 2)
        {["r", "é", "el", "le", "me"], "nt"}
  """

  def split_graphemes(graphemes, nbytes) do
    case split_reverse_graphemes(graphemes, [], nbytes) do
      [] -> {[], ""}
      [last_part | rest] -> {Enum.reverse(rest), last_part}
    end
  end

  defp split_reverse_graphemes([], acc, _nbytes) do
    acc
  end

  defp split_reverse_graphemes(graphemes, acc, nbytes) do
    {first_part, rest} = split_reverse_graphemes_at(graphemes, [], nbytes)
    # crashes instead of infinite-looping if the graphement does not fit
    [_ | _] = first_part
    split_reverse_graphemes(rest, [Enum.join(Enum.reverse(first_part)) | acc], nbytes)
  end
end
