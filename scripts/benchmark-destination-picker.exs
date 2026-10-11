# Run with MIX_ENV=test mix run --no-start scripts/benchmark-destination-picker.exs
# --save tmp/destination-picker-before.term records timings and complete outputs.
# --compare tmp/destination-picker-before.term requires exact output equality.
# Synthetic owner state and public definitions; no server or database is started.
defmodule DestinationPickerBenchmark do
  @endpoint TijaraTidesWeb.Endpoint
  alias TijaraTides.Domain.{Markets, Piracy, Visibility}

  alias TijaraTides.UseCases.{
    DestinationMatrixCache,
    GameQueries,
    MarketQueries,
    VoyageOpportunities
  }

  alias TijaraTidesWeb.GameUI.DestinationPicker
  import Phoenix.LiveViewTest, only: [render_component: 2]

  def run do
    {options, [], []} =
      OptionParser.parse(System.argv(),
        strict: [save: :string, compare: :string, samples: :integer]
      )

    samples = Keyword.get(options, :samples, 7)
    true = samples > 0
    {state, catalogue} = TijaraTides.CommandFuzzer.fixture()
    account = state.entities["accounts"]["account"]

    view = %{
      public: Visibility.public(state, catalogue),
      private: Visibility.private(state, account),
      markets: Markets.quotes(state, catalogue)
    }

    definitions = %{catalogue: Map.update!(catalogue, "piracy", &Piracy.public_model/1)}
    base = view.private["ships"]["company:1"]

    cases = [
      {"small freighter", %{"class" => "small_freighter"}, 100_000_000, "none"},
      {"freighter", %{"class" => "freighter"}, 100_000_000, "none"},
      {"limited cash", %{"class" => "freighter"}, 100_000, "both"},
      {"retained cargo",
       %{
         "class" => "freighter",
         "cargo" => [
           %{"good" => "lumber", "quantity" => 10, "unit_cost" => 1000},
           %{"good" => "fruit", "quantity" => 5, "unit_cost" => 1000, "expires_ms" => 1}
         ]
       }, 100_000_000, "guards"},
      {"loading", %{"class" => "freighter", "status" => "loading", "arrive_ms" => 60_000},
       100_000_000, "insurance"},
      {"queued purchase", %{"class" => "freighter", "pending_side" => "buy"}, 100_000_000,
       "none"},
      {"tanker", %{"class" => "tanker", "port" => "Dubai", "last_liquid" => "diesel"},
       100_000_000, "both"},
      {"limited tanker", %{"class" => "tanker", "port" => "Dubai", "last_liquid" => "diesel"},
       1_000_000, "insurance"}
    ]

    measure = fn fun ->
      fun.()

      times =
        for _ <- 1..samples do
          {us, _} = :timer.tc(fun)
          us / 1000
        end
        |> Enum.sort()

      %{
        median_ms: Enum.at(times, div(samples, 2)),
        p95_ms: Enum.at(times, ceil(samples * 0.95) - 1)
      }
    end

    # Safe decoding accepts only existing atoms, including the plan/map keys.
    for module <- [MarketQueries, VoyageOpportunities], do: Code.ensure_loaded!(module)

    baseline =
      if path = options[:compare],
        do: path |> File.read!() |> :erlang.binary_to_term([:safe])

    results =
      Map.new(cases, fn {label, changes, cash, protection} ->
        IO.puts("Measuring #{label}...")
        ship = Map.merge(base, changes)

        scenario =
          view
          |> put_in([:private, "ships", ship["id"]], ship)
          |> put_in([:private, "company", "cash"], cash)
          |> put_in([:private, "ship_routes", ship["id"]], %{"protection" => protection})

        matrix = fn -> GameQueries.destination_matrix(definitions, scenario, ship) end

        render = fn locale, prepared ->
          TijaraTides.Localization.with_locale(locale, fn ->
            render_component(&DestinationPicker.panel/1,
              definitions: definitions,
              view: scenario,
              ship: ship,
              matrix: prepared || matrix.()
            )
          end)
        end

        output = %{matrix: matrix.(), en: render.("en", nil), ar: render.("ar", nil)}
        cache = DestinationMatrixCache.refresh(nil, definitions, scenario, ship, true)

        for locale <- ["en", "ar"] do
          unless render.(locale, cache.matrix) === output[String.to_existing_atom(locale)],
            do: raise("Cached picker rendering changed: #{label} #{locale}")
        end

        if baseline do
          unless comparable(output) === comparable(baseline[label].output),
            do: raise("Destination suggestions or rendered picker changed: #{label}")
        end

        cold = fn ->
          fresh = DestinationMatrixCache.refresh(nil, definitions, scenario, ship, true)
          render.("en", fresh.matrix)
        end

        warm = fn ->
          reused = DestinationMatrixCache.refresh(cache, definitions, scenario, ship, true)
          render.("en", reused.matrix)
        end

        {_, geometry} = DestinationMatrixCache.calculate(definitions, scenario, ship, nil)
        next_view = put_in(scenario, [:public, "clock_ms"], 5000)

        {next_cache, reused} =
          DestinationMatrixCache.calculate(definitions, next_view, ship, geometry)

        unless reused === geometry &&
                 next_cache.matrix ===
                   GameQueries.destination_matrix(definitions, next_view, ship),
               do: raise("Geometry reuse changed next-tick estimates: #{label}")

        geometry_cached = fn ->
          {fresh, _} = DestinationMatrixCache.calculate(definitions, next_view, ship, geometry)
          render.("en", fresh.matrix)
        end

        loading = fn ->
          render_component(&DestinationPicker.panel/1,
            definitions: definitions,
            view: scenario,
            ship: ship,
            matrix: nil
          )
        end

        timings = %{
          matrix: measure.(matrix),
          picker: measure.(cold),
          cached_picker: measure.(warm),
          geometry_cached_picker: measure.(geometry_cached),
          loading_picker: measure.(loading)
        }

        for stage <- [:matrix, :picker, :cached_picker, :geometry_cached_picker, :loading_picker] do
          timing = timings[stage]

          comparison =
            if baseline do
              before_ms =
                baseline[label].timings[if(stage == :matrix, do: :matrix, else: :picker)].median_ms

              " (before #{Float.round(before_ms, 2)} ms; " <>
                "#{Float.round(before_ms / timing.median_ms, 2)}×)"
            else
              ""
            end

          IO.puts(
            "#{label} #{stage}: median #{Float.round(timing.median_ms, 2)} ms, " <>
              "p95 #{Float.round(timing.p95_ms, 2)} ms#{comparison}"
          )
        end

        {label, %{output: output, timings: timings}}
      end)

    if path = options[:save] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, :erlang.term_to_binary(results))
    end

    if baseline,
      do:
        IO.puts(
          "All 8 matrices are exactly unchanged; English/Arabic renders match apart from intertag whitespace."
        )
  end

  # Conditional loading/error branches introduce empty intertag whitespace only.
  defp comparable(output) do
    Enum.reduce([:en, :ar], output, fn locale, result ->
      Map.update!(result, locale, &String.replace(&1, ~r/>\s+</u, "><"))
    end)
  end
end

DestinationPickerBenchmark.run()
