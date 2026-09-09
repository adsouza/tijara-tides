defmodule TijaraTides.Infrastructure.EmailConfigTest do
  use ExUnit.Case, async: false

  setup do
    keys =
      ~w(RESEND_API_KEY SMTP_HOST EMAIL_FROM EMAIL_BASE_URL SECRET_KEY_BASE DATABASE_URL PHX_HOST RENDER_EXTERNAL_HOSTNAME)

    previous = Map.new(keys, &{&1, System.get_env(&1)})
    Enum.each(keys, &System.delete_env/1)
    System.put_env("SECRET_KEY_BASE", String.duplicate("test", 16))

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "Resend enables email over HTTPS and takes precedence over SMTP" do
    System.put_env("RESEND_API_KEY", "re_test_only")
    System.put_env("SMTP_HOST", "unused.example.test")
    System.put_env("EMAIL_FROM", "game@example.test")
    System.put_env("EMAIL_BASE_URL", "https://game.example.test/")
    config = Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
    assert get_in(config, [:tijara_tides, :email_enabled])
    assert get_in(config, [:tijara_tides, :email_base_url]) == "https://game.example.test"
    assert get_in(config, [:swoosh, :api_client]) == Swoosh.ApiClient.Req
    mailer = get_in(config, [:tijara_tides, TijaraTides.Infrastructure.Mailer])
    assert mailer[:adapter] == Swoosh.Adapters.Resend
    assert mailer[:api_key] == "re_test_only"
    refute mailer[:relay]
  end

  test "no provider leaves email disabled" do
    config = Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
    refute get_in(config, [:tijara_tides, :email_enabled])
  end

  test "Resend requires a sender and a safe public origin" do
    System.put_env("RESEND_API_KEY", "re_test_only")
    System.put_env("EMAIL_BASE_URL", "http://game.example.test")

    assert_raise RuntimeError, ~r/HTTPS origin/, fn ->
      Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
    end

    System.put_env("EMAIL_BASE_URL", "https://game.example.test")

    assert_raise System.EnvError, fn ->
      Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
    end
  end

  test "custom host and Render hostname are the only allowed production origins" do
    System.put_env("PHX_HOST", "tijara.adsouza.net")
    System.put_env("RENDER_EXTERNAL_HOSTNAME", "tijara-tides.onrender.com")
    config = Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
    endpoint = get_in(config, [:tijara_tides, TijaraTidesWeb.Endpoint])
    assert endpoint[:url][:host] == "tijara.adsouza.net"

    assert endpoint[:check_origin] == [
             "https://tijara.adsouza.net",
             "https://tijara-tides.onrender.com"
           ]
  end
end
