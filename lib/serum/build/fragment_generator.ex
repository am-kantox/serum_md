defmodule Serum.Build.FragmentGenerator do
  @moduledoc false

  _moduledocp = "Renders page/post/post list structs into a page fragment."

  import Serum.IOProxy, only: [put_msg: 2]
  alias Serum.Fragment
  alias Serum.Plugin
  alias Serum.Result

  @spec to_fragment(map()) :: Result.t([Fragment.t()])
  def to_fragment(map) do
    put_msg(:info, "Generating fragments...")

    map
    |> Map.take([:pages, :posts, :lists])
    |> Enum.flat_map(&elem(&1, 1))
    |> Task.async_stream(&task_fun/1, timeout: :infinity)
    |> Enum.map(&elem(&1, 1))
    |> Result.aggregate_values(:fragment_generator)
  end

  @spec task_fun(struct()) :: Result.t(Fragment.t())
  defp task_fun(fragment_source) do
    case Fragment.Source.to_fragment(fragment_source) do
      {:ok, fragment} -> Plugin.rendered_fragment(fragment)
      {:error, _} = error -> error
    end
  end
end
