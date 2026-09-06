defmodule TijaraTidesWeb.Layouts do
  use TijaraTidesWeb, :html
  embed_templates "layouts/*"
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main class="min-h-screen">{render_slot(@inner_block)}</main>
    <div
      :for={{kind, message} <- @flash}
      role="alert"
      class="fixed bottom-4 left-4 rounded bg-slate-800 p-4"
      id={"flash-#{kind}"}
    >
      {message}
    </div>
    """
  end
end
