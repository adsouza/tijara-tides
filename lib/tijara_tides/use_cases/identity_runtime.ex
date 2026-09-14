defmodule TijaraTides.UseCases.IdentityRuntime do
  @moduledoc "Device credentials and identity workflows, independent of gameplay and presence APIs."
  @type session :: String.t() | nil
  @type result :: {:ok, map()} | {:error, term()}
  @callback token() :: String.t()
  @callback redeem_for_device(String.t(), String.t()) :: result()
  @callback sign_out(session()) :: :ok | {:error, term()}
  @callback email_request(session(), String.t(), String.t(), String.t(), String.t()) :: result()
  @callback email_redeem(String.t(), String.t(), session()) :: result()
end
