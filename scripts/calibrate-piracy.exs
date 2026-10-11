# mix run --no-start scripts/calibrate-piracy.exs
# Independent economic audit; no state mutations or database connections.
alias TijaraTides.Domain.{Piracy, ShipClass}
# Tests can supply a different catalogue through Code.eval_string/3's binding.
catalogue_path = Keyword.get(binding(), :catalogue_path, "priv/game/catalogue.json")
model = Jason.decode!(File.read!(catalogue_path))["piracy"]
p = Piracy.protection_settings(model)
IO.puts("class,zone,guard_fee,base_prevented,campaign_prevented,unannounced_loss_loading")

failures =
  for {class_id, class} <- Enum.sort(ShipClass.all()),
      {zone_id, zone} <- Enum.sort(model["zones"]),
      reduce: [] do
    failures ->
      kind = model["kinds"][zone["kind"]]
      charge = div(class["price"] * kind["charge_bps"], 10_000)
      # Idle crew cents per world minute, matching Fleet/Ship operations.
      hold_cost = kind["hold_ms"] * class["crew"] / 120_000
      factor = if kind["storm_suppressed"], do: 22 / class["speed"], else: 1
      base = zone["chance_bps"] * factor / 10_000
      guarded = div(zone["chance_bps"] * (100 - zone["guard_pct"]), 100) * factor / 10_000
      campaign = min(1, base * model["campaign"]["multiplier"])
      campaign_guarded = min(1, guarded * model["campaign"]["multiplier"])
      fee = div(class["price"] * (zone["guard_fee_ppm"] || p["guard_fee_bps"] * 100), 1_000_000)
      avoided = (base - guarded) * (charge + hold_cost)
      surge_avoided = (campaign - campaign_guarded) * (charge + hold_cost)
      # A full unannounced campaign duty cycle is a conservative insurer bound;
      # early announcements and storm suppression only reduce this exposure.
      duty =
        zone["campaign_bps"] / 10_000 * model["campaign"]["duration_ms"] /
          model["campaign"]["period_ms"]

      loading = 1 + duty * (model["campaign"]["multiplier"] - 1)

      IO.puts(
        Enum.join(
          [
            class_id,
            zone_id,
            fee,
            Float.round(avoided, 2),
            Float.round(surge_avoided, 2),
            loading
          ],
          ","
        )
      )

      if avoided >= fee * 0.75 and avoided <= fee * 1.3 and surge_avoided >= fee * 2.5 and
           loading <= p["loading_pct"] / 100, do: failures, else: [{class_id, zone_id} | failures]
  end

if failures != [], do: raise("Piracy calibration failed: #{inspect(failures)}")

IO.puts(
  "PASS: #{map_size(ShipClass.all()) * map_size(model["zones"])} class/zone pairs; base guards within 0.75–1.3x avoided cost; campaigns above 2.5x; insurance loading covers unannounced campaigns."
)
