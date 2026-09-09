defmodule TijaraTides.Infrastructure.Persistence.Repo.Migrations.UseCargoMachineIds do
  use Ecto.Migration

  # Frozen migration mapping: display labels and runtime catalogues may evolve.
  @ids [
    {"Agricultural machinery", "agricultural_machinery"},
    {"Appliances", "appliances"},
    {"Construction equipment", "construction_equipment"},
    {"Copper scrap", "copper_scrap"},
    {"Crude oil", "crude_oil"},
    {"Designer clothing", "designer_clothing"},
    {"Electronics", "electronics"},
    {"Everyday clothing", "everyday_clothing"},
    {"Fruit", "fruit"},
    {"Grain", "grain"},
    {"Iron ore", "iron_ore"},
    {"Jewelry", "jewelry"},
    {"Lumber", "lumber"},
    {"Meat", "meat"},
    {"Recovered plastics", "recovered_plastics"},
    {"Refined fuel", "refined_fuel"},
    {"Scrap aluminium", "aluminium_scrap"},
    {"Seafood", "seafood"},
    {"Spices", "spices"},
    {"Turbines", "turbines"},
    {"Vegetable oil", "vegetable_oil"},
    {"Whisky", "whisky"}
  ]

  def up do
    rename_ids(@ids)

    execute(
      "ALTER TABLE game_cargo_types ADD CONSTRAINT cargo_machine_id CHECK (id ~ '^[a-z]+(_[a-z]+)*$')"
    )
  end

  def down do
    execute("ALTER TABLE game_cargo_types DROP CONSTRAINT cargo_machine_id")
    rename_ids(Enum.map(@ids, fn {old, new} -> {new, old} end))
  end

  defp rename_ids(ids) do
    # Run with the game stopped. Keep the temporary trigger exceptions and all
    # reference updates inside Ecto's migration transaction and exclusive locks.
    execute(
      "LOCK TABLE game_cargo_types, game_ships, game_markets, game_cargo_lots, game_cargo_holdings, game_ship_instructions, game_journal_transactions IN ACCESS EXCLUSIVE MODE"
    )

    execute("ALTER TABLE game_cargo_lots DISABLE TRIGGER immutable_lots")
    execute("ALTER TABLE game_journal_transactions DISABLE TRIGGER seal_journal")

    for {old, new} <- ids do
      execute(
        "INSERT INTO game_cargo_types(id,display_name) SELECT '#{new}',display_name FROM game_cargo_types WHERE id='#{old}'"
      )

      for {table, column} <- [
            {"game_ships", "last_liquid_good_id"},
            {"game_markets", "good_id"},
            {"game_cargo_lots", "good_id"},
            {"game_ship_instructions", "good_id"},
            {"game_journal_transactions", "good_id"}
          ] do
        execute("UPDATE #{table} SET #{column}='#{new}' WHERE #{column}='#{old}'")
      end

      # Market keys encode the port and cargo ID. Holdings use a deferred FK;
      # update the parent first so holding validation sees the new cargo type.
      execute("""
      UPDATE game_markets SET id=port_id || '|#{new}' WHERE good_id='#{new}';
      """)

      execute("""
      UPDATE game_cargo_holdings h SET market_id=m.id
      FROM game_markets m
      WHERE h.world_id=m.world_id AND m.good_id='#{new}'
        AND h.market_id=m.port_id || '|#{old}';
      """)

      execute("DELETE FROM game_cargo_types WHERE id='#{old}'")
    end

    execute("ALTER TABLE game_cargo_lots ENABLE TRIGGER immutable_lots")
    execute("ALTER TABLE game_journal_transactions ENABLE TRIGGER seal_journal")
  end
end
