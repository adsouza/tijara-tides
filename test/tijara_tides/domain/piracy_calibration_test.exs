defmodule TijaraTides.Domain.PiracyCalibrationTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "the generated guard fees and insurance loading satisfy the economic calibration" do
    output = capture_io(fn -> Code.eval_file("scripts/calibrate-piracy.exs") end)
    catalogue = Jason.decode!(File.read!("priv/game/catalogue.json"))
    count = map_size(TijaraTides.Domain.ShipClass.all()) * map_size(catalogue["piracy"]["zones"])

    rows =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(&(length(String.split(&1, ",")) == 6))
      |> tl()

    assert length(rows) == count
    assert output =~ "PASS: #{count} class/zone pairs"
  end

  test "the audit reports the pairs actually checked when the catalogue roster changes" do
    catalogue = Jason.decode!(File.read!("priv/game/catalogue.json"))
    [removed | _] = Map.keys(catalogue["piracy"]["zones"])
    catalogue = update_in(catalogue["piracy"]["zones"], &Map.delete(&1, removed))

    path =
      Path.join(
        System.tmp_dir!(),
        "piracy-calibration-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(catalogue))
    on_exit(fn -> File.rm!(path) end)

    output =
      capture_io(fn ->
        Code.eval_string(File.read!("scripts/calibrate-piracy.exs"), [catalogue_path: path],
          file: "scripts/calibrate-piracy.exs"
        )
      end)

    count = map_size(TijaraTides.Domain.ShipClass.all()) * map_size(catalogue["piracy"]["zones"])
    assert output =~ "PASS: #{count} class/zone pairs"

    rows =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(&(length(String.split(&1, ",")) == 6))
      |> tl()

    assert length(rows) == count
  end
end
