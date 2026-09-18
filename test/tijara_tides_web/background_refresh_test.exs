defmodule TijaraTidesWeb.BackgroundRefreshTest do
  use ExUnit.Case, async: true
  alias TijaraTidesWeb.GameLive

  test "a superseded background result cannot overwrite a foreground refresh" do
    socket = %Phoenix.LiveView.Socket{assigns: %{refresh_generation: 2, view: :newer_view}}

    assert {:noreply, ^socket} =
             GameLive.handle_async({:world_refresh, 1}, {:ok, {:stale_view, nil}}, socket)

    assert {:noreply, ^socket} =
             GameLive.handle_async({:world_refresh, 1}, {:exit, :cancelled}, socket)
  end

  test "a failed background fetch releases the task without discarding the displayed view" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        refresh_generation: 2,
        refresh_running: true,
        refresh_pending: false,
        dropdown_active: false,
        view: :current_view
      }
    }

    assert {:noreply, updated} =
             GameLive.handle_async({:world_refresh, 2}, {:exit, :timeout}, socket)

    refute updated.assigns.refresh_running
    assert updated.assigns.view == :current_view
  end
end
