defmodule Serum.Plugins.TableOfContents do
  @moduledoc """
  A Serum plugin that inserts a table of contents.

  ## Using the Plugin

  First, add this plugin to your `serum.exs`:

      %{
        plugins: [
          #{__MODULE__ |> to_string() |> String.replace_prefix("Elixir.", "")}
        ]
      }

  This plugin works with both pages(`.md`, `.html`, and `.html.eex`) and blog
  posts(`.md`). Insert the `<serum-toc>` tag at the position you want to
  display a table of contents at.

      <serum-toc start="2" end="4"></serum-toc>

  The `start` and `end` attributes define a range of heading level this plugin
  recognizes. In the case of the above example, `<h1>`, `<h5>`, and `<h6>` tags
  are ignored when generating a table of contents.

  After this plugin has run, each `<serum-toc>` tag is replaced with an
  unordered list:

      <ul id="toc" class="serum-toc">
        <li class="indent-0">
          <a href="#s_1">
            <span class="number">1</span>
            Section 1
          </a>
        </li>
        <!-- More list items here... -->
      </ul>

  This plugin produces a "flat" unordered list. However, each list item tag has
  an `indent-x` class, where `x` is an indentation level (from 0 to 5) of the
  current item in the list. You can utilize this when working on stylesheets.

  The `id` attribute of each target heading tag is used when hyperlinks are
  generated. If the element does not have an `id`, the plugin will set one
  appropriately.

  ## Notes

  You may use `<serum-toc>` tag more than once in a single page. However, all
  occurrences of this tag will be replaced with a table of contents generated
  using the attributes of the first one. That is, for example, all three tags
  in the code below expand to the same table of contents, showing a 2-level
  deep list.

      <serum-toc start="2" end="3"></serum-toc>
      ...
      <serum-toc></serum-toc>
      ...
      <serum-toc></serum-toc>

  It's recommended that you wrap a `<serum-toc>` tag with a `<div>` tag when
  using in a markdown file, to ensure a well-formed structure of HTML output.

      <div><serum-toc ...></serum-toc></div>

  And finally, make sure you close every `<serum-toc>` tag properly
  with `</serum-toc>`.
  """

  @behaviour Serum.Plugin

  serum_ver = Version.parse!(Mix.Project.config()[:version])
  serum_req = "~> #{serum_ver.major}.#{serum_ver.minor}"

  def name, do: "Table of Contents"
  def version, do: "1.0.0"
  def elixir, do: ">= 1.6.0"
  def serum, do: unquote(serum_req)
  def description, do: "Inserts a table of contents into pages or posts."

  def implements,
    do: [
      :rendering_fragment
    ]

  def rendering_fragment(html, metadata)
  def rendering_fragment(html, %{type: :page}), do: {:ok, insert_toc(html)}
  def rendering_fragment(html, %{type: :post}), do: {:ok, insert_toc(html)}
  def rendering_fragment(html, _), do: {:ok, html}

  @spec insert_toc(Floki.html_tree()) :: Floki.html_tree()
  defp insert_toc(html) do
    case Floki.find(html, "serum-toc") do
      [] ->
        html

      [{"serum-toc", attr_list, _} | _] ->
        {start, end_} = get_range(attr_list)
        state = {start, end_, start, [0], []}
        {new_tree, new_state} = traverse(html, state, &tree_fun/2)
        items = new_state |> elem(4) |> Enum.reverse()
        toc = {"ul", [{"class", "serum-toc"}], items}

        new_tree
        |> traverse(nil, fn
          {"serum-toc", _, _}, _ -> {toc, nil}
          x, _ -> {x, nil}
        end)
        |> elem(0)
    end
  end

  @spec get_range([{binary(), binary()}]) :: {integer(), integer()}
  defp get_range(attr_list) do
    attr_map = Map.new(attr_list)
    start = attr_map["start"]
    end_ = attr_map["end"]
    start = (start && parse_h_level(start, 1)) || 1
    end_ = (end_ && parse_h_level(end_, 6)) || 6
    end_ = max(start, end_)

    {start, end_}
  end

  @spec parse_h_level(binary(), integer()) :: integer()
  defp parse_h_level(str, default) do
    case Integer.parse(str) do
      {level, ""} -> max(1, min(level, 6))
      _ -> default
    end
  end

  @spec traverse(
          Floki.html_tree(),
          term(),
          (Floki.html_tree(), term() -> {Floki.html_tree(), term()})
        ) :: {Floki.html_tree(), term()}

  defp traverse(tree, state, fun)

  defp traverse({tag, attrs, children}, state, fun) do
    {new_children, new_state} = traverse(children, state, fun)

    fun.({tag, attrs, new_children}, new_state)
  end

  defp traverse([_ | _] = tags, state, fun) do
    {new_tags, new_state} =
      Enum.reduce(tags, {[], state}, fn tag, {acc, st} ->
        {new_tag, new_st} = traverse(tag, st, fun)

        {[new_tag | acc], new_st}
      end)

    {new_tags |> Enum.reverse() |> List.flatten(), new_state}
  end

  defp traverse(x, state, _fun), do: {x, state}

  @spec tree_fun(Floki.html_tree(), term()) :: {Floki.html_tree(), term()}
  defp tree_fun(tree, state)

  defp tree_fun({<<?h::8, ch::8, _::binary>>, _, children} = tree, state) when ch in ?1..?6 do
    {start, end_, prev_level, counts, items} = state
    level = ch - ?0

    if level >= start and level <= end_ do
      new_counts = update_counts(counts, level, prev_level)
      num_dot = new_counts |> Enum.reverse() |> Enum.join(".")
      span = {"span", [{"class", "number"}], [num_dot]}
      {contents, _} = traverse(children, nil, &strip_a_tags/2)
      link = {"a", [{"href", "#s_#{num_dot}"}], [span | contents]}
      item = {"li", [{"class", "indent-#{level - start}"}], [link]}
      bookmark = {"a", [{"name", "s_#{num_dot}"}], []}
      new_state = {start, end_, level, new_counts, [item | items]}

      {[bookmark, tree], new_state}
    else
      {tree, state}
    end
  end

  defp tree_fun(x, state), do: {x, state}

  @spec strip_a_tags(Floki.html_tree(), term()) :: {Floki.html_tree(), term()}
  defp strip_a_tags(tree, state)
  defp strip_a_tags({"a", _, children}, state), do: {children, state}
  defp strip_a_tags(x, state), do: {x, state}

  @spec update_counts([integer()], integer(), integer()) :: [integer()]
  defp update_counts(counts, level, prev_level) do
    case level - prev_level do
      0 ->
        [x | xs] = counts

        [x + 1 | xs]

      diff when diff < 0 ->
        [x | xs] = Enum.drop(counts, -diff)

        [x + 1 | xs]

      diff when diff > 0 ->
        List.duplicate(1, diff) ++ counts
    end
  end
end
