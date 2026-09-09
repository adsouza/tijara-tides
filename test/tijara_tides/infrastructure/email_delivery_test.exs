defmodule TijaraTides.Infrastructure.EmailDeliveryTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  alias TijaraTides.Infrastructure.EmailDelivery

  setup tags do
    enabled = Application.get_env(:tijara_tides, :email_enabled)
    server = Application.get_env(:tijara_tides, :game_server)
    keys = [:email_base_url, :email_from, TijaraTides.Infrastructure.Mailer]
    saved = Map.new(keys, &{&1, Application.fetch_env(:tijara_tides, &1)})
    poller = Process.whereis(EmailDelivery)
    unless tags[:supervisor_test], do: :sys.suspend(poller)

    on_exit(fn ->
      for {key, value} <- saved do
        case value do
          {:ok, value} -> Application.put_env(:tijara_tides, key, value)
          :error -> Application.delete_env(:tijara_tides, key)
        end
      end

      unless tags[:supervisor_test], do: :sys.resume(poller)
    end)

    on_exit(fn ->
      Application.put_env(:tijara_tides, :email_enabled, enabled)

      if server,
        do: Application.put_env(:tijara_tides, :game_server, server),
        else: Application.delete_env(:tijara_tides, :game_server)
    end)

    :ok
  end

  @tag :supervisor_test
  test "poller crashes do not restart Endpoint or the world" do
    endpoint = Process.whereis(TijaraTidesWeb.Endpoint)
    world = Process.whereis(TijaraTides.Infrastructure.GameServer)
    poller = Process.whereis(EmailDelivery)
    monitor = Process.monitor(poller)
    Process.exit(poller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^poller, :killed}
    wait_for_replacement(poller, 100)
    assert Process.whereis(TijaraTidesWeb.Endpoint) == endpoint
    assert Process.whereis(TijaraTides.Infrastructure.GameServer) == world
  end

  test "poll failures are logged without including payloads or credentials" do
    Application.put_env(:tijara_tides, :email_enabled, true)
    server = spawn(fn -> serve() end)
    on_exit(fn -> Process.exit(server, :kill) end)
    Application.put_env(:tijara_tides, :game_server, server)
    log = capture_log(fn -> assert {:noreply, nil} = EmailDelivery.handle_info(:poll, nil) end)
    assert log =~ "Email poll failed: CaseClauseError"
    refute log =~ "private-token@example.com"
    Process.exit(server, :kill)
    log = capture_log(fn -> assert {:noreply, nil} = EmailDelivery.handle_info(:poll, nil) end)
    assert log =~ "game call exited (noproc)"
  end

  defmodule DeliveryAdapter do
    use Swoosh.Adapter

    def deliver(message, config) do
      send(config[:owner], {:attempted_email, message})

      case config[:outcome] do
        :error -> {:error, :provider_unavailable}
        :raise -> raise "sensitive-provider-credential"
        :exit -> exit(:sensitive_provider_credential)
        :ok -> {:ok, %{id: "provider-receipt"}}
      end
    end
  end

  defmodule Outbox do
    use GenServer
    def start_link(args), do: GenServer.start_link(__MODULE__, args)
    def init(args), do: {:ok, args}

    def handle_call(:email_pending, _from, {owner, pending} = state) do
      send(owner, :polled)

      case pending do
        :exit -> {:stop, :shutdown, state}
        _ -> {:reply, pending, state}
      end
    end

    def handle_call(request, _from, {owner, _} = state) do
      send(owner, {:outbox_update, request})
      {:reply, :ok, state}
    end
  end

  defp configure(pending, outcome \\ :ok) do
    server = start_supervised!({Outbox, {self(), pending}}, id: make_ref())
    Application.put_env(:tijara_tides, :game_server, server)
    Application.put_env(:tijara_tides, :email_enabled, true)
    Application.put_env(:tijara_tides, :email_base_url, "https://game.example.com")
    Application.put_env(:tijara_tides, :email_from, "game@example.com")

    Application.put_env(:tijara_tides, TijaraTides.Infrastructure.Mailer,
      adapter: DeliveryAdapter,
      owner: self(),
      outcome: outcome
    )
  end

  test "successful invitations have the correct recipient and active-world expiry and are acknowledged" do
    configure([%{"id" => "invite", "email" => "recipient@example.com", "purpose" => "invite"}])
    assert {:noreply, nil} = EmailDelivery.handle_info(:poll, nil)
    assert_receive {:attempted_email, message}
    assert message.to == [{"", "recipient@example.com"}]
    assert message.from == {"Tijara Tides", "game@example.com"}
    assert message.subject == "Your Tijara Tides invitation"
    assert message.text_body =~ "three days of active world time"
    assert message.text_body =~ "https://game.example.com/email/verify?token="
    assert_receive {:outbox_update, {:email_delivered, "invite"}}
    refute_received {:outbox_update, {:email_failed, _}}
  end

  for outcome <- [:error, :raise, :exit] do
    test "provider #{outcome} records failure for backoff instead of acknowledging delivery" do
      configure(
        [%{"id" => "login", "email" => "recipient@example.com", "purpose" => "login"}],
        unquote(outcome)
      )

      log = capture_log(fn -> assert {:noreply, nil} = EmailDelivery.handle_info(:poll, nil) end)
      assert_receive {:attempted_email, message}
      assert message.subject == "Your Tijara Tides sign-in link"
      assert message.text_body =~ "15 minutes"
      assert_receive {:outbox_update, {:email_failed, "login"}}
      refute_received {:outbox_update, {:email_delivered, _}}
      refute log =~ "sensitive"
    end
  end

  test "disabled delivery and unrelated messages leave the outbox alone; empty polls do not send" do
    configure([])
    Application.put_env(:tijara_tides, :email_enabled, false)
    assert {:noreply, nil} = EmailDelivery.handle_continue(:poll, nil)
    assert {:noreply, nil} = EmailDelivery.handle_info(:unrelated, nil)
    refute_received :polled
    Application.put_env(:tijara_tides, :email_enabled, true)
    assert {:noreply, nil} = EmailDelivery.handle_info(:poll, nil)
    assert_receive :polled
    refute_received {:attempted_email, _}
    refute_received {:outbox_update, _}
  end

  test "unavailable or unknown world states log safely without attempting delivery" do
    for {status, expected} <- [
          {:unavailable, "unavailable"},
          {{:sensitive, "private"}, "unknown"}
        ] do
      configure({:error, status})
      log = capture_log(fn -> EmailDelivery.handle_info(:poll, nil) end)
      assert log =~ "game unavailable (#{expected})"
      refute log =~ "private"
      refute_received {:attempted_email, _}
    end
  end

  test "world termination during polling is diagnosed and leaves the worker available" do
    configure(:exit)
    log = capture_log(fn -> assert {:noreply, nil} = EmailDelivery.handle_info(:poll, nil) end)
    assert log =~ "game call exited (other)"
    refute_received {:attempted_email, _}
  end

  defp serve do
    receive do
      {:"$gen_call", from, :email_pending} ->
        GenServer.reply(from, {:unexpected, "private-token@example.com"})
        serve()
    end
  end

  defp wait_for_replacement(old, tries) when tries > 0 do
    case Process.whereis(EmailDelivery) do
      pid when is_pid(pid) and pid != old ->
        :ok

      _ ->
        receive do
        after
          10 -> wait_for_replacement(old, tries - 1)
        end
    end
  end

  defp wait_for_replacement(_, 0), do: flunk("email worker did not restart")
end
