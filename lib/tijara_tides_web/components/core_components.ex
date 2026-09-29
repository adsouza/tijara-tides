defmodule TijaraTidesWeb.CoreComponents do
  @moduledoc "Shared UI primitives. Add components as the interface takes shape."
  use Phoenix.Component

  @doc "A decorative emoji accompanying a visible, translated label."
  attr :symbol, :string, required: true

  def emoji(assigns) do
    ~H"""
    <span class="ui-emoji" aria-hidden="true">{@symbol}</span>
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: "size-5"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} aria-hidden="true" />
    """
  end
end
