# Use --no-start so argument and target checks run before the world is claimed.
arguments =
  case System.argv() do
    ["--" | rest] -> rest
    rest -> rest
  end

{options, positional, invalid} =
  OptionParser.parse(arguments,
    strict: [
      account: [:string, :keep],
      email: [:string, :keep],
      count: [:integer, :keep],
      request_id: [:string, :keep]
    ]
  )

selector =
  case {Keyword.get_values(options, :account), Keyword.get_values(options, :email)} do
    {[id], []} -> {:account, id}
    {[], [email]} -> {:email, email}
    _ -> nil
  end

unless invalid == [] and positional == [] and selector != nil and
         length(Keyword.get_values(options, :count)) == 1 and
         length(Keyword.get_values(options, :request_id)) == 1 do
  raise "Usage: mix run --no-start scripts/grant-invitations.exs -- " <>
          "(--account ID | --email EMAIL) --count 1..3 --request-id UNIQUE_ID"
end

TijaraTides.Release.grant_invitations(
  selector,
  Keyword.fetch!(options, :count),
  Keyword.fetch!(options, :request_id)
)
