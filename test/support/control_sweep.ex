defmodule TijaraTides.ControlSweep do
  @moduledoc """
  Rendered command controls and their submission outcomes.

  `controls/2` reads rendered LiveView HTML into one entry per way a player can submit a
  command: each submit form (one entry per named submit button) and each `phx-click`
  element whose event reaches a command submission, directly or through helpers.
  `outcomes/1` records command telemetry so a sweep can tell a commit from a
  rejection and see the rejection reason.
  """

  use Boundary

  @doc """
  Enabled command controls in `html`, keyed by {event, action, operation}. A form whose
  submitting button is disabled, or a disabled clickable element, offers no submission.
  """
  def controls(html, facts) do
    doc = LazyHTML.from_fragment(html)
    Enum.reject(forms(doc, facts) ++ clicks(doc, facts), & &1.disabled?)
  end

  defp forms(doc, facts) do
    for form <- LazyHTML.query(doc, "form[phx-submit]"),
        [event] = LazyHTML.attribute(form, "phx-submit"),
        fact = facts[event],
        fact && fact.command?,
        {submitter, disabled?} <- submitters(form) do
      id = form |> LazyHTML.attribute("id") |> List.first()
      hidden = values(form, "input[name=action]")
      action = submitter["action"] || one(hidden) || one(MapSet.to_list(fact.actions))

      %{
        kind: :form,
        event: event,
        id: id,
        key: {event, action, one(values(form, "[name=operation]"))},
        submitter: submitter,
        disabled?: disabled?
      }
    end
  end

  # Each named submit button is its own submission; unnamed buttons submit the form alone.
  defp submitters(form) do
    case for(button <- LazyHTML.query(form, "button[name][value]"), do: button) do
      [] ->
        buttons = for b <- LazyHTML.query(form, "button:not([type=button])"), do: b
        [{%{}, buttons != [] and Enum.all?(buttons, &disabled?/1)}]

      buttons ->
        for button <- buttons do
          [name] = LazyHTML.attribute(button, "name")
          [value] = LazyHTML.attribute(button, "value")
          {%{name => value}, disabled?(button)}
        end
    end
  end

  defp disabled?(node), do: LazyHTML.attribute(node, "disabled") != []

  defp clicks(doc, facts) do
    for element <- LazyHTML.query(doc, "[phx-click]"),
        [event] = LazyHTML.attribute(element, "phx-click"),
        not String.starts_with?(event, "["),
        fact = facts[event],
        fact && fact.command? do
      [attributes] = LazyHTML.attributes(element)

      values =
        for {"phx-value-" <> key, value} <- attributes, into: %{}, do: {key, value}

      action = values["action"] || one(MapSet.to_list(fact.actions))

      %{
        kind: :click,
        id: element |> LazyHTML.attribute("id") |> List.first(),
        event: event,
        key: {event, action, values["operation"]},
        values: values,
        disabled?: disabled?(element)
      }
    end
  end

  defp values(node, selector) do
    for input <- LazyHTML.query(node, selector),
        value <- LazyHTML.attribute(input, "value"),
        uniq: true,
        do: value
  end

  # A control whose action depends on state (sail or reroute) reports every candidate.
  defp one([value]), do: value
  defp one([]), do: nil
  defp one(values), do: Enum.sort(values)

  @doc "Collects `{outcome, reason}` for every command the calling process triggers."
  def outcomes(fun) do
    test = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(id, [:tijara_tides, :operation, :stop], &__MODULE__.record/4, {test, id})

    try do
      result = fun.()
      {result, drain(id, [])}
    after
      :telemetry.detach(id)
    end
  end

  @doc false
  def record(_event, _measurements, %{operation: :command} = metadata, {test, id}),
    do: send(test, {id, metadata.outcome, Map.get(metadata, :reason)})

  def record(_event, _measurements, _metadata, _config), do: :ok

  defp drain(id, acc) do
    receive do
      {^id, outcome, reason} -> drain(id, [{outcome, reason} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
