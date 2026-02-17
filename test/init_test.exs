defmodule Wetware.InitTest do
  use ExUnit.Case, async: false

  @tag :init

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "wetware_init_#{System.unique_integer([:positive, :monotonic])}"
      )

    prev = System.get_env("WETWARE_DATA_DIR")
    System.put_env("WETWARE_DATA_DIR", tmp_dir)

    on_exit(fn ->
      if prev,
        do: System.put_env("WETWARE_DATA_DIR", prev),
        else: System.delete_env("WETWARE_DATA_DIR")

      File.rm_rf(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  test "init creates data dir and concepts.json", %{tmp_dir: tmp_dir} do
    refute File.exists?(tmp_dir)

    output = capture_init()

    assert File.exists?(tmp_dir)
    assert File.exists?(Path.join(tmp_dir, "concepts.json"))

    # Verify valid JSON with concepts
    {:ok, data} = File.read(Path.join(tmp_dir, "concepts.json"))
    {:ok, decoded} = Jason.decode(data)
    concepts = decoded["concepts"]
    assert map_size(concepts) > 0

    # Check output mentions initialization
    assert output =~ "initialized"
    assert output =~ "starter concepts"
  end

  test "init is idempotent — second run reports already initialized", %{tmp_dir: tmp_dir} do
    # First init
    capture_init()
    assert File.exists?(Path.join(tmp_dir, "concepts.json"))

    # Read the concepts file to compare after second run
    {:ok, original} = File.read(Path.join(tmp_dir, "concepts.json"))

    # Second init
    output = capture_init()
    assert output =~ "already initialized"

    # File unchanged
    {:ok, after_second} = File.read(Path.join(tmp_dir, "concepts.json"))
    assert original == after_second
  end

  test "init on empty concepts.json re-scaffolds", %{tmp_dir: tmp_dir} do
    # Create dir with empty concepts file
    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "concepts.json"), ~s({"concepts": {}}))

    output = capture_init()

    # Should re-scaffold since concepts are empty
    assert output =~ "initialized"

    {:ok, data} = File.read(Path.join(tmp_dir, "concepts.json"))
    {:ok, decoded} = Jason.decode(data)
    assert map_size(decoded["concepts"]) > 0
  end

  defp capture_init do
    ExUnit.CaptureIO.capture_io(fn ->
      Wetware.CLI.main(["init"])
    end)
  end
end
