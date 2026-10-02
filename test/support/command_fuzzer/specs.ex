defmodule TijaraTides.CommandFuzzer.Specs do
  @moduledoc "Payload builders, model preconditions and targeted rejection contracts."
  alias TijaraTides.CommandFuzzer.Scenarios, as: S

  def payload(step, b) do
    base =
      case step.spec do
        :company ->
          %{"action" => "company"}

        :guarantee ->
          %{"action" => "guarantee", "account" => b.beneficiary}

        op when op in [:borrow, :purchase_ship, :funding_policy, :bankruptcy, :locale] ->
          %{"action" => Atom.to_string(op)}

        op when op in [:repay, :recast] ->
          %{"action" => Atom.to_string(op), "loan" => b.loan}

        :rename_ship ->
          %{"action" => "rename_ship", "ship" => b.ship}

        :foreign_ship ->
          %{"action" => "rename_ship", "ship" => b.b_ship}

        :preset_save ->
          TijaraTides.CommandFuzzer.Contracts.name_command(:preset, "Explored")

        :preset_delete ->
          %{"action" => "markdown_preset_delete", "preset" => b.preset}

        op when op in [:buy, :queued_buy, :sell] ->
          %{
            "action" => if(op == :sell, do: "sell", else: "buy"),
            "ship" => if(op == :queued_buy, do: b.ship_two, else: b.ship),
            "good" => "lumber",
            "quantity" => 1,
            "limit" => if(op == :sell, do: 0, else: 1_000_000),
            "destination" => "Singapore"
          }

        :cancel_berth_trade ->
          %{"action" => "cancel_berth_trade", "ship" => b.ship_two}

        op when op in [:sail, :reroute] ->
          %{"action" => Atom.to_string(op), "ship" => b.ship}

        :warehouse_lease ->
          %{
            "action" => "warehouse_lease",
            "port" => "Jakarta",
            "storage" => "dry",
            "blocks" => 1,
            "days" => 1,
            "price" => 100
          }

        :warehouse_store ->
          %{
            "action" => "warehouse_transfer",
            "ship" => b.ship,
            "warehouse" => b.warehouse,
            "side" => "store",
            "good" => "lumber"
          }

        :warehouse_release ->
          %{"action" => "warehouse_release", "warehouse" => b.warehouse, "blocks" => 1}

        :add_stop ->
          %{"action" => "route", "ship" => b.ship, "operation" => "add_stop"}

        :add_rule ->
          %{
            "action" => "route",
            "ship" => b.ship,
            "operation" => "add_rule",
            "stop" => b.origin,
            "side" => "buy",
            "good" => "lumber"
          }

        :remove_rule ->
          %{"action" => "route", "ship" => b.ship, "operation" => "remove_rule", "rule" => b.rule}

        op when op in [:start, :pause, :resume] ->
          %{
            "action" => "route",
            "ship" => b.ship,
            "operation" => Atom.to_string(op),
            "auto_depart" => false
          }

        :visit_budget_origin ->
          %{"action" => "visit_budget", "ship" => b.ship, "stop" => b.origin}

        :visit_budget_destination ->
          %{"action" => "visit_budget", "ship" => b.ship, "stop" => b.destination}
      end

    Map.merge(base, step.params)
  end

  # Preconditions inspect only the small model, never the production admission predicate.
  def eligible?(%{op: op}, _) when op in [:observe, :replay, :restart, :wall], do: true
  def eligible?(%{op: :tick, target: {:arrival, _}}, m), do: m.ship_deadline != nil
  def eligible?(%{op: :tick, target: {:fraction, _, _}}, m), do: m.ship_status == "sailing"
  def eligible?(%{op: :tick}, _), do: true
  def eligible?(%{expected: :berth_order_pending}, m), do: m.pending
  def eligible?(%{spec: :queued_buy}, m), do: not m.pending and m.queued_status == "docked"
  def eligible?(%{spec: :cancel_berth_trade}, m), do: m.pending
  def eligible?(%{spec: :borrow, actor: :a, expected: :ok}, m), do: m.loan == nil and m.active

  def eligible?(%{spec: :recast, actor: :a}, m),
    do: m.loan != nil and m.clock_ms == m.loan_ms and m.debts[m.loan] > 100

  def eligible?(%{spec: :repay, actor: :a}, m), do: m.loan != nil

  def eligible?(%{spec: :buy}, m),
    do:
      m.active and m.ship_status == "docked" and m.port == "Jakarta" and m.cargo < 20 and
        m.route == nil

  def eligible?(%{spec: :sell}, m),
    do: m.active and m.ship_status == "docked" and m.port == "Singapore" and m.cargo > 0

  def eligible?(%{spec: :sail}, m), do: m.active and m.ship_status == "docked"
  def eligible?(%{spec: :reroute}, m), do: m.ship_status == "sailing"

  def eligible?(%{spec: :warehouse_store}, m),
    do: m.warehouse and m.ship_status == "docked" and m.cargo > 0

  def eligible?(%{spec: :warehouse_release}, m), do: m.warehouse and m.stored == 0
  def eligible?(%{spec: :warehouse_lease}, m), do: m.active and not m.warehouse
  def eligible?(%{spec: :preset_delete}, m), do: m.preset
  def eligible?(%{spec: :preset_save}, m), do: not m.preset
  def eligible?(%{spec: :remove_rule}, m), do: m.rule
  def eligible?(%{spec: :pause}, m), do: m.route == :running
  def eligible?(%{spec: :resume}, m), do: m.route == :paused

  def eligible?(%{spec: op}, m)
      when op in [:rename_ship, :foreign_ship, :funding_policy, :borrow], do: m.active

  def eligible?(_, _), do: true

  def suffix(choices, prefix_size, broad? \\ false) do
    choices
    |> Enum.with_index(prefix_size + 1)
    |> Enum.map(fn {{choice, value, mutation}, slot} ->
      if rem(slot, 3) == 0 and choice >= 8 do
        %{
          op: Enum.at([:observe, :replay, :restart, :tick], rem(choice, 4)),
          target: if(rem(value, 2) == 0, do: 0, else: 60_000),
          invariant: nil
        }
      else
        spec =
          Enum.at(
            [
              :borrow,
              :recast,
              :repay,
              :rename_ship,
              :preset_save,
              :preset_delete,
              :funding_policy,
              :warehouse_lease,
              :warehouse_release,
              :buy,
              :sell,
              :pause,
              :resume,
              :remove_rule,
              :locale
            ],
            rem(choice, 15)
          )

        params =
          case spec do
            :borrow -> %{"amount" => 1000 + value * 100}
            :recast -> %{"amount" => 100}
            :rename_ship -> %{"name" => "Explored #{slot}:#{value}"}
            :preset_save -> %{"name" => "Explored #{slot}:#{value}"}
            :funding_policy -> %{"policy" => Enum.at(~w(wait reduced skip), rem(value, 3))}
            :locale -> %{"locale" => Enum.at(~w(en ar), rem(value, 2))}
            op when op in [:buy, :sell] -> %{"quantity" => 1}
            _ -> %{}
          end

        if broad? and mutation == 0 do
          case rem(choice, 3) do
            0 -> S.command(:borrow, %{"amount" => 0}, error: :loan_invalid_amount)
            1 -> S.command(:rename_ship, %{"name" => "a\0b"}, error: :ship_name_invalid)
            2 -> S.command(:foreign_ship, %{"name" => "Foreign"}, error: :ship_not_owned)
          end
        else
          S.command(spec, params,
            as:
              case spec do
                :borrow -> :loan
                :preset_save -> :preset
                :warehouse_lease -> :warehouse
                _ -> nil
              end
          )
        end
      end
    end)
  end

  def broad_prefix do
    [
      S.command(:borrow, %{"amount" => 1000}, as: :loan),
      S.command(:recast, %{"amount" => 100}),
      S.command(:repay),
      S.command(:preset_save, %{}, as: :preset),
      S.command(:preset_delete)
    ]
  end
end
