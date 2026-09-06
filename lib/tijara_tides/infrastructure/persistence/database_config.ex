defmodule TijaraTides.Infrastructure.Persistence.DatabaseConfig do
  @moduledoc "Server-only PostgreSQL connection settings, shared by runtime and connection checks."

  def options(url) when is_binary(url) do
    uri = URI.parse(url)

    unless uri.scheme in ["postgres", "postgresql"] and is_binary(uri.host) and
             uri.host != "" and is_binary(uri.userinfo) and
             is_binary(uri.path) and uri.path not in ["", "/"] and is_nil(uri.fragment) do
      raise ArgumentError, "DATABASE_URL must be a PostgreSQL connection URL"
    end

    # These are libpq parameters, not Postgrex settings. Never allow arbitrary
    # query options (such as ssl=false) to override the explicit TLS policy.
    query = URI.decode_query(uri.query || "")

    unless Enum.all?(query, fn
             {"sslmode", mode} -> mode in ["require", "verify-ca", "verify-full"]
             {"channel_binding", mode} -> mode in ["require", "prefer"]
             _ -> false
           end) do
      raise ArgumentError, "DATABASE_URL contains unsupported connection parameters"
    end

    [
      url: URI.to_string(%{uri | query: nil}),
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(uri.host),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ],
      pool_size: 2,
      idle_limit: 0,
      timeout: 15_000,
      connect_timeout: 15_000,
      show_sensitive_data_on_connection_error: false
    ]
  end
end
