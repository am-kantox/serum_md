defmodule Serum.Markdown do
  @moduledoc false

  _moduledocp = """
  This module provides functions related to dealing with markdown data.
  """

  alias Serum.Project

  @re_media ~r/(?<type>href|src)="(?:%|%25)media:(?<url>[^"]*)"/
  @re_media_short ~r/\A(?:%|%25)media:(?<url>[^"]*)\z/
  @re_post ~r/(?<type>href|src)="(?:%|%25)post:(?<url>[^"]*)"/
  @re_page ~r/(?<type>href|src)="(?:%|%25)page:(?<url>[^"]*)"/
  @re_tag ~r/(?<type>href|src)="(?:%|%25)tag:(?<url>[^"]*)"/

  @add_prev_next_links Application.compile_env(:serum_md, :prev_next, :arrows)

  @doc "Converts a markdown document into HTML."
  @spec to_html(binary(), Project.t(), keyword()) :: {binary(), map()}
  def to_html(markdown, proj, options \\ []) do
    {html, meta} =
      Md.generate(markdown <> prev_next_links({@add_prev_next_links, options, proj}),
        parser: Serum.Md.Parser,
        format: :none,
        walker:
          {:post,
           fn
             {:p, _, [title]} = _elem, acc
             when not is_map_key(acc, :title) and is_binary(title) ->
               {"", Map.put(acc, :title, title)}

             {:a, %{"data-tag": tag}, _} = elem, acc ->
               {elem, Map.update(acc, :tags, [tag], &[tag | &1])}

             {:img, %{src: src}, _} = elem, acc
             when not is_map_key(acc, :card) and is_binary(src) ->
               card =
                 Regex.replace(@re_media_short, src, fn _, url ->
                   Path.join([proj.base_url, "media", url])
                 end)

               {elem, Map.put(acc, :card, card)}

             elem, acc ->
               {elem, acc}
           end}
      )

    {process_links(html, proj), Map.put(meta, :prev_next, options)}
  end

  @arrows Application.compile_env(:serum_md, :arrows, prev: "⮜", next: "⮞")
  @splitter Application.compile_env(:serum_md, :splitter, "  ￤  ")

  @spec prev_next_links(
          {:arrows, [{:prev, String.t()} | {:next, String.t()}]}
          | (nil | String.t(), nil | String.t() -> String.t())
        ) :: String.t()
  def prev_next_links({:arrows, prev_next, proj}) do
    prev_next = for {k, v} <- prev_next, do: {k, safe_dest(v, proj.pretty_urls)}
    {opening, closing} = {"\n\n---\n⇒{{class:prev_next}}", "⇐\n"}

    wrapper =
      &if(is_nil(prev_next[&1]), do: @arrows[&1], else: "[#{@arrows[&1]}](#{prev_next[&1]})")

    Enum.join([opening, wrapper.(:prev), @splitter, wrapper.(:next), closing])
  end

  def prev_next_links(fun, prev_next) when is_function(fun, 2),
    do: fun.(prev_next[:prev], prev_next[:next])

  defp safe_dest(nil, _), do: nil
  defp safe_dest(s, _) when is_binary(s), do: s
  defp safe_dest(%Serum.File{dest: dest}, _) when is_binary(dest), do: dest

  defp safe_dest(%Serum.File{src: src} = file, false) when is_binary(src),
    do: safe_dest(file, true) <> ".html"

  defp safe_dest(%Serum.File{src: src}, _) when is_binary(src),
    do: src |> String.split("/") |> List.last()

  defp safe_dest(_, _), do: nil

  @spec process_links(binary(), Project.t()) :: binary()
  defp process_links(data, proj) do
    data
    |> replace_media_links(proj)
    |> replace_tag_links(proj)
    |> replace_page_links(proj)
    |> replace_post_links(proj)
  end

  @spec replace_media_links(binary(), Project.t()) :: binary()
  defp replace_media_links(data, proj) do
    Regex.replace(@re_media, data, fn _, attr, val ->
      make_html_attr(attr, Path.join([proj.base_url, "media", val]))
    end)
  end

  @spec replace_tag_links(binary(), Project.t()) :: binary()
  defp replace_tag_links(data, proj) do
    Regex.replace(@re_tag, data, fn _, attr, val ->
      make_html_attr(attr, Path.join([proj.base_url, proj.tags_path, val]))
    end)
  end

  @spec replace_page_links(binary(), Project.t()) :: binary()
  defp replace_page_links(data, proj) do
    Regex.replace(@re_page, data, fn _, attr, val ->
      make_html_attr(attr, Path.join([proj.base_url, val <> ".html"]))
    end)
  end

  @spec replace_post_links(binary(), Project.t()) :: binary()
  defp replace_post_links(data, proj) do
    suffix = post_suffix(proj.pretty_urls)

    Regex.replace(@re_post, data, fn _, attr, val ->
      make_html_attr(attr, Path.join([proj.base_url, "posts", val <> suffix]))
    end)
  end

  @spec make_html_attr(binary(), binary()) :: binary()
  defp make_html_attr(attr, value) do
    <<attr::binary, "=\"", value::binary, "\"">>
  end

  @spec post_suffix(Project.pretty_urls()) :: binary()
  defp post_suffix(pretty_urls)
  defp post_suffix(true), do: ""
  defp post_suffix(:posts), do: ""
  defp post_suffix(_pretty_urls), do: ".html"
end
