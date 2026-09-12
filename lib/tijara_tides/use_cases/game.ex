defmodule TijaraTides.UseCases.Game do
  @moduledoc "Application entry point for player interfaces. Runtime services are supplied by the composition root."

  defp runtime, do: Application.fetch_env!(:tijara_tides, :game_runtime)

  def snapshot(token), do: runtime().snapshot(token)
  def reports(token, selection), do: runtime().reports(token, selection)
  def preview(token, ship, destination), do: runtime().preview(token, ship, destination)
  def command(token, request_id, payload), do: runtime().command(token, request_id, payload)
  def connect(token), do: runtime().connect(token)
  def subscribe(), do: runtime().subscribe()
  def definitions(), do: runtime().definitions()
  def request_id(), do: runtime().request_id()
  def token(), do: runtime().token()
  def redeem_for_device(code, device), do: runtime().redeem_for_device(code, device)
  def sign_out(token), do: runtime().sign_out(token)

  def email_request(token, purpose, address, request_id, requester),
    do: runtime().email_request(token, purpose, address, request_id, requester)

  def email_redeem(code, device, signed_in), do: runtime().email_redeem(code, device, signed_in)
  def readiness(), do: runtime().readiness()
  def database_readiness(), do: runtime().database_readiness()
  def presence_snapshot(), do: runtime().presence_snapshot()
  def presence_subscribe(world), do: runtime().presence_subscribe(world)
  def presence_attach(player), do: runtime().presence_attach(player)
  def presence_detach(), do: runtime().presence_detach()

  def log_exception(message, error, stacktrace),
    do: runtime().log_exception(message, error, stacktrace)

  def cargo_name(good), do: definitions().catalogue["goods"][good]["name"] || good
end
