defmodule TijaraTides.Domain.PiracyCalibrationTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "the generated guard fees and insurance loading satisfy the economic calibration" do
    output = capture_io(fn -> Code.eval_file("scripts/calibrate-piracy.exs") end)
    assert output =~ "PASS: 40 class/zone pairs"
  end
end
