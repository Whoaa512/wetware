defmodule Wetware.AbsorbTest do
  use ExUnit.Case, async: false

  alias Wetware.{Absorb, Persistence, Resonance}

  @test_data_dir System.tmp_dir!()
                 |> Path.join("wetware_absorb_test_#{System.unique_integer([:positive])}")

  setup_all do
    assert :ok = Resonance.boot()
    :ok
  end

  setup do
    File.mkdir_p!(@test_data_dir)
    baseline_path = Path.join(@test_data_dir, "baseline")
    assert :ok = Persistence.save(baseline_path)

    on_exit(fn ->
      assert :ok = Persistence.load(baseline_path)
      File.rm_rf!(@test_data_dir)
    end)

    :ok
  end

  describe "extract_concept_name/1" do
    test "extracts from standard markdown heading" do
      assert {:ok, "encounter"} = Absorb.extract_concept_name("# Encounter\n\nSome text.")
    end

    test "normalizes multi-word headings" do
      assert {:ok, "the-third-vocabulary"} =
               Absorb.extract_concept_name("# The Third Vocabulary\n\nText here.")
    end

    test "strips special characters" do
      assert {:ok, "whats-next"} = Absorb.extract_concept_name("# What's Next?\n\nText.")
    end

    test "returns error for no heading" do
      assert {:error, :no_heading_found} = Absorb.extract_concept_name("Just some text.")
    end
  end

  describe "run/2" do
    test "dry run reports what would happen" do
      file = Path.join(@test_data_dir, "test-concept.md")

      File.write!(file, """
      # Test Concept

      This concept relates to coding and music in interesting ways.
      The coding connection is about building things. Music is about rhythm.

      *Cross-references: coding, music*
      """)

      assert {:ok, result} = Absorb.run(file, dry_run: true)
      assert result.concept_name == "test-concept"
      # The concept doesn't exist in the gel, so it would be created
      assert result.created == true
    end

    test "returns error for missing file" do
      assert {:error, :file_not_found} = Absorb.run("/nonexistent/file.md")
    end

    test "returns error for file without heading" do
      file = Path.join(@test_data_dir, "no-heading.md")
      File.write!(file, "Just text without a heading.")
      assert {:error, :no_heading_found} = Absorb.run(file)
    end

    test "extracts cross-references" do
      file = Path.join(@test_data_dir, "cross-ref.md")

      File.write!(file, """
      # Cross Ref Test

      Some text about fiction-writing and coding.

      *Cross-references: fiction-writing, coding, music*
      """)

      assert {:ok, result} = Absorb.run(file, dry_run: true)
      assert "fiction-writing" in result.cross_refs
      assert "coding" in result.cross_refs
      assert "music" in result.cross_refs
    end
  end
end
