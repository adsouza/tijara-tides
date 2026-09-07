defmodule TijaraTides.UseCases do
  @moduledoc "Transport-independent application operations."
  use Boundary, deps: [TijaraTides.Domain], exports: [WorldCommands, GameCommands]
end
