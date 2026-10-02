defmodule TijaraTides.Domain.DepartureRequest do
  @moduledoc "Pure departure request lifecycle and economic rules."
  @fields ~w(id ship_id company_id destination stop_id visit configured policy required blocked_ms accumulated window_deadline_ms cooldown_ms)a
  @enforce_keys @fields
  defstruct @fields

  def new(spec, policy, required, now) do
    %__MODULE__{
      id: spec.ship_id,
      ship_id: spec.ship_id,
      company_id: spec.company_id,
      destination: spec.port,
      stop_id: spec.stop_id,
      visit: spec.visit,
      configured: spec.configured,
      policy: policy,
      required: required,
      blocked_ms: now,
      accumulated: 0,
      window_deadline_ms: nil,
      cooldown_ms: nil
    }
  end

  def accumulate(%__MODULE__{} = request, amount, deadline) do
    unless amount >= 0 and request.accumulated + amount <= request.required,
      do: raise(ArgumentError, "Invalid departure accumulation")

    %{
      request
      | accumulated: request.accumulated + amount,
        window_deadline_ms: request.window_deadline_ms || deadline
    }
  end

  @doc "New terms keep waiting age and deadline; accumulation above the new requirement is returned."
  def reprice(%__MODULE__{} = request, policy, required) do
    unless is_integer(required) and required >= 0,
      do: raise(ArgumentError, "Invalid departure requirement")

    kept = min(request.accumulated, required)

    {%{request | policy: policy, required: required, accumulated: kept},
     request.accumulated - kept}
  end

  def release(%__MODULE__{} = request, cooldown),
    do: %{request | accumulated: 0, window_deadline_ms: nil, cooldown_ms: cooldown}
end
