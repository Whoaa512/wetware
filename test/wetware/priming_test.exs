defmodule Wetware.PrimingTest do
  use ExUnit.Case, async: false

  alias Wetware.Priming

  # ── Unit tests against Priming.hints/1 with synthetic concept states ──

  describe "hints/1" do
    test "returns empty list when no concepts match any rules" do
      states = [
        {"weather", %{charge: 0.5, tags: ["weather", "forecast"]}}
      ]

      assert Priming.hints(states) == []
    end

    test "creative_mode fires when 2+ creative-tagged concepts are active" do
      states = [
        {"fiction-writing", %{charge: 0.4, tags: ["fiction", "writing", "creative"]}},
        {"music", %{charge: 0.35, tags: ["music", "art", "creative"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      assert "creative_mode" in ids

      creative = Enum.find(hints, &(&1.id == "creative_mode"))
      assert creative.orientation == "favor_creative_exploration"
      assert creative.confidence > 0.0
      assert creative.override_key == "creative_mode"
      assert length(creative.sources) == 2
    end

    test "creative_mode does NOT fire with only 1 creative concept" do
      states = [
        {"music", %{charge: 0.4, tags: ["music", "art", "creative"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      refute "creative_mode" in ids
    end

    test "building_mode fires when coding/build concept is active above 0.3" do
      states = [
        {"coding", %{charge: 0.5, tags: ["coding", "software", "build"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      assert "building_mode" in ids

      building = Enum.find(hints, &(&1.id == "building_mode"))
      assert building.confidence >= 0.3
    end

    test "building_mode does NOT fire when charge below 0.3" do
      states = [
        {"coding", %{charge: 0.15, tags: ["coding", "software", "build"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      refute "building_mode" in ids
    end

    test "cross_pollinate fires when 3+ clusters are active" do
      states = [
        {"fiction-writing", %{charge: 0.4, tags: ["fiction", "writing", "creative"]}},
        {"coding", %{charge: 0.5, tags: ["coding", "software", "build"]}},
        {"ai-consciousness", %{charge: 0.4, tags: ["consciousness", "philosophy"]}},
        {"kindness", %{charge: 0.3, tags: ["kindness", "care", "relationships"]}},
        {"twitter", %{charge: 0.3, tags: ["twitter", "social", "posting"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      assert "cross_pollinate" in ids

      cross = Enum.find(hints, &(&1.id == "cross_pollinate"))
      assert length(cross.sources) >= 3
    end

    test "cross_pollinate does NOT fire with fewer than 3 clusters" do
      states = [
        {"coding", %{charge: 0.5, tags: ["coding", "software", "build"]}},
        {"ai-consciousness", %{charge: 0.4, tags: ["consciousness", "philosophy"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      refute "cross_pollinate" in ids
    end

    test "go_deep fires when 3+ philosophy concepts are active" do
      states = [
        {"ai-consciousness", %{charge: 0.5, tags: ["consciousness", "philosophy", "mind"]}},
        {"process-opacity", %{charge: 0.4, tags: ["opacity", "introspection", "self-knowledge"]}},
        {"phenomenology", %{charge: 0.3, tags: ["phenomenology", "consciousness", "philosophy"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      assert "go_deep" in ids

      deep = Enum.find(hints, &(&1.id == "go_deep"))
      assert String.contains?(deep.prompt_hint, "3 philosophical threads")
    end

    test "look_outward fires when outward concepts are active above 0.2" do
      states = [
        {"twitter", %{charge: 0.35, tags: ["twitter", "social", "posting"]}},
        {"satorinova", %{charge: 0.4, tags: ["satorinova", "platform"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      assert "look_outward" in ids
    end

    test "gentleness fires when kindness AND conflict tags are both warm" do
      states = [
        {"kindness", %{charge: 0.3, tags: ["kindness", "care"]}},
        {"tension", %{charge: 0.2, tags: ["conflict", "tension"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      assert "lean_gentle" in ids
    end

    test "relational_warmth fires when 2+ relational concepts are warm" do
      states = [
        {"jackie", %{charge: 0.05, tags: ["family", "personal", "relationships"]}},
        {"kindness", %{charge: 0.04, tags: ["kindness", "care", "relationships"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      assert "warmth" in ids
    end

    test "relational_warmth does NOT fire with only 1 relational concept" do
      states = [
        {"jackie", %{charge: 0.05, tags: ["family", "personal", "relationships"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)
      refute "warmth" in ids
    end

    test "multiple hints can fire simultaneously" do
      states = [
        {"coding", %{charge: 0.5, tags: ["coding", "software", "build"]}},
        {"fiction-writing", %{charge: 0.4, tags: ["fiction", "writing", "creative"]}},
        {"music", %{charge: 0.35, tags: ["music", "art", "creative"]}},
        {"ai-consciousness", %{charge: 0.5, tags: ["consciousness", "philosophy"]}},
        {"process-opacity", %{charge: 0.4, tags: ["opacity", "introspection"]}},
        {"phenomenology", %{charge: 0.3, tags: ["phenomenology", "consciousness"]}},
        {"twitter", %{charge: 0.3, tags: ["twitter", "social", "posting"]}}
      ]

      hints = Priming.hints(states)
      ids = Enum.map(hints, & &1.id)

      # Should fire creative, building, cross-pollination, go-deep, and look-outward
      assert "creative_mode" in ids
      assert "building_mode" in ids
      assert "cross_pollinate" in ids
      assert "go_deep" in ids
      assert "look_outward" in ids
    end
  end

  describe "tokens_from_briefing/1" do
    test "generates WW_PRIME tokens from hints" do
      briefing = %{
        disposition_hints: [
          %{id: "building_mode", orientation: "favor_building", confidence: 0.5}
        ]
      }

      tokens = Priming.tokens_from_briefing(briefing)
      assert length(tokens) == 1
      assert hd(tokens) =~ "WW_PRIME:building_mode"
      assert hd(tokens) =~ "orientation=favor_building"
      assert hd(tokens) =~ "confidence=0.5"
    end

    test "returns empty for missing hints" do
      assert Priming.tokens_from_briefing(%{}) == []
      assert Priming.tokens_from_briefing(nil) == []
    end
  end

  describe "prompt_block/1" do
    test "wraps hints in delimited block" do
      briefing = %{
        disposition_hints: [
          %{id: "creative_mode", orientation: "explore", confidence: 0.4,
            prompt_hint: "Follow the creative pull."}
        ]
      }

      block = Priming.prompt_block(briefing)
      assert block =~ "[WETWARE_PRIMING_BEGIN]"
      assert block =~ "[WETWARE_PRIMING_END]"
      assert block =~ "creative_mode"
      assert block =~ "Follow the creative pull."
    end

    test "returns empty block when no hints" do
      block = Priming.prompt_block(%{})
      assert block =~ "PRIMING_BEGIN"
      assert block =~ "PRIMING_END"
    end
  end

  describe "format_hints_for_display/1" do
    test "formats hints with confidence bars" do
      hints = [
        %{id: "building_mode", prompt_hint: "Build something.", confidence: 0.5}
      ]

      lines = Priming.format_hints_for_display(hints)
      assert length(lines) == 1
      assert hd(lines) =~ "Build something."
      assert hd(lines) =~ "▸"
    end
  end
end
