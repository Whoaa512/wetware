defmodule Wetware.DiscoveryTest do
  use ExUnit.Case, async: false

  alias Wetware.{Concept, DataPaths, Discovery, Gel, Resonance}

  setup_all do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "wetware_discovery_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(tmp_dir)

    prev = System.get_env("WETWARE_DATA_DIR")
    System.put_env("WETWARE_DATA_DIR", tmp_dir)

    seed_concepts(tmp_dir)
    Resonance.boot(concepts_path: DataPaths.concepts_path())

    on_exit(fn ->
      if prev,
        do: System.put_env("WETWARE_DATA_DIR", prev),
        else: System.delete_env("WETWARE_DATA_DIR")

      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  setup do
    File.rm(DataPaths.pending_concepts_path())
    :ok
  end

  test "scan -> pending -> graduate -> concept becomes live" do
    term = "signalmesh"

    Discovery.scan("coding signalmesh signalmesh")
    Discovery.scan("research signalmesh signalmesh")
    Discovery.scan("coding research signalmesh signalmesh")

    pending = Discovery.pending()
    item = Enum.find(pending, &(&1.term == term))

    assert item.count >= 6
    assert item.session_count >= 3

    assert {:ok, %{concept: concept}} = Discovery.graduate(term)
    assert concept.name == term
    assert term in Concept.list_all()

    Concept.stimulate(term, 0.8)
    assert {:ok, _} = Gel.step()
    assert Concept.charge(term) > 0.0

    assert :ok = Resonance.remove_concept(term)
  end

  test "layout engine places nearby by tag overlap" do
    existing = %{
      "anchor" => %{center: {40, 40}, r: 3, tags: ["software", "engineering"]},
      "occupied" => %{center: {46, 40}, r: 3, tags: ["analysis"]}
    }

    {x, y} = Wetware.Layout.Engine.place("candidate", ["software"], existing)
    assert is_integer(x)
    assert is_integer(y)
  end

  test "layout engine exposes pluggable strategy module" do
    strategy = Wetware.Layout.Engine.strategy()
    assert strategy == Wetware.Layout.Proximity
    assert function_exported?(strategy, :place, 3)
    assert function_exported?(strategy, :should_grow?, 2)
    assert function_exported?(strategy, :should_shrink?, 2)
  end

  test "pending concepts state persists" do
    term = "deepkernel"

    Discovery.scan("deepkernel deepkernel coding")

    assert File.exists?(DataPaths.pending_concepts_path())
    payload = Jason.decode!(File.read!(DataPaths.pending_concepts_path()))
    assert payload["terms"][term]["count"] >= 2
  end

  defp seed_concepts(tmp_dir) do
    concepts = %{
      "concepts" => %{
        "coding" => %{"tags" => ["software", "engineering"]},
        "research" => %{"tags" => ["analysis", "investigation"]}
      }
    }

    File.write!(Path.join(tmp_dir, "concepts.json"), Jason.encode!(concepts, pretty: true))
  end
end
