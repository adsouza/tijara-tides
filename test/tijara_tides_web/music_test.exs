defmodule TijaraTidesWeb.MusicTest do
  use ExUnit.Case, async: true
  require Logger
  alias TijaraTides.OwnLog
  alias TijaraTidesWeb.Music

  @recipe %{"strategy" => "whole-recording", "fade_in_s" => 2}

  defp track(slug, entry \\ 0.0) do
    %{
      "file" => slug <> ".ogg",
      "source_sha256" => "s" <> slug,
      "output_sha256" => "o" <> slug,
      "entry_s" => entry,
      "duration_s" => 120.0,
      "title" => slug,
      "artists" => ["Composer"],
      "credit" => "Composer",
      "source_url" => "https://example.test/" <> slug,
      "licence" => "CC BY 4.0",
      "licence_url" => "https://creativecommons.org/licenses/by/4.0/",
      "edits" => "Encoded as Opus 64 kbps.",
      "notices" => [%{"name" => "Release", "file" => "notices/" <> slug <> ".pdf"}]
    }
  end

  defp manifest do
    %{
      "recipe" => @recipe,
      "palettes" => [
        %{"id" => "east", "ports" => ["Busan"], "port" => ["p"], "voyage" => ["v"]},
        %{"id" => "west", "ports" => ["Tangier"], "port" => ["q"], "voyage" => ["w"]}
      ],
      "tracks" => %{
        "p" => track("p"),
        "v" => track("v", 7.5),
        "q" => track("q"),
        "w" => track("w")
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

  test "every matching port handoff is checked, regardless of record order", %{directory: dir} do
    records = approvals()
    [original | _] = records["handoffs"]

    for {entry, status} <- [
          {Map.put(original, "decision", "rejected"), :rejected},
          {Map.put(original, "decision", "pending"), :pending},
          {Map.put(original, "to_output_sha256", "old-output"), :stale}
        ],
        entries <- [records["handoffs"] ++ [entry], [entry | records["handoffs"]]] do
      duplicate = Map.put(records, "handoffs", entries)
      assert "p → v handoff" in Map.get(Music.approval_report(manifest(), duplicate), status, [])
      assert {:unavailable, reasons} = Music.evaluate(manifest(), duplicate, dir, enabled: true)
      assert "p → v handoff #{status}" in reasons
    end
  end

  test "a superseded handoff record is kept as history without blocking the gate", %{
    directory: dir
  } do
    records = approvals()
    [original | rest] = records["handoffs"]
    history = %{original | "decision" => "superseded", "to_output_sha256" => "old-output"}

    for entries <- [[history, original | rest], [original, history | rest]] do
      kept = Map.put(records, "handoffs", entries)
      assert Music.evaluate(manifest(), kept, dir, enabled: true) == :available
      refute Map.has_key?(Music.approval_report(manifest(), kept), :stale)
    end

    only_history = Map.put(records, "handoffs", [history | rest])
    assert "p → v handoff" in Music.approval_report(manifest(), only_history).pending

    voyage = Enum.find(rest, &(&1["kind"] == "voyage-handoff"))
    old_voyage = %{voyage | "decision" => "superseded", "from_output_sha256" => "old"}
    kept = Map.put(records, "handoffs", records["handoffs"] ++ [old_voyage])
    assert Music.evaluate(manifest(), kept, dir, enabled: true) == :available
  end

  test "well_formed_manifest?/1 accepts the credited shape the credits page reads" do
    assert Music.well_formed_manifest?(manifest())
    refute Music.well_formed_manifest?(put_in(manifest()["tracks"]["p"]["notices"], ["x.pdf"]))

    refute Music.well_formed_manifest?(
             update_in(manifest()["tracks"]["p"], &Map.delete(&1, "licence_url"))
           )
  end

  test "boot logs no warning while disabled, and names every reason once enabled", %{
    directory: dir
  } do
    File.write!(Path.join(dir, "v.ogg"), "version https://git-lfs.github.com/spec/v1\n")
    pending = update_in(approvals()["tracks"], &Map.delete(&1, "p"))
    disabled = Music.evaluate(manifest(), pending, dir, enabled: false)
    assert {:unavailable, [_, _ | _]} = disabled

    capture = fn status ->
      OwnLog.capture(fn ->
        # Reproduce the log noise that concurrent async tests can emit.
        Task.async(fn -> Logger.warning("unrelated concurrent warning") end) |> Task.await()
        Music.log_status(status)
      end)
    end

    assert capture.(disabled) == []

    enabled = Music.evaluate(manifest(), pending, dir, enabled: true)
    {:unavailable, reasons} = enabled

    assert capture.(enabled) == [
             "Background music is unavailable: " <> Enum.join(reasons, "; ") <> "\n"
           ]

    assert capture.(:available) == []
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

  defp load(dir, manifest, approvals, opts \\ [enabled: true]) do
    for {name, body} <- [{"music.json", manifest}, {"approvals.json", approvals}] do
      path = Path.join(dir, name)
      if is_binary(body), do: File.write!(path, body), else: File.rm(path)
    end

    Music.load_status(Path.join(dir, "music.json"), Path.join(dir, "approvals.json"), opts)
  end

  test "status files load, and unreadable or invalid JSON keeps music off", %{directory: dir} do
    manifest = Jason.encode!(manifest())
    approvals = Jason.encode!(approvals())
    assert load(dir, manifest, approvals) == :available

    assert {:unavailable, [reason]} = load(dir, nil, approvals)
    assert reason =~ "music.json cannot be read: no such file or directory"
    assert {:unavailable, [reason]} = load(dir, manifest, nil)
    assert reason =~ "approvals.json cannot be read"
    assert {:unavailable, [reason]} = load(dir, "{\"tracks\": ", approvals)
    assert reason =~ "music.json is not valid JSON"
    assert {:unavailable, [reason]} = load(dir, manifest, "not json")
    assert reason =~ "approvals.json is not valid JSON"
  end

  test "valid JSON of the wrong shape keeps music off instead of raising", %{directory: dir} do
    m = manifest()
    [east, west] = m["palettes"]

    manifests = [
      [],
      nil,
      "music",
      Map.delete(m, "tracks"),
      Map.delete(m, "palettes"),
      Map.delete(m, "recipe"),
      %{m | "tracks" => [], "palettes" => []},
      %{m | "palettes" => %{"east" => east}},
      %{m | "palettes" => [east, %{west | "voyage" => "w"}]},
      %{m | "palettes" => [east, %{west | "port" => ["ghost"]}]},
      %{m | "palettes" => ["east"]},
      put_in(m["tracks"]["p"], "p.ogg"),
      put_in(m["tracks"]["p"]["file"], 7),
      %{m | "palettes" => [Map.delete(east, "ports"), west]},
      %{m | "palettes" => [%{east | "ports" => "Busan"}, west]},
      %{m | "palettes" => [%{east | "ports" => []}, west]},
      %{m | "palettes" => [%{east | "ports" => [7]}, west]},
      %{m | "palettes" => [%{east | "ports" => [""]}, west]},
      %{m | "palettes" => [Map.delete(east, "id"), west]},
      %{m | "palettes" => [%{east | "id" => []}, west]},
      %{m | "palettes" => [%{east | "port" => []}, west]},
      %{m | "palettes" => [%{east | "voyage" => []}, west]}
    ]

    tracks =
      for {key, value} <- [
            {"file", ""},
            {"source_sha256", nil},
            {"output_sha256", []},
            {"output_sha256", ""},
            {"title", nil},
            {"title", ""},
            {"artists", "Composer"},
            {"artists", []},
            {"artists", [7]},
            {"artists", [""]},
            {"source_url", nil},
            {"source_url", ""},
            {"credit", nil},
            {"licence", ""},
            {"licence_url", nil},
            {"edits", 7},
            {"notices", nil},
            {"notices", "x.pdf"},
            {"notices", ["x.pdf"]},
            {"notices", [%{"name" => "Release"}]},
            {"notices", [%{"name" => "", "file" => "notices/x.pdf"}]},
            {"duration_s", "120"},
            {"duration_s", 0},
            {"duration_s", -1},
            {"entry_s", nil},
            {"entry_s", "7.5"},
            {"entry_s", -1},
            {"entry_s", 120}
          ],
          do: put_in(m["tracks"]["p"][key], value)

    approval_sets = [
      [],
      "approved",
      %{"tracks" => []},
      %{"tracks" => %{"p" => []}},
      %{"handoffs" => %{"kind" => "port-to-voyage"}}
    ]

    cases =
      Enum.map(manifests ++ tracks, &{&1, approvals()}) ++
        Enum.map(approval_sets, &{manifest(), &1})

    for {manifest, approvals} <- cases, audition <- [false, true] do
      body = {Jason.encode!(manifest), Jason.encode!(approvals)}

      assert {:unavailable, [reason]} =
               load(dir, elem(body, 0), elem(body, 1), enabled: true, audition: audition),
             "#{inspect(body)} audition: #{audition}"

      assert reason =~ "music.json or approvals.json has an unexpected shape"
    end
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
    assert ["audio/ogg" <> _] = get_resp_header(partial, "content-type")
    assert get_resp_header(partial, "content-range") == ["bytes 4-19/#{byte_size(bytes)}"]
    assert partial.resp_body == binary_part(bytes, 4, 16)

    full = build_conn() |> get("/audio/fixtures/east-port.ogg")
    assert full.status == 200 and full.resp_body == bytes
    assert ["audio/ogg" <> _] = get_resp_header(full, "content-type")
    assert build_conn() |> get("/audio/fixtures/music.json") |> json_response(200)
  end

  test "a missing recording is a 404 that is not labelled as audio" do
    missing = build_conn() |> get("/audio/fixtures/missing.ogg")
    assert missing.status == 404
    refute Enum.any?(get_resp_header(missing, "content-type"), &String.starts_with?(&1, "audio/"))
  end
end
