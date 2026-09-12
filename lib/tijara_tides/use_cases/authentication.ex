defmodule TijaraTides.UseCases.Authentication do
  @moduledoc """
  Shared application authentication boundary. Accepts session hashes and an explicit
  wall clock; never caches an account across attempts. Ownership and business
  eligibility remain domain rules. Optional authentication permits anonymous reads
  and login flows; it must not be used to bypass a protected operation's requirements.
  """
  alias TijaraTides.Domain.Account

  def required(game, session_hash, wall_ms) when is_binary(session_hash),
    do: Account.authenticate(game, session_hash, wall_ms)

  def required(_game, _session_hash, _wall_ms), do: {:error, :invalid_session}

  def optional(game, session_hash, wall_ms) do
    case required(game, session_hash, wall_ms) do
      {:ok, account} -> account
      {:error, :invalid_session} -> nil
    end
  end
end
