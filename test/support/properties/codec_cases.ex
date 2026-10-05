defmodule TijaraTides.Domain.CodecCases do
  @moduledoc "Independent persisted row fixtures, rather than rows made by the encoder under test."

  alias TijaraTides.Domain.{
    Account,
    Auction,
    DepartureRequest,
    LiquidationPool,
    Ship,
    VisitBudget
  }

  alias TijaraTides.Domain.CompanyFinance.Loan

  def kinds, do: [:budget, :request, :pool, :loan, :auction, :ship, :account]

  def sample(kind, amount, now, optional?) do
    optional = if optional?, do: now + 17
    reference = if optional?, do: "other"

    {codec, row, defaults} =
      case kind do
        :budget ->
          {VisitBudget.Rows,
           %{
             "id" => "visit",
             "company_id" => "company",
             "ship_id" => "ship",
             "stop_id" => "stop",
             "port" => "Jakarta",
             "amount" => amount,
             "remaining" => div(amount, 2),
             "strict" => optional?,
             "skip" => false,
             "visit" => now
           }, %{}}

        :request ->
          {DepartureRequest.Rows,
           %{
             "id" => "ship",
             "ship_id" => "ship",
             "company_id" => "company",
             "destination" => "Singapore",
             "stop_id" => "stop",
             "visit" => now,
             "configured" => if(optional?, do: amount),
             "policy" => "wait",
             "required" => amount,
             "blocked_ms" => now,
             "accumulated" => div(amount, 2),
             "window_deadline_ms" => optional,
             "cooldown_ms" => nil
           }, %{}}

        :pool ->
          {LiquidationPool.Rows,
           %{
             "id" => "warehouse",
             "company_id" => "company",
             "port" => "Jakarta",
             "status" => "grace",
             "expires_ms" => now,
             "grace_end_ms" => now + 17,
             "last_ms" => now,
             "original_blocks" => 3,
             "occupied_blocks" => 2,
             "rent" => amount,
             "duration_ms" => 100,
             "surcharge_bps" => 2500,
             "window_ms" => 200,
             "clearance_bps" => 1000,
             "handling_rate" => 7,
             "rent_due" => 11,
             "rent_remainder" => 13,
             "handling_due" => 5,
             "clearance_remainders" => %{"fruit" => %{"numerator" => 1, "denominator" => 3}},
             "proceeds" => amount,
             "charged" => 0,
             "paid" => 0,
             "sunk" => 0,
             "completed_ms" => nil,
             "replacement_paid" => 0
           }, %{"replacement_paid" => 0}}

        :loan ->
          {Loan,
           %{
             "id" => "loan",
             "company_id" => "company",
             "principal" => amount,
             "remaining" => div(amount, 2),
             "principal_due" => 3,
             "interest_due" => 5,
             "interest_accrued" => 7,
             "interest_remainder" => 11,
             "interest_at_ms" => now,
             "overdue_ms" => optional,
             "next_due_ms" => now + 100,
             "period_ms" => 100,
             "periods_left" => 3,
             "rate_bps" => 500,
             "installment" => div(amount, 3),
             "status" => "active",
             "created_ms" => 0,
             "guarantee_id" => reference
           }, %{"guarantee_id" => nil}}

        :auction ->
          {Auction.Rows,
           %{
             "id" => "auction",
             "company_id" => "company",
             "warehouse_id" => "warehouse",
             "port" => "Jakarta",
             "good" => "fruit",
             "quantity" => 17,
             "reserve" => amount,
             "opens_ms" => now + 1,
             "closes_ms" => now + 100,
             "status" => "scheduled",
             "price" => nil,
             "winner_id" => nil,
             "valuation_seed" => "fixed",
             "expires_ms" => optional
           }, %{"ship_id" => nil, "liquidation_id" => nil, "expires_ms" => nil}}

        :ship ->
          {Ship.Rows,
           %{
             "id" => "ship",
             "company_id" => "company",
             "name" => "Vessel",
             "class" => "freighter",
             "book_value" => amount,
             "build_value" => amount,
             "built_ms" => 0,
             "port" => "Jakarta",
             "cargo" => [],
             "status" => "docked",
             "arrive_ms" => nil,
             "destination" => nil,
             "depart_ms" => nil,
             "fuel_total" => 0,
             "fuel_burned" => 0,
             "crew_remainder" => 13,
             "last_cost_ms" => now,
             "last_liquid" => nil,
             "acquired_ms" => optional,
             "voyage_path" => if(optional?, do: [[103.8, 1.3], [106.8, -6.1]])
           }
           |> Map.merge(
             if(optional?,
               do: %{"handling_started_ms" => now, "handling_volume_l" => amount},
               else: %{}
             )
           ),
           Map.new(
             ~w(acquired_ms acquisition_value planned_destination weather voyage_path paid_canals voyage_speedup berth_queued_ms berth_granted_ms berth_retry_ms handling_started_ms handling_volume_l pending_side pending_good pending_quantity pending_limit pending_destination),
             &{&1, nil}
           )
           |> Map.put("cargo", [])}

        :account ->
          {Account.Rows,
           %{
             "id" => "account",
             "company_id" => reference,
             "inviter" => nil,
             "bankruptcies" => 1,
             "suspended_ms" => optional,
             "email" => nil,
             "invite_quota" => 2,
             "created_ms" => now,
             "locale" => "ar",
             "funding_policy" => "reduced"
           }, %{"funding_policy" => "wait"}}
      end

    # Encoder intentionally omits nil optional auction/ship fields.
    row =
      if kind in [:auction, :ship],
        do: Map.reject(row, fn {_, v} -> is_nil(v) end) |> Map.merge(required_nils(kind)),
        else: row

    %{codec: codec, row: row, defaults: defaults}
  end

  defp required_nils(:auction), do: %{"price" => nil, "winner_id" => nil}

  defp required_nils(:ship),
    do: %{"arrive_ms" => nil, "destination" => nil, "depart_ms" => nil, "last_liquid" => nil}

  def decode(Loan, row), do: Loan.from_row(row)
  def decode(codec, row), do: codec.decode(row)
  def encode(Loan, model), do: Loan.to_row(model)
  def encode(codec, model), do: codec.encode(model)

  def facts(model),
    do:
      model
      |> Map.from_struct()
      |> Map.drop([
        :bids,
        :route_plan,
        :visit_orders,
        :visit_plans,
        :sessions,
        :invitations,
        :email_requests,
        :bankruptcy_events
      ])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
end
