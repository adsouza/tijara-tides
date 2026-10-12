defmodule TijaraTidesWeb.Music do
  @moduledoc """
  Whether the client may play background music, and the credits it shows.

  The soundtrack is presentation data. `priv/audio/music.json` lists palettes
  and tracks, the audio is stored in Git LFS, and `priv/music/approvals.json`
  records listening decisions bound to the exact files and playback recipe they
  were made against. The server never chooses pieces; it only gates playback.
  """
  require Logger

  @status_key {__MODULE__, :status}
  @audition_allowed Application.compile_env(:tijara_tides, :music_audition_allowed, false)

  def manifest_url, do: Keyword.fetch!(config(), :url)
  def manifest, do: read_json(priv(:manifest))

  @doc "Availability, computed once per boot."
  def status do
    with nil <- :persistent_term.get(@status_key, nil) do
      status = compute_status()
      :persistent_term.put(@status_key, status)
      status
    end
  end

  def log_status do
    with {:unavailable, reasons} <- status() do
      Logger.warning("Background music is unavailable: " <> Enum.join(reasons, "; "))
    end

    :ok
  end

  def evaluate(manifest, approvals, directory, opts) do
    reasons =
      if(Keyword.fetch!(opts, :enabled), do: [], else: ["music is disabled"]) ++
        missing_audio(manifest, directory) ++
        if(Keyword.get(opts, :audition, false), do: [], else: unapproved(manifest, approvals))

    if reasons == [], do: :available, else: {:unavailable, reasons}
  end

  def approval_report(manifest, approvals) do
    tracks = manifest["tracks"]
    recipe = manifest["recipe"]
    recorded = approvals["tracks"] || %{}
    handoffs = approvals["handoffs"] || []

    pairs =
      for palette <- manifest["palettes"],
          from <- palette["port"],
          to <- palette["voyage"],
          do: {from, to}

    track_items =
      for {slug, track} <- Enum.sort(tracks), part <- ["recording", "playback"] do
        {"#{slug} #{part}",
         classify(get_in(recorded, [slug, part]), binding(part, track, recipe))}
      end

    unknown =
      for slug <- Enum.sort(Map.keys(recorded)),
          not Map.has_key?(tracks, slug),
          do: {"#{slug} approvals for an unknown track", :stale}

    pair_items =
      for {from, to} <- pairs do
        entry = find_handoff(handoffs, "port-to-voyage", from, to)

        {"#{from} → #{to} handoff",
         classify(entry, handoff_binding(from, to, tracks, recipe, true))}
      end

    outside =
      for %{"kind" => "port-to-voyage"} = h <- handoffs,
          {h["from"], h["to"]} not in pairs,
          do: {"#{h["from"]} → #{h["to"]} handoff outside the roster", :stale}

    odd =
      for h <- handoffs,
          h["kind"] not in ["port-to-voyage", "voyage-handoff"],
          do: {"handoff of unknown kind #{inspect(h["kind"])}", :stale}

    voyages = voyage_items(handoffs, manifest["palettes"], tracks, recipe)

    (track_items ++ unknown ++ pair_items ++ outside ++ voyages ++ odd)
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
  end

  def credits(manifest) do
    base = Path.dirname(manifest_url())

    for palette <- manifest["palettes"], role <- ["port", "voyage"], slug <- palette[role] do
      track = manifest["tracks"][slug]

      %{
        slug: slug,
        palette: palette["name"],
        role: role,
        title: track["title"],
        credit: track["credit"],
        source_url: track["source_url"],
        licence: track["licence"],
        licence_url: track["licence_url"],
        edits: track["edits"],
        notices:
          for(n <- track["notices"] || [], do: %{name: n["name"], url: base <> "/" <> n["file"]})
      }
    end
  end

  defp voyage_items(handoffs, palettes, tracks, recipe) do
    voyage_palettes = Map.new(for p <- palettes, slug <- p["voyage"], do: {slug, p["id"]})
    recorded = Enum.filter(handoffs, &(&1["kind"] == "voyage-handoff"))

    {valid, invalid} =
      Enum.split_with(recorded, fn h ->
        origin = voyage_palettes[h["from"]]
        destination = voyage_palettes[h["to"]]

        Map.has_key?(tracks, h["from"]) and Map.has_key?(tracks, h["to"]) and
          origin != nil and destination != nil and origin != destination
      end)

    invalid_items =
      for h <- invalid do
        {"#{h["from"]} → #{h["to"]} voyage handoff outside cross-region voyage pools", :stale}
      end

    required =
      valid
      |> Enum.flat_map(fn h -> [{h["from"], h["to"]}, {h["to"], h["from"]}] end)
      |> Enum.uniq()
      |> Enum.sort()

    checks =
      for h <- valid do
        {"#{h["from"]} → #{h["to"]} voyage handoff",
         classify(h, handoff_binding(h["from"], h["to"], tracks, recipe, false))}
      end

    missing =
      for {from, to} <- required,
          find_handoff(valid, "voyage-handoff", from, to) == nil do
        {"#{from} → #{to} voyage handoff", :pending}
      end

    empty = if valid == [], do: [{"cross-region voyage handoff", :pending}], else: []
    invalid_items ++ checks ++ missing ++ empty
  end

  defp find_handoff(handoffs, kind, from, to),
    do: Enum.find(handoffs, &(&1["kind"] == kind and &1["from"] == from and &1["to"] == to))

  defp binding("recording", track, _recipe), do: %{"source_sha256" => track["source_sha256"]}

  defp binding("playback", track, recipe),
    do: %{
      "output_sha256" => track["output_sha256"],
      "entry_s" => track["entry_s"],
      "recipe" => recipe
    }

  # Selection handoffs start at the voyage's entry; automatic handoffs at zero.
  defp handoff_binding(from, to, tracks, recipe, entry?) do
    binding = %{
      "from_output_sha256" => get_in(tracks, [from, "output_sha256"]),
      "to_output_sha256" => get_in(tracks, [to, "output_sha256"]),
      "recipe" => recipe
    }

    if entry?, do: Map.put(binding, "to_entry_s", get_in(tracks, [to, "entry_s"])), else: binding
  end

  defp classify(nil, _binding), do: :pending
  defp classify(%{"decision" => "pending"}, _binding), do: :pending
  defp classify(%{"decision" => "rejected"}, _binding), do: :rejected

  defp classify(%{"decision" => "approved"} = entry, binding),
    do: if(Map.take(entry, Map.keys(binding)) == binding, do: :approved, else: :stale)

  defp classify(_entry, _binding), do: :stale

  defp unapproved(manifest, approvals) do
    report = approval_report(manifest, approvals)

    for status <- [:stale, :rejected, :pending],
        item <- Map.get(report, status, []),
        do: "#{item} #{status}"
  end

  defp missing_audio(manifest, directory) do
    for {_slug, track} <- Enum.sort(manifest["tracks"]),
        not ogg?(Path.join(directory, track["file"])),
        do: "#{track["file"]} is not Ogg audio (missing or a Git LFS pointer)"
  end

  defp ogg?(path),
    do: match?({:ok, "OggS"}, File.open(path, [:read, :binary], &IO.binread(&1, 4)))

  defp compute_status do
    load_status(priv(:manifest), priv(:approvals),
      enabled: Keyword.get(config(), :enabled, false),
      audition: @audition_allowed and Keyword.get(config(), :audition, false)
    )
  end

  @doc """
  Availability from the manifest and approvals files, with the audio beside the
  manifest. An unreadable file, invalid JSON or JSON of the wrong shape keeps
  music unavailable with a reason instead of raising during a page render.
  """
  def load_status(manifest_path, approvals_path, opts) do
    with {:ok, manifest} <- read_json(manifest_path),
         {:ok, approvals} <- read_json(approvals_path) do
      files = "#{Path.basename(manifest_path)} or #{Path.basename(approvals_path)}"

      try do
        if well_formed?(manifest, approvals),
          do: evaluate(manifest, approvals, Path.dirname(manifest_path), opts),
          else: {:unavailable, ["#{files} has an unexpected shape"]}
      rescue
        error ->
          message = String.slice(Exception.message(error), 0, 200)
          {:unavailable, ["#{files} has an unexpected shape: #{message}"]}
      end
    else
      {:error, reason} -> {:unavailable, [reason]}
    end
  end

  # The structure evaluation and the client rely on; deeper type errors raise
  # inside evaluation and are rescued by load_status/3.
  defp well_formed?(manifest, approvals) do
    is_map(manifest) and is_map(approvals) and well_formed_approvals?(approvals) and
      is_map(manifest["recipe"]) and
      is_map(manifest["tracks"]) and Enum.all?(Map.values(manifest["tracks"]), &is_map/1) and
      is_list(manifest["palettes"]) and
      Enum.all?(manifest["palettes"], fn palette ->
        is_map(palette) and
          Enum.all?(["port", "voyage"], fn role ->
            is_list(palette[role]) and Enum.all?(palette[role], &is_map(manifest["tracks"][&1]))
          end)
      end)
  end

  defp well_formed_approvals?(approvals) do
    tracks = Map.get(approvals, "tracks", %{})
    handoffs = Map.get(approvals, "handoffs", [])

    is_map(tracks) and
      Enum.all?(
        Map.values(tracks),
        &(is_map(&1) and Enum.all?(Map.values(&1), fn e -> is_map(e) end))
      ) and
      is_list(handoffs) and Enum.all?(handoffs, &is_map/1)
  end

  defp read_json(path) do
    with {:ok, body} <- File.read(path),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, "#{Path.basename(path)} is not valid JSON: #{Exception.message(error)}"}

      {:error, reason} ->
        {:error, "#{Path.basename(path)} cannot be read: #{:file.format_error(reason)}"}
    end
  end

  defp config, do: Application.get_env(:tijara_tides, :music, [])

  defp priv(key),
    do: Application.app_dir(:tijara_tides, Path.join("priv", Keyword.fetch!(config(), key)))
end
