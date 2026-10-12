defmodule Docs.MusicApprovalsTest do
  @moduledoc """
  A recorded approval must still describe the files and recipe it approved, so
  a stale sign-off fails in the change that made it stale. Pending approvals
  pass and are listed; they only keep production music unavailable.
  """
  use ExUnit.Case, async: true

  defp json(path), do: path |> File.read!() |> Jason.decode!()

  test "no listening approval is stale" do
    report =
      TijaraTidesWeb.Music.approval_report(
        json("priv/audio/music.json"),
        json("priv/music/approvals.json")
      )

    assert Map.get(report, :stale, []) == []

    for status <- [:pending, :rejected],
        item <- Map.get(report, status, []),
        do: IO.puts("music approval #{status}: #{item}")
  end

  test "the fixture soundtrack is fully approved" do
    report =
      TijaraTidesWeb.Music.approval_report(
        json("priv/audio/fixtures/music.json"),
        json("priv/music/fixtures/approvals.json")
      )

    assert Map.keys(report) == [:approved]
  end
end
