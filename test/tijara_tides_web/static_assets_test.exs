defmodule TijaraTidesWeb.StaticAssetsTest do
  # Writes probe files into priv/static, so it must not share the directory.
  use TijaraTidesWeb.ConnCase, async: false

  # A leftover `phx.digest` .gz must never shadow the bundle that tests just built.
  test "test builds serve the current uncompressed asset, not a stale .gz", %{conn: conn} do
    name = "gzip-probe-#{System.unique_integer([:positive])}.js"
    path = Application.app_dir(:tijara_tides, ["priv", "static", "assets", "js", name])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "current")
    File.write!(path <> ".gz", :zlib.gzip("stale"))

    on_exit(fn ->
      File.rm(path)
      File.rm(path <> ".gz")
    end)

    conn = conn |> put_req_header("accept-encoding", "gzip") |> get("/assets/js/" <> name)

    assert response(conn, 200) == "current"
    assert get_resp_header(conn, "content-encoding") == []
  end
end
