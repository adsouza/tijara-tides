defmodule TijaraTides.Infrastructure.Mailer do
  use Swoosh.Mailer, otp_app: :tijara_tides
end

defmodule TijaraTides.Infrastructure.EmailDelivery do
  @moduledoc "Retryable delivery of committed credentials; raw bearer tokens never enter stored game state."
  use GenServer
  require Logger
  alias TijaraTides.Infrastructure.{GameServer, Mailer}
  import Swoosh.Email
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def init(_), do: {:ok, nil, {:continue, :poll}}
  def handle_continue(:poll, state), do: poll(state)
  def handle_info(:poll, state), do: poll(state)
  def handle_info(_, state), do: {:noreply, state}

  defp deliver(message) do
    Mailer.deliver(message)
  rescue
    _ -> {:error, :delivery_failed}
  catch
    :exit, _ -> {:error, :delivery_failed}
  end

  # Do not log exceptions or GenServer exit payloads: they may contain credentials.
  defp safe_status(status) when status in [:unavailable, :disabled, :not_configured, :loading],
    do: status

  defp safe_status(_), do: :unknown
  defp exit_kind({:timeout, _}), do: :timeout
  defp exit_kind({:noproc, _}), do: :noproc
  defp exit_kind(_), do: :other

  defp poll(state) do
    if Application.get_env(:tijara_tides, :email_enabled, false) do
      try do
        case GameServer.email_pending() do
          [row | _] ->
            base = Application.fetch_env!(:tijara_tides, :email_base_url)
            url = base <> "/email/verify?token=" <> GameServer.email_token(row["id"])

            message =
              new()
              |> to(row["email"])
              |> from({"Tijara Tides", Application.fetch_env!(:tijara_tides, :email_from)})
              |> subject(
                if(row["purpose"] == "invite",
                  do: "Your Tijara Tides invitation",
                  else: "Your Tijara Tides sign-in link"
                )
              )
              |> text_body(
                "Open this link to verify your email and continue to Tijara Tides:\n\n#{url}\n\n#{if row["purpose"] == "invite", do: "This invitation expires after three days of active world time.", else: "This link expires in 15 minutes."}\n\nDo not forward this link. If you did not request it, ignore this email."
              )

            case deliver(message) do
              {:ok, _} -> GameServer.email_delivered(row["id"])
              _ -> GameServer.email_failed(row["id"])
            end

          {:error, status} ->
            Logger.warning("Email poll postponed: game unavailable (#{safe_status(status)})")

          [] ->
            :ok
        end
      rescue
        error -> Logger.error("Email poll failed: #{inspect(error.__struct__)}; retrying")
      catch
        :exit, reason ->
          Logger.warning("Email poll failed: game call exited (#{exit_kind(reason)}); retrying")
      end
    end

    Process.send_after(self(), :poll, 5000)
    {:noreply, state}
  end
end
