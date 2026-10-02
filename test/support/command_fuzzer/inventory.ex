defmodule TijaraTides.CommandFuzzer.Inventory do
  @moduledoc "Static source inventories. Dynamic producers must resolve to checked literal alternatives."

  def commands(source \\ File.read!("lib/tijara_tides/domain/commands.ex")) do
    ast = Code.string_to_quoted!(source)

    {_, actions} =
      Macro.prewalk(ast, MapSet.new(), fn
        {"action", action} = node, acc when is_binary(action) ->
          {node, MapSet.put(acc, action)}

        {:in, _, [{:action, _, _}, alternatives]} = node, acc when is_list(alternatives) ->
          {node, Enum.reduce(alternatives, acc, &MapSet.put(&2, &1))}

        node, acc ->
          {node, acc}
      end)

    actions
  end

  def forms do
    Path.wildcard("lib/tijara_tides_web/**/*.{ex,heex}")
    |> Enum.flat_map(fn path ->
      Regex.scan(~r/phx-submit="([^"]+)"/, File.read!(path), capture: :all_but_first)
      |> Enum.map(fn [event] -> event end)
    end)
    |> MapSet.new()
  end

  def notices do
    Enum.flat_map(Path.wildcard("lib/tijara_tides/domain/**/*.ex"), fn path ->
      notice_source(File.read!(path), path)
    end)
  end

  def notice_source(source, path) do
    ast = Code.string_to_quoted!(source)
    # Handle the one local code binding (fleet handling) without silently ignoring dynamic codes.
    {_, variables} =
      Macro.prewalk(ast, %{}, fn
        {:=, _, [{name, _, context}, expression]} = node, acc
        when is_atom(name) and is_atom(context) ->
          case payload_codes(expression, %{}) do
            [] -> {node, acc}
            codes -> {node, Map.put(acc, name, codes)}
          end

        node, acc ->
          {node, acc}
      end)

    {_, entries} =
      Macro.prewalk(ast, [], fn node, acc ->
        node =
          case node do
            {kind, meta, [_head, body]} when kind in [:def, :defp] -> {:__block__, meta, [body]}
            other -> other
          end

        case call(node) do
          {meta, args} when length(args) in [3, 4] ->
            payload = List.last(args)
            codes = payload_codes(payload, variables)

            if codes == [] and not forwarding?(path, payload) do
              raise ArgumentError,
                    "Unresolved notice producer #{path}:#{meta[:line]}: #{Macro.to_string(payload)}"
            end

            {node, Enum.map(codes, &{&1, path, meta[:line]}) ++ acc}

          _ ->
            case node do
              {:%{}, meta, fields} ->
                case List.keyfind(fields, "code", 0) do
                  {"code", code} when is_binary(code) ->
                    {node, [{code, path, meta[:line]} | acc]}

                  {"code", {:code, _, nil}}
                  when path in [
                         "lib/tijara_tides/domain/company_finance_world.ex",
                         "lib/tijara_tides/domain/notices.ex"
                       ] ->
                    # This checked effect conversion forwards the already inventoried tuple.
                    {node, acc}

                  {"code", code} ->
                    raise ArgumentError,
                          "Unresolved notice effect #{path}:#{meta[:line]}: #{Macro.to_string(code)}"

                  nil ->
                    {node, acc}
                end

              _ ->
                {node, acc}
            end
        end
      end)

    Enum.uniq(entries)
  end

  defp call({:notice, meta, args}) when is_list(args), do: {meta, args}
  defp call({{:., _, [_, :notice]}, meta, args}) when is_list(args), do: {meta, args}
  defp call(_), do: nil

  defp payload_codes(code, _) when is_binary(code) do
    if Regex.match?(~r/^[a-z_]+\.[a-z_]+$/, code), do: [code], else: []
  end

  defp payload_codes({code, _arguments}, variables), do: payload_codes(code, variables)

  defp payload_codes({:if, _, [_condition, branches]}, variables),
    do: Enum.flat_map(branches, fn {_, expression} -> payload_codes(expression, variables) end)

  defp payload_codes({name, _, context}, variables) when is_atom(name) and is_atom(context),
    do: Map.get(variables, name, [])

  defp payload_codes(_, _), do: []

  # Checked forwarding seams, not producers. Reject any changed expression or a new dynamic site.
  defp forwarding?(path, payload) do
    expression = Macro.to_string(payload)

    {Path.basename(path), expression} in [
      {"company_finance.ex", "payload"},
      {"company_finance_world.ex",
       "if notice[\"code\"] do\n  {notice[\"code\"], notice[\"arguments\"]}\nelse\n  notice[\"text\"]\nend"}
    ]
  end

  def command_contracts do
    generated =
      ~w(company rename_ship markdown_preset_save markdown_preset_delete borrow repay recast funding_policy route instruction cancel_instruction sail buy sell cancel_berth_trade warehouse_lease warehouse_transfer warehouse_release exchange_place exchange_amend exchange_cancel bankruptcy)

    excluded =
      ~w(locale auction_consign auction_revise auction_withdraw auction_bid auction_withdraw_bid plan_destination reroute warehouse_reserve warehouse_cancel_reservation warehouse_replace warehouse_extend warehouse_renew warehouse_auto_renew visit_budget guarantee sell_ship instruction_onward purchase_ship invite)

    Map.new(
      Enum.map(generated, &{&1, %{mode: :planned, boundary: :admission, follow_up: 4}}) ++
        Enum.map(
          excluded,
          &{&1,
           %{
             mode: :excluded,
             reason: "Dedicated deterministic coverage; outside the initial sequence cohort",
             follow_up: "Prioritized after measured Round 4 cohort"
           }}
        )
    )
  end

  def form_contracts do
    covered = ~w(add-instruction exchange route borrow recast)

    excluded =
      ~w(auction email-request guarantee repay bankruptcy warehouse company instruction-onward trade purchase-ship funding-policy rename-ship sell-ship visit-budget)

    Map.new(
      Enum.map(covered, &{&1, :valid_variants}) ++
        Enum.map(
          excluded,
          &{&1,
           {:excluded,
            "Existing dedicated coverage; extend after measuring the initial 12 variants"}}
        )
    )
  end
end
