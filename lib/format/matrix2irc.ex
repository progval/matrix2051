defmodule Matrix2051.Format.Matrix2Irc.Handler do
  @behaviour Saxy.Handler

  @simple_tags Matrix2051.Format.matrix2irc_map()

  def handle_event(:start_document, _prolog, state) do
    {:ok, state}
  end

  def handle_event(:end_document, _data, state) do
    {:ok, state}
  end

  def handle_event(
        :start_element,
        {name, attributes},
        {parts, color_stack, link_stack, []} = state
      ) do
    state =
      case Map.get(@simple_tags, name) do
        nil ->
          case name do
            x when x in ["font", "span"] ->
              # colors
              {previous_fg, previous_bg} =
                case color_stack do
                  [] -> {"000000", "FFFFFF"}
                  [x | _] -> x
                end

              attributes = Map.new(attributes)
              fg = Map.get(attributes, "data-mx-color", previous_fg)
              bg = Map.get(attributes, "data-mx-bg-color", previous_bg)
              {["\x04#{fg},#{bg}" | parts], [{fg, bg} | color_stack], link_stack, []}

            "a" ->
              # links (added after the text)
              attributes = Map.new(attributes)

              case Map.get(attributes, "href") do
                nil ->
                  {parts, color_stack, [nil | link_stack], []}

                link ->
                  case Regex.named_captures(~R(https://matrix.to/#/@(?<userid>.*\)), link) do
                    nil ->
                      {parts, color_stack, [link | link_stack], []}

                    %{"userid" => user_id} ->
                      {[user_id | parts], color_stack, link_stack, [:a]}
                  end
              end

            "img" ->
              # links (added after the text)
              attributes = Map.new(attributes)

              case Map.get(attributes, "src") do
                nil -> state
                link -> {[link | parts], color_stack, link_stack, []}
              end

            x when x in ["ol", "ul"] ->
              {["\n" | parts], color_stack, link_stack, []}

            "li" ->
              # TODO: should be a number when the list was opened with <ol>
              {["* " | parts], color_stack, link_stack, []}

            "br" ->
              {["\n" | parts], color_stack, link_stack, []}

            "mx-reply" ->
              {parts, color_stack, link_stack, [:mx_reply]}

            _ ->
              state
          end

        code ->
          {[code | parts], color_stack, link_stack, []}
      end

    {:ok, state}
  end

  def handle_event(
        :end_element,
        "a",
        {parts, color_stack, link_stack, [:a | ignore_stack]}
      ) do
    {:ok, {parts, color_stack, link_stack, ignore_stack}}
  end

  def handle_event(
        :end_element,
        "mx-reply",
        {parts, color_stack, link_stack, [:mx_reply | ignore_stack]}
      ) do
    {:ok, {parts, color_stack, link_stack, ignore_stack}}
  end

  def handle_event(:end_element, name, {parts, color_stack, link_stack, []} = state) do
    state =
      case Map.get(@simple_tags, name) do
        nil ->
          case name do
            x when x in ["font", "span"] ->
              # pop the item added by the corresponding start_element
              [_ | color_stack] = color_stack

              case color_stack do
                [] ->
                  # we can safely reset the color entirely
                  {["\x0f" | parts], color_stack, link_stack, []}

                [{previous_fg, previous_bg} | _] ->
                  # we need to revert to the previous colors
                  {["\x04#{previous_fg},#{previous_bg}" | parts], color_stack, link_stack, []}
              end

            "a" ->
              [link | link_stack] = link_stack

              case link do
                nil -> {parts, color_stack, link_stack, []}
                _ -> {[" <#{link}>" | parts], color_stack, link_stack, []}
              end

            x when x in ["td", "th"] ->
              {["\t" | parts], color_stack, link_stack, []}

            "li" ->
              {["\n" | parts], color_stack, link_stack, []}

            _ ->
              state
          end

        code ->
          {[code | parts], color_stack, link_stack, []}
      end

    {:ok, state}
  end

  def handle_event(:characters, chars, {parts, color_stack, link_stack, []}) do
    {:ok, {[chars | parts], color_stack, link_stack, []}}
  end

  def handle_event(:cdata, cdata, {parts, color_stack, link_stack, []}) do
    {:ok, {[cdata | parts], color_stack, link_stack, []}}
  end

  def handle_event(_, _, {_, _, _, [_ | _ignore_stack]} = state) do
    {:ok, state}
  end
end
