defmodule TijaraTides.Infrastructure.ReportRetryTest do
  use ExUnit.Case, async: true
  alias TijaraTides.Infrastructure.GameServer

  defmodule Store do
    def page({observer, failures}, _selection, _owner, expected) do
      send(observer, {:read, expected.revision})

      if expected.revision <= failures do
        {:error, :report_revision_changed}
      else
        {:ok,
         %{
           ranked: [],
           provisional: [],
           own: [],
           ranked_count: 0,
           provisional_count: 0,
           own_count: 0
         }}
      end
    end
  end

  defmodule Owner do
    use GenServer
    def start_link(args), do: GenServer.start_link(__MODULE__, args)
    def init(args), do: {:ok, {args, 0}}

    def handle_call({:report_plan, _token, selection}, _from, {args, revision}) do
      revision = revision + 1

      plan = %{
        selection: TijaraTides.UseCases.ReportQueries.selection(0, selection),
        owner: nil,
        expected: %{epoch: 1, revision: revision, clock_ms: 0}
      }

      {:reply, {:ok, plan, {Store, args}}, {args, revision}}
    end
  end

  test "a stale read obtains a fresh plan and succeeds" do
    owner = start_supervised!({Owner, {self(), 1}})
    assert {:ok, _} = GameServer.reports(nil, %{}, owner)
    assert_received {:read, 1}
    assert_received {:read, 2}
    refute_received {:read, 3}
  end

  test "continuous revision changes stop after two retries" do
    owner = start_supervised!({Owner, {self(), 10}})
    assert {:error, :report_revision_changed} = GameServer.reports(nil, %{}, owner)
    for revision <- 1..3, do: assert_received({:read, ^revision})
    refute_received {:read, 4}
  end
end
