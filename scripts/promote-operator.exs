# Use --no-start so selector and request checks precede claiming the world.
arguments =
  case System.argv() do
    ["--" | rest] -> rest
    rest -> rest
  end

{options, positional, invalid} =
  OptionParser.parse(arguments,
    strict: [account: [:string, :keep], email: [:string, :keep], request_id: [:string, :keep]]
  )

selector =
  case {Keyword.get_values(options, :account), Keyword.get_values(options, :email)} do
    {[id], []} -> {:account, id}
    {[], [email]} -> {:email, email}
    _ -> nil
  end

unless invalid == [] and positional == [] and selector != nil and
         length(Keyword.get_values(options, :request_id)) == 1 do
  raise "Usage: mix run --no-start scripts/promote-operator.exs -- " <>
          "(--account ID | --email EMAIL) --request-id UNIQUE_ID"
end

TijaraTides.Release.promote_operator(selector, Keyword.fetch!(options, :request_id))
