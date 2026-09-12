defmodule TijaraTides.Infrastructure.GameRuntime do
  @moduledoc "OTP and infrastructure implementation of the application runtime port."
  @behaviour TijaraTides.UseCases.GameRuntime
  alias TijaraTides.Infrastructure.{GameServer, WorldServer, ExceptionLog}

  @impl true
  def snapshot(token), do: GameServer.snapshot(token)

  @impl true
  def reports(token, selection), do: GameServer.reports(token, selection)

  @impl true
  def preview(token, ship, destination), do: GameServer.preview(token, ship, destination)

  @impl true
  def command(token, request_id, payload), do: GameServer.command(token, request_id, payload)

  @impl true
  def connect(token), do: GameServer.connect(token)

  @impl true
  def subscribe(), do: GameServer.subscribe()

  @impl true
  def definitions(), do: GameServer.definitions()

  @impl true
  def request_id(), do: GameServer.request_id()

  @impl true
  def token(), do: GameServer.token()

  @impl true
  def redeem_for_device(code, device), do: GameServer.redeem_for_device(code, device)

  @impl true
  def sign_out(token), do: GameServer.sign_out(token)

  @impl true
  def email_request(token, purpose, address, request_id, requester),
    do: GameServer.email_request(token, purpose, address, request_id, requester)

  @impl true
  def email_redeem(code, device, signed_in), do: GameServer.email_redeem(code, device, signed_in)

  @impl true
  def readiness(), do: GameServer.readiness()

  @impl true
  def database_readiness(), do: TijaraTides.Infrastructure.Persistence.Readiness.status()

  @impl true
  def presence_snapshot(), do: WorldServer.snapshot()

  @impl true
  def presence_subscribe(world), do: WorldServer.subscribe(world)

  @impl true
  def presence_attach(player), do: WorldServer.attach(player)

  @impl true
  def presence_detach(), do: WorldServer.detach()

  @impl true
  def log_exception(message, error, stacktrace),
    do: ExceptionLog.error(message, error, stacktrace)
end
