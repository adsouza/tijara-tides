defmodule TijaraTides.UseCases.Game do
  @moduledoc "Application entry point for player interfaces. Runtime services are supplied by the composition root."

  defp runtime, do: Application.fetch_env!(:tijara_tides, :game_runtime)
  defp identity, do: Application.fetch_env!(:tijara_tides, :identity_runtime)
  defp presence, do: Application.fetch_env!(:tijara_tides, :presence_runtime)
  defp operations, do: Application.fetch_env!(:tijara_tides, :operations_runtime)

  def snapshot(token), do: runtime().snapshot(token)
  def reports(token, selection), do: runtime().reports(token, selection)
  def preview(token, ship, destination), do: runtime().preview(token, ship, destination)
  def command(token, request_id, payload), do: runtime().command(token, request_id, payload)
  def connect(token), do: runtime().connect(token)
  def subscribe(), do: runtime().subscribe()
  def definitions(), do: runtime().definitions()
  def request_id(), do: runtime().request_id()
  def token(), do: identity().token()
  def redeem_for_device(code, device), do: identity().redeem_for_device(code, device)
  def sign_out(token), do: identity().sign_out(token)

  def email_request(token, purpose, address, request_id, requester),
    do: identity().email_request(token, purpose, address, request_id, requester)

  def email_redeem(code, device, signed_in), do: identity().email_redeem(code, device, signed_in)
  def readiness(), do: operations().readiness()
  def database_readiness(), do: operations().database_readiness()
  def presence_snapshot(), do: presence().presence_snapshot()
  def presence_subscribe(world), do: presence().presence_subscribe(world)
  def presence_attach(player), do: presence().presence_attach(player)
  def presence_detach(), do: presence().presence_detach()

  def log_exception(message, error, stacktrace),
    do: operations().log_exception(message, error, stacktrace)

  def cargo_name(good), do: definitions().catalogue["goods"][good]["name"] || good
end
