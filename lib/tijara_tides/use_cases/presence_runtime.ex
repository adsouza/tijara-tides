defmodule TijaraTides.UseCases.PresenceRuntime do
  @moduledoc "Ephemeral connection roster; no durable gameplay or credential operations."
  @type snapshot :: %{
          world_id: String.t(),
          revision: non_neg_integer(),
          online_players: non_neg_integer(),
          connections: non_neg_integer()
        }
  @callback presence_snapshot() :: snapshot()
  @callback presence_subscribe(String.t()) :: :ok | {:error, term()}
  @callback presence_attach(String.t()) :: snapshot() | {:error, atom()}
  @callback presence_detach() :: :ok
end
