defmodule Docs.MusicManifestTest do
  @moduledoc """
  Guards the committed soundtrack manifest against the catalogue, DESIGN.md's
  palette table and the files beside it. Files are compared by SHA-256 either
  directly or through their Git LFS pointer, so CI checks hashes without
  downloading audio.
  """
  use ExUnit.Case, async: true

  @manifest "priv/audio/music.json"
  @pointer "version https://git-lfs.github.com/spec/v1\n"

  defp manifest, do: @manifest |> File.read!() |> Jason.decode!()

  defp identity(path) do
    case File.read(path) do
      {:ok, @pointer <> _ = pointer} ->
        [_, oid] = Regex.run(~r/^oid sha256:([0-9a-f]{64})$/m, pointer)
        oid

      {:ok, bytes} ->
        :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

      {:error, reason} ->
        flunk("#{path}: #{reason}")
    end
  end

  defp design_palettes do
    File.read!("docs/DESIGN.md")
    |> String.split("| Palette | Ports |\n", parts: 2)
    |> List.last()
    |> String.split("\n")
    |> Enum.take_while(&String.starts_with?(&1, "|"))
    |> Enum.reject(&String.starts_with?(&1, "|---"))
    |> Enum.map(fn line ->
      [name, ports] = line |> String.split("|", trim: true) |> Enum.map(&String.trim/1)
      {name, ports |> String.split(", ") |> Enum.sort()}
    end)
  end

  test "every catalogue port appears in exactly one palette" do
    ports =
      File.read!("priv/game/catalogue.json")
      |> Jason.decode!()
      |> Map.fetch!("ports")
      |> Map.keys()
      |> Enum.sort()

    listed = Enum.flat_map(manifest()["palettes"], & &1["ports"])
    assert Enum.sort(listed) == ports
    assert length(listed) == length(Enum.uniq(listed))
  end

  test "palettes match DESIGN.md's table and every pool is populated" do
    palettes = manifest()["palettes"]
    assert length(palettes) == 12

    assert design_palettes() ==
             for(p <- palettes, do: {p["name"], Enum.sort(p["ports"])})

    for p <- palettes, role <- ["port", "voyage"] do
      assert p[role] != [], "#{p["id"]} has no #{role} track"
      assert Enum.all?(p[role], &Map.has_key?(manifest()["tracks"], &1))
    end

    assert map_size(manifest()["tracks"]) == 28
  end

  test "the committed manifest has the shape the server gate requires" do
    # The same check the server runs at boot; failing here keeps a preparation
    # run from publishing a manifest that would silently disable music.
    assert TijaraTidesWeb.Music.well_formed_manifest?(manifest())
  end

  test "every track is credited and its files match their recorded hashes" do
    for {slug, track} <- manifest()["tracks"] do
      for key <- ~w(title credit source_url licence licence_url edits),
          do: assert(is_binary(track[key]) and track[key] != "", "#{slug} lacks #{key}")

      assert [_ | _] = track["artists"]
      assert identity(Path.join("priv/audio", track["file"])) == track["output_sha256"], slug
      assert track["entry_s"] >= 0 and track["entry_s"] < track["duration_s"]
      assert is_number(track["true_peak_dbtp"])
      assert track["true_peak_dbtp"] <= manifest()["recipe"]["true_peak_dbtp"]

      for notice <- track["notices"],
          do: assert(File.exists?(Path.join("priv/audio", notice["file"])))
    end
  end

  test "edits describe exactly the trims the manifest records" do
    for {slug, track} <- manifest()["tracks"] do
      for {key, side} <- [{"trim_start_s", "leading"}, {"trim_end_s", "trailing"}] do
        trim = track[key]
        assert is_float(trim) and trim >= 0.0, "#{slug} #{key}"

        case Regex.run(~r/([\d.]+) s of #{side} silence/, track["edits"]) do
          nil ->
            assert trim == 0.0, "#{slug}: #{track["edits"]}"

          [_, printed] ->
            assert trim > 0.0, "#{slug}: #{track["edits"]}"
            assert_in_delta String.to_float(printed), trim, 0.0051, slug
        end
      end

      refute track["edits"] =~ "0.00 s", slug
    end
  end
end
