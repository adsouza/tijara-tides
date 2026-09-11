# Isolated synthetic state; no database or running application is used.
# Run with MIX_ENV=test mix run --no-start scripts/benchmark-state.exs
alias TijaraTides.Domain.{EntityIndex, Game}
alias TijaraTides.UseCases.{CommitPreparation, GameQueries, WorldProjection}
now = 2_000_000_000
catalogue = TijaraTides.Infrastructure.GameCatalogue.all()
base = Game.initialize(%{entities: %{}, clock_ms: now, revision: 0, epoch: 1}, catalogue)

companies =
  Map.new(1..1000, fn n ->
    id = "c#{n}"

    {id,
     %{
       "id" => id,
       "account_id" => "a#{n}",
       "name" => id,
       "cash" => 0,
       "reserved" => 0,
       "unpaid" => 0,
       "profit" => 0,
       "created_ms" => 0,
       "last_invite_year" => 0,
       "bankruptcy_ms" => nil,
       "unpaid_since" => nil,
       "arrears_since" => nil
     }}
  end)

accounts =
  Map.new(1..1000, fn n ->
    id = "a#{n}"

    {id,
     %{
       "id" => id,
       "company_id" => "c#{n}",
       "inviter" => nil,
       "bankruptcies" => 0,
       "suspended_ms" => nil,
       "email" => nil,
       "invite_quota" => 0,
       "created_ms" => 0
     }}
  end)

requests =
  Map.new(1..50_000, fn n ->
    id = "r#{n}"

    {id,
     %{
       "id" => id,
       "account_id" => "a#{rem(n, 1000) + 1}",
       "purpose" => "login",
       "created_ms" => 0,
       "expires_ms" => 1,
       "used_session" => nil,
       "delivery" => "sent",
       "retry_ms" => 0,
       "requester" => id,
       "email" => "#{id}@example.test",
       "token_hash" => id
     }}
  end)

game =
  %{
    base
    | entities:
        Map.merge(base.entities, %{
          "companies" => companies,
          "accounts" => accounts,
          "email_requests" => requests
        })
  }
  |> EntityIndex.rebuild()

game = CommitPreparation.prepare(game, game) |> CommitPreparation.accepted()

for {cache, game} <- [
      {"historical", game},
      {"active", TijaraTides.Domain.Account.compact_history(game, now)}
    ] do
  projection = WorldProjection.build(game, catalogue)

  for {label, fun} <- [
        {"commit preparation", fn -> CommitPreparation.prepare(game, game) end},
        {"private snapshot",
         fn -> GameQueries.snapshot(game, catalogue, projection, {:ok, accounts["a1"]}) end},
        {"email request",
         fn ->
           TijaraTides.Domain.EmailIdentity.request(game, nil, "login", "new@example.test", %{
             id: "new",
             hash: "new",
             requester: "new",
             wall_ms: now
           })
         end}
      ] do
    Enum.each(1..5, fn _ -> fun.() end)
    {us, _} = :timer.tc(fn -> Enum.each(1..100, fn _ -> fun.() end) end)
    IO.puts("#{cache} #{label}: #{Float.round(us / 100 / 1000, 3)} ms/op")
  end
end
