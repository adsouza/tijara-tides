defmodule TijaraTidesWeb.CoreComponents do
  @moduledoc "Shared UI primitives. Add components as the interface takes shape."
  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :any, default: "size-5"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} aria-hidden="true" />
    """
  end
end
