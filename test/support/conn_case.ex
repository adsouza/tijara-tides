defmodule TijaraTidesWeb.ConnCase do
  @moduledoc "HTTP and LiveView test helpers; no database is required."
  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TijaraTidesWeb.Endpoint

      use TijaraTidesWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TijaraTidesWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
