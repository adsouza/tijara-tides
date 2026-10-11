# Run with mix run --no-start scripts/benchmark-voyage-quotes.exs.
# Compare identical loaded catalogues in one VM; no server or database is started.
alias TijaraTides.Domain.Fleet
alias TijaraTides.Infrastructure.GameCatalogue

catalogue = GameCatalogue.all()
uncached = update_in(catalogue["piracy"], &Map.delete(&1, :crossings))

ship = fn port ->
  %{"id" => "benchmark", "class" => "freighter", "port" => port, "cargo" => [], "built_ms" => 0}
end

measure = fn quote, cat, repetitions, count ->
  Enum.each(1..min(100, repetitions), fn _ -> quote.(cat) end)

  samples =
    for _ <- 1..5 do
      {us, _} = :timer.tc(fn -> Enum.each(1..repetitions, fn _ -> quote.(cat) end) end)
      us / (repetitions * count)
    end

  samples |> Enum.sort() |> Enum.at(2)
end

compare = fn label, quote, repetitions, count ->
  before = measure.(quote, uncached, repetitions, count)
  after_cache = measure.(quote, catalogue, repetitions, count)

  IO.puts(
    "#{label}: #{Float.round(before, 1)} → " <>
      "#{Float.round(after_cache, 1)} µs/quote (#{Float.round(before / after_cache, 1)}×)"
  )
end

for {port, destination} <- [
      {"Tangier", "Valencia"},
      {"Tangier", "Athens"},
      {"Antwerp", "Busan"},
      {"Los Angeles", "Busan"}
    ] do
  quote = fn cat -> Fleet.voyage_quote(ship.(port), destination, cat, 123_456) end
  true = quote.(catalogue) == quote.(uncached)
  compare.("#{port} → #{destination}", quote, 500, 1)
end

voyages =
  for {key, _} <- Enum.sort(catalogue["routes"]) do
    [port, destination] = String.split(key, "|")
    {ship.(port), destination}
  end

quote_all = fn cat ->
  Enum.each(voyages, fn {ship, destination} ->
    Fleet.voyage_quote(ship, destination, cat, 123_456)
  end)
end

compare.("All #{length(voyages)} routes", quote_all, 1, length(voyages))
