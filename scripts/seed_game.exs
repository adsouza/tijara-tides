# Explicit operator action: creates one launch-root invitation, not a signup entitlement.
case TijaraTides.Infrastructure.GameServer.seed() do
  {:ok, code} -> IO.puts("Launch-root invitation (single use): #{code}")
  {:error, reason} -> raise "Game is unavailable: #{reason}"
end
