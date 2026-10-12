defmodule TijaraTidesWeb.MusicTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.Music

  @recipe %{"strategy" => "whole-recording", "fade_in_s" => 2}

  defp manifest do
    %{
      "recipe" => @recipe,
      "palettes" => [
        %{"id" => "east", "ports" => ["Busan"], "port" => ["p"], "voyage" => ["v"]},
        %{"id" => "west", "ports" => ["Tangier"], "port" => ["q"], "voyage" => ["w"]}
      ],
      "tracks" => %{
        "p" => %{
          "file" => "p.ogg",
          "source_sha256" => "sp",
          "output_sha256" => "op",
          "entry_s" => 0.0
        },
        "v" => %{
          "file" => "v.ogg",
          "source_sha256" => "sv",
          "output_sha256" => "ov",
          "entry_s" => 7.5
        },
        "q" => %{
          "file" => "q.ogg",
          "source_sha256" => "sq",
          "output_sha256" => "oq",
          "entry_s" => 0.0
        },
        "w" => %{
          "file" => "w.ogg",
          "source_sha256" => "sw",
          "output_sha256" => "ow",
          "entry_s" => 0.0
        }
      }
    }
  end

  defp approved(extra), do: Map.merge(%{"decision" => "approved"}, extra)

  defp approvals do
    %{
      "tracks" => %{
        "p" => %{
          "recording" => approved(%{"source_sha256" => "sp"}),
          "playback" =>
            approved(%{"output_sha256" => "op", "entry_s" => 0.0, "recipe" => @recipe})
        },
        "v" => %{
          "recording" => approved(%{"source_sha256" => "sv"}),
          "playback" =>
            approved(%{"output_sha256" => "ov", "entry_s" => 7.5, "recipe" => @recipe})
        },
        "q" => %{
          "recording" => approved(%{"source_sha256" => "sq"}),
          "playback" =>
            approved(%{"output_sha256" => "oq", "entry_s" => 0.0, "recipe" => @recipe})
        },
        "w" => %{
          "recording" => approved(%{"source_sha256" => "sw"}),
          "playback" =>
            approved(%{"output_sha256" => "ow", "entry_s" => 0.0, "recipe" => @recipe})
        }
      },
      "handoffs" => [
        approved(%{
          "kind" => "port-to-voyage",
          "from" => "p",
          "to" => "v",
          "from_output_sha256" => "op",
          "to_output_sha256" => "ov",
          "to_entry_s" => 7.5,
          "recipe" => @recipe
        }),
        approved(%{
          "kind" => "port-to-voyage",
          "from" => "q",
          "to" => "w",
          "from_output_sha256" => "oq",
          "to_output_sha256" => "ow",
          "to_entry_s" => 0.0,
          "recipe" => @recipe
        }),
        approved(%{
          "kind" => "voyage-handoff",
          "from" => "v",
          "to" => "w",
          "from_output_sha256" => "ov",
          "to_output_sha256" => "ow",
          "recipe" => @recipe
        }),
        approved(%{
          "kind" => "voyage-handoff",
          "from" => "w",
          "to" => "v",
          "from_output_sha256" => "ow",
          "to_output_sha256" => "ov",
          "recipe" => @recipe
        })
      ]
    }
  end

  setup do
    directory = Path.join(System.tmp_dir!(), "music-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)

    for slug <- ~w(p v q w),
        do: File.write!(Path.join(directory, slug <> ".ogg"), "OggS" <> :binary.copy(<<0>>, 32))

    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "current approvals, real audio and the flag make music available", %{directory: dir} do
    assert Music.evaluate(manifest(), approvals(), dir, enabled: true) == :available
    assert %{approved: approved} = Music.approval_report(manifest(), approvals())
    assert length(approved) == 12
  end

  test "the flag, a pointer file and a missing approval each keep music off", %{directory: dir} do
    assert {:unavailable, ["music is disabled"]} =
             Music.evaluate(manifest(), approvals(), dir, enabled: false)

    File.write!(
      Path.join(dir, "v.ogg"),
      "version https://git-lfs.github.com/spec/v1\noid sha256:ab\n"
    )

    assert {:unavailable, [reason]} = Music.evaluate(manifest(), approvals(), dir, enabled: true)
    assert reason =~ "v.ogg is not Ogg audio"

    File.write!(Path.join(dir, "v.ogg"), "OggS")
    pending = update_in(approvals()["tracks"], &Map.delete(&1, "v"))
    assert {:unavailable, reasons} = Music.evaluate(manifest(), pending, dir, enabled: true)
    assert "v recording pending" in reasons and "v playback pending" in reasons
  end

  test "each binding goes stale when what it was made against changes" do
    changed = put_in(manifest()["tracks"]["v"]["output_sha256"], "new")
    report = Music.approval_report(changed, approvals())
    assert "v playback" in report.stale
    assert "p → v handoff" in report.stale
    assert "v → w voyage handoff" in report.stale
    assert "w → v voyage handoff" in report.stale
    refute "v recording" in report.stale

    resourced = put_in(manifest()["tracks"]["p"]["source_sha256"], "new")
    assert Music.approval_report(resourced, approvals()).stale == ["p recording"]

    reentered = put_in(manifest()["tracks"]["v"]["entry_s"], 8.0)

    assert Enum.sort(Music.approval_report(reentered, approvals()).stale) ==
             ["p → v handoff", "v playback"]

    recipe = put_in(manifest()["recipe"]["fade_in_s"], 3)
    assert length(Music.approval_report(recipe, approvals()).stale) == 8
  end

  test "rejections, unknown tracks and a missing cross-region check are reported" do
    rejected = put_in(approvals()["tracks"]["p"]["recording"]["decision"], "rejected")
    assert Music.approval_report(manifest(), rejected).rejected == ["p recording"]

    unknown = put_in(approvals()["tracks"]["ghost"], %{})

    assert "ghost approvals for an unknown track" in Music.approval_report(manifest(), unknown).stale

    no_voyage =
      update_in(
        approvals()["handoffs"],
        &Enum.reject(&1, fn h -> h["kind"] == "voyage-handoff" end)
      )

    assert Music.approval_report(manifest(), no_voyage).pending == ["cross-region voyage handoff"]
  end

  test "audition skips approvals but not the flag or the audio check", %{directory: dir} do
    assert Music.evaluate(manifest(), %{}, dir, enabled: true, audition: true) == :available

    assert {:unavailable, ["music is disabled"]} =
             Music.evaluate(manifest(), %{}, dir, enabled: false, audition: true)
  end

  test "a reviewed cross-region voyage handoff also requires its reverse", %{directory: dir} do
    one_way =
      update_in(
        approvals()["handoffs"],
        &Enum.reject(&1, fn h ->
          h["kind"] == "voyage-handoff" and h["from"] == "w" and h["to"] == "v"
        end)
      )

    assert Music.approval_report(manifest(), one_way).pending == ["w → v voyage handoff"]
    assert {:unavailable, reasons} = Music.evaluate(manifest(), one_way, dir, enabled: true)
    assert "w → v voyage handoff pending" in reasons
  end

  test "self, port and unknown-track handoffs cannot stand in for cross-region review" do
    for {from, to} <- [{"v", "v"}, {"p", "w"}, {"v", "ghost"}] do
      tracks = manifest()["tracks"]

      invalid =
        approved(%{
          "kind" => "voyage-handoff",
          "from" => from,
          "to" => to,
          "from_output_sha256" => get_in(tracks, [from, "output_sha256"]),
          "to_output_sha256" => get_in(tracks, [to, "output_sha256"]),
          "recipe" => @recipe
        })

      records =
        update_in(approvals()["handoffs"], fn handoffs ->
          Enum.filter(handoffs, &(&1["kind"] == "port-to-voyage")) ++ [invalid]
        end)

      report = Music.approval_report(manifest(), records)
      assert "#{from} → #{to} voyage handoff outside cross-region voyage pools" in report.stale
      assert report.pending == ["cross-region voyage handoff"]
    end
  end

  test "two voyage tracks in the same palette do not satisfy cross-region review" do
    same_palette =
      put_in(manifest()["palettes"], [
        %{"id" => "east", "ports" => ["Busan"], "port" => ["p", "q"], "voyage" => ["v", "w"]}
      ])

    report = Music.approval_report(same_palette, approvals())
    assert "v → w voyage handoff outside cross-region voyage pools" in report.stale
    assert "w → v voyage handoff outside cross-region voyage pools" in report.stale
    assert "cross-region voyage handoff" in report.pending
  end

  test "the test build plays the approved fixture" do
    assert Music.status() == :available
    assert Music.manifest_url() == "/audio/fixtures/music.json"
  end
end

defmodule TijaraTidesWeb.MusicServingTest do
  use TijaraTidesWeb.ConnCase, async: true

  test "audio supports byte ranges and full downloads", %{conn: conn} do
    path = Application.app_dir(:tijara_tides, "priv/audio/fixtures/east-port.ogg")
    bytes = File.read!(path)

    partial =
      conn |> put_req_header("range", "bytes=4-19") |> get("/audio/fixtures/east-port.ogg")

    assert partial.status == 206
    assert get_resp_header(partial, "content-range") == ["bytes 4-19/#{byte_size(bytes)}"]
    assert partial.resp_body == binary_part(bytes, 4, 16)

    full = build_conn() |> get("/audio/fixtures/east-port.ogg")
    assert full.status == 200 and full.resp_body == bytes
    assert ["audio/ogg" <> _] = get_resp_header(full, "content-type")
    assert build_conn() |> get("/audio/fixtures/music.json") |> json_response(200)
  end
end
