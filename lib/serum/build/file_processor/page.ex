defmodule Serum.Build.FileProcessor.Page do
  @moduledoc false

  import Serum.IOProxy, only: [put_msg: 2]
  alias Serum.Markdown
  alias Serum.Page
  alias Serum.Plugin
  alias Serum.Project
  alias Serum.Renderer
  alias Serum.Result
  alias Serum.Template
  alias Serum.Template.Compiler, as: TC

  @spec preprocess_pages([Serum.File.t()], Project.t()) :: Result.t({[Page.t()], [map()]})
  def preprocess_pages(files, proj) do
    put_msg(:info, "Processing page files...")

    result =
      files
      |> Task.async_stream(&preprocess_page(&1, proj), timeout: :infinity)
      |> Enum.map(&elem(&1, 1))
      |> Result.aggregate_values(:file_processor)

    case result do
      {:ok, pages} ->
        sorted_pages = Enum.sort(pages, &(&1.order < &2.order))

        {:ok, {sorted_pages, Enum.map(sorted_pages, &Page.compact/1)}}

      {:error, _} = error ->
        error
    end
  end

  @spec preprocess_page(Serum.File.t(), Project.t()) :: Result.t(Page.t())
  defp preprocess_page(file, proj) do
    import Serum.HeaderParser

    opts = [
      title: :string,
      label: :string,
      group: :string,
      order: :integer,
      template: :string
    ]

    required = []

    with {:ok, %{in_data: data} = file2} <- Plugin.processing_page(file),
         {:ok, {header, extras, rest}} <- parse_header(data, opts, required) do
      header = Map.put(header, :label, header[:label] || header[:title])
      page = Page.new(file2.src, {header, extras}, rest, proj)

      {:ok, page}
    else
      {:invalid, message} -> {:error, {message, file.src, 0}}
      {:error, _} = plugin_error -> plugin_error
    end
  end

  @spec process_pages([Page.t()], Project.t()) :: Result.t([Page.t()])
  def process_pages(pages, proj) do
    [nil | pages]
    |> Enum.chunk_every(3, 1, [nil])
    |> Task.async_stream(&process_page(&1, proj), timeout: :infinity)
    |> Enum.map(&elem(&1, 1))
    |> Result.aggregate_values(:file_processor)
    |> case do
      {:ok, pages} -> Plugin.processed_pages(pages)
      {:error, _} = error -> error
    end
  end

  @spec process_page([Page.t()], Project.t()) :: Result.t(Page.t())
  defp process_page([prev, page, next], proj) do
    case do_process_page(page, proj, prev: prev, next: next) do
      {:ok, page} -> Plugin.processed_page(page)
      {:error, _} = error -> error
    end
  end

  @spec do_process_page(Page.t(), Project.t(), keyword()) :: Result.t(Page.t())
  defp do_process_page(page, proj, options)

  defp do_process_page(%Page{type: type} = page, proj, options) when type in [".md", ""] do
    {data, meta} = Markdown.to_html(page.data, proj, options)

    tags =
      page.file
      |> String.split("/")
      |> Enum.slice(1..-2//1)
      |> Kernel.++([Map.get(page.extras, "tags") | Map.get(meta, :tags, [])])
      |> Enum.uniq()
      |> Enum.join(", ")

    title = page.title || Map.get(meta, :title, "★ ★ ★")
    label = page.label || title

    extras =
      page.extras
      |> Map.put_new("title", title)
      |> Map.put("tags", tags)
      |> Map.put(:supplemental, options)

    {:ok, %Page{page | data: data, extras: extras, title: title, label: label}}
  end

  defp do_process_page(%Page{type: ".html"} = page, _proj, _options) do
    {:ok, page}
  end

  defp do_process_page(%Page{type: ".html.eex"} = page, _proj, _options) do
    with {:ok, ast} <- TC.compile_string(page.data),
         template = Template.new(ast, page.file, :template, page.file),
         {:ok, new_template} <- TC.Include.expand(template),
         {:ok, html} <- Renderer.render_fragment(new_template, []) do
      {:ok, %Page{page | data: html}}
    else
      {:ct_error, msg, line} -> {:error, {msg, page.file, line}}
      {:error, _} = error -> error
    end
  end
end
