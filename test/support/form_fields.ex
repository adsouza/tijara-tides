defmodule TijaraTides.FormFields do
  @moduledoc """
  Static field inventory: what each template sends to an event, and what its handler reads.

  Templates are read from `~H` sigils. A field is sent by a named `input`, `select`,
  `textarea` or `button` inside `<form phx-submit="event">`, or by `phx-value-*`
  and `JS.push(..., value: %{...})` on a `phx-click="event"` element. A handler reads
  a field through its head pattern, `params["field"]`, `Map.get/2,3`, `Map.take/2`,
  or a local function receiving `params`. Passing `params` anywhere else forwards
  every field except literal `Map.drop/2` keys. Unresolvable names raise.

  `dropped/3` adds the admission dimension: `GameLive.run/2` keeps only fields the
  submitted action's `CommandPayload` schema admits, so each form field must be
  admitted by one of the form's actions or converted by its handler.
  """

  use Boundary, deps: [TijaraTides.UseCases]

  @web "lib/tijara_tides_web/**/*.ex"
  @handlers "lib/tijara_tides_web/live/game_live.ex"
  @controls ~w(input select textarea button)

  # Action values bound from assigns rather than literal :for lists, with the guard
  # that limits them. An undeclared dynamic action value raises.
  @dynamic_actions %{
    # handle_event("port-market-side", ...) only assigns "buy" or "sell".
    {"ports_panel.ex", "side"} => ~w(buy sell)
  }

  @doc "Every web source as {path, contents}."
  def sources, do: for(path <- Path.wildcard(@web), do: {path, File.read!(path)})

  @doc """
  Every submit form and click that reaches handle_event, as a record of its event,
  location, sent fields and the literal `action` and `operation` values it can submit.
  Controls rendered by a function component belong to the forms that call it.
  LiveView's own lv: events are omitted.
  """
  def forms(sources \\ sources()) do
    scanned =
      sources
      |> Enum.flat_map(fn {path, source} -> templates(source, path) end)
      |> Enum.map(fn {component, template, where} ->
        {component, where, template_scan(template, where)}
      end)

    # Same-named components merge their calls; two that render named controls are ambiguous.
    loose =
      Enum.reduce(scanned, %{}, fn {component, where, result}, acc ->
        if result.loose == [],
          do: acc,
          else:
            Map.update(acc, component, {where, result.loose}, fn {other, items} ->
              if controls?(items) and controls?(result.loose),
                do:
                  raise(
                    ArgumentError,
                    "Ambiguous component .#{component} at #{other} and #{where}"
                  )

              {if(controls?(items), do: other, else: where), items ++ result.loose}
            end)
      end)

    records = Enum.flat_map(scanned, fn {_, _, result} -> result.records end)
    called = records |> Enum.flat_map(& &1.calls) |> reachable(loose, MapSet.new())

    for {component, {where, items}} <- loose,
        controls?(items),
        component not in called,
        do:
          raise(
            ArgumentError,
            "Named controls in .#{component} are never inside a submit form (#{where})"
          )

    records
    |> Enum.reject(&String.starts_with?(&1.event, "lv:"))
    |> Enum.map(fn record ->
      record.calls
      |> Enum.flat_map(&component_items(&1, loose, MapSet.new()))
      |> Enum.reduce(Map.delete(record, :calls), &add_item(&2, &1))
    end)
  end

  @doc "Event => MapSet of field names sent by its forms and clicks."
  def sent(sources \\ sources()) do
    Enum.reduce(forms(sources), %{}, fn record, acc ->
      Map.update(acc, record.event, record.fields, &MapSet.union(&1, record.fields))
    end)
  end

  @doc """
  Fields a form sends that its actions do not admit and its handler never reads.

  `run/2` keeps only the fields `CommandPayload` admits for the submitted action, so any
  other field must be converted by the handler (read explicitly) or it is silently lost.
  A field admitted by a sibling action of the same form, such as a second submit button,
  is expected. Command events reach `run/2` or `Game.command/3` through helpers; a command
  form whose action cannot be determined raises.
  """
  def dropped(
        forms \\ forms(),
        handlers \\ File.read!(@handlers),
        admitted \\ &TijaraTides.UseCases.CommandPayload.admitted/1
      ) do
    facts = handler_facts(handlers)

    for record <- forms, fact = facts[record.event], fact.command? do
      actions = MapSet.union(record.actions, fact.actions)

      if MapSet.size(actions) == 0,
        do: raise(ArgumentError, "Cannot determine the command action for #{record.where}")

      admitted =
        for action <- actions,
            operation <- operations(action, record),
            reduce: MapSet.new(["request_id"]) do
          acc ->
            case admitted.(%{
                   "action" => action,
                   "operation" => operation
                 }) do
              nil ->
                raise ArgumentError,
                      "No admission schema for #{action} #{operation} at #{record.where}"

              fields ->
                MapSet.union(acc, MapSet.new(fields))
            end
        end

      for field <- record.fields,
          field not in admitted,
          field not in fact.explicit,
          do: {record.event, record.where, field}
    end
    |> List.flatten()
  end

  defp operations("route", %{operations: operations, where: where}) do
    if MapSet.size(operations) == 0,
      do: raise(ArgumentError, "Route form without a literal operation at #{where}")

    operations
  end

  defp operations(_action, _record), do: [nil]

  defp controls?(items), do: Enum.any?(items, &(not match?({:call, _}, &1)))

  defp reachable([], _loose, seen), do: seen

  defp reachable([component | rest], loose, seen) do
    if component in seen do
      reachable(rest, loose, seen)
    else
      {_where, items} = Map.get(loose, component, {nil, []})
      inner = for {:call, called} <- items, do: called
      reachable(inner ++ rest, loose, MapSet.put(seen, component))
    end
  end

  defp component_items(component, loose, seen) do
    if component in seen, do: raise(ArgumentError, "Recursive component .#{component}")
    {_where, items} = Map.get(loose, component, {nil, []})

    Enum.flat_map(items, fn
      {:call, inner} -> component_items(inner, loose, MapSet.put(seen, component))
      item -> [item]
    end)
  end

  defp add_item(record, {:field, field}), do: %{record | fields: MapSet.put(record.fields, field)}

  defp add_item(record, {:action, value}),
    do: %{record | actions: MapSet.put(record.actions, value)}

  defp add_item(record, {:operation, value}),
    do: %{record | operations: MapSet.put(record.operations, value)}

  defp add_item(record, {:call, component}), do: %{record | calls: [component | record.calls]}

  defp record(event, where, kind, id_prefix),
    do: %{
      event: event,
      where: where,
      kind: kind,
      id_prefix: id_prefix,
      fields: MapSet.new(),
      actions: MapSet.new(),
      operations: MapSet.new(),
      calls: []
    }

  @doc "Event => :all | {:only, MapSet} | {:all_except, MapSet} read by handle_event clauses."
  def read(source \\ File.read!(@handlers)) do
    ast = Code.string_to_quoted!(source)
    locals = local_functions(ast)

    ast
    |> handle_event_clauses()
    |> Enum.reduce(%{}, fn {event, pattern, body}, acc ->
      reads = clause_reads(pattern, body, locals)
      Map.update(acc, event, reads, &merge(&1, reads))
    end)
  end

  @doc "Fields a template sends that no handler clause for that event reads."
  def unread(sent \\ sent(), read \\ read()) do
    for {event, fields} <- sent,
        field <- fields,
        not read?(Map.get(read, event, {:only, MapSet.new()}), field),
        do: {event, field}
  end

  defp read?(:all, _field), do: true
  defp read?({:only, fields}, field), do: field in fields
  defp read?({:all_except, dropped}, field), do: field not in dropped

  # -- templates ------------------------------------------------------------

  # Each ~H template with the name of the function component that renders it.
  defp templates(source, path) do
    {_, found} =
      Macro.prewalk(Code.string_to_quoted!(source), [], fn
        {kind, _, [head, body]} = node, acc when kind in [:def, :defp] ->
          {name, _, _} = strip_guard(head)
          {node, sigils(body, name, path) ++ acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp sigils(body, name, path) do
    {_, found} =
      Macro.prewalk(body, [], fn
        {:sigil_H, meta, [{:<<>>, _, [template]}, _]} = node, acc when is_binary(template) ->
          {node, [{to_string(name), template, "#{path}:#{meta[:line]}"} | acc]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Produces form and click records, plus controls a component renders outside any form.
  defp template_scan(template, where) do
    template
    |> tags()
    |> Enum.reduce({%{records: [], loose: [], bindings: %{}}, :outside}, fn
      {:close, form}, {acc, current} when form in ["form", ".form"] ->
        acc = if is_map(current), do: %{acc | records: [current | acc.records]}, else: acc
        {acc, :outside}

      {:open, form, attrs}, {acc, _} when form in ["form", ".form"] ->
        case literal_event(attrs, "phx-submit", where) do
          # phx-change-only and plain HTTP forms do not reach handle_event on submit.
          nil ->
            {acc, :ignored}

          event ->
            {acc,
             record(event, "#{where} ##{id_label(attrs["id"])}", :form, id_prefix(attrs["id"]))}
        end

      {:open, tag, attrs}, {acc, current} ->
        acc = %{acc | bindings: bind(attrs[":for"], acc.bindings)}
        resolve = &literal_values(&1, acc.bindings, where)
        acc = %{acc | records: clicks(attrs, where, resolve) ++ acc.records}
        items = items(tag, attrs, where, resolve)

        case current do
          :outside -> {%{acc | loose: items ++ acc.loose}, current}
          :ignored -> {acc, current}
          record -> {acc, Enum.reduce(items, record, &add_item(&2, &1))}
        end

      _, state ->
        state
    end)
    |> elem(0)
  end

  # The literal start of a control id: "auction-revise-" for {"auction-revise-" <> a["id"]}.
  defp id_prefix(nil), do: nil
  defp id_prefix(id) when is_binary(id), do: id

  defp id_prefix({:expr, expr}) do
    case Code.string_to_quoted!(expr) do
      literal when is_binary(literal) -> literal
      {:<>, _, [prefix, _]} when is_binary(prefix) -> prefix
      {:<<>>, _, [prefix | _]} when is_binary(prefix) -> prefix
      _ -> nil
    end
  end

  defp id_label({:expr, expr}), do: "{" <> expr <> "}"
  defp id_label(nil), do: "(no id)"
  defp id_label(id), do: id

  # :for={var <- ["a", "b"]} binds var to literals; any other generator is dynamic.
  defp bind({:expr, expr}, bindings) do
    case Code.string_to_quoted!(expr) do
      {:<-, _, [{var, _, context}, list]} when is_atom(var) and is_atom(context) ->
        value = if is_list(list) and Enum.all?(list, &is_binary/1), do: list, else: :dynamic
        Map.put(bindings, Atom.to_string(var), value)

      _ ->
        bindings
    end
  end

  defp bind(_, bindings), do: bindings

  defp items("." <> component, _attrs, _where, _resolve),
    do: [{:call, component |> String.split(".") |> List.last()}]

  defp items(tag, attrs, where, resolve) when tag in @controls do
    case attrs["name"] do
      nil ->
        []

      name ->
        field = field_name(name, where)

        values =
          if field in ["action", "operation"], do: resolve.(attrs["value"]), else: []

        [{:field, field} | Enum.map(values, &{String.to_atom(field), &1})]
    end
  end

  defp items(_tag, _attrs, _where, _resolve), do: []

  # A submitted action or operation must be literal or an expression choosing between literals.
  defp literal_values(value, _bindings, _where) when is_binary(value), do: [value]

  defp literal_values({:expr, expr}, bindings, where) do
    case Code.string_to_quoted!(expr) do
      {var, _, context} when is_atom(var) and is_atom(context) ->
        file = where |> String.split(":") |> hd() |> Path.basename()

        case {Map.get(bindings, Atom.to_string(var)),
              @dynamic_actions[{file, Atom.to_string(var)}]} do
          {values, _} when is_list(values) -> values
          {_, values} when is_list(values) -> values
          _ -> raise ArgumentError, "Declare dynamic action value {#{expr}} at #{where}"
        end

      ast ->
        case results(ast) do
          :unresolved -> raise ArgumentError, "Unresolved action value {#{expr}} at #{where}"
          values -> values
        end
    end
  end

  defp literal_values(_value, _bindings, where),
    do: raise(ArgumentError, "Action control without value at #{where}")

  defp clicks(attrs, where, resolve) do
    case attrs["phx-click"] do
      nil ->
        []

      {:expr, expr} ->
        pushes(expr, where, id_prefix(attrs["id"]))

      event ->
        fields = for {"phx-value-" <> field, _} <- attrs, do: field

        actions =
          case attrs["phx-value-action"] do
            nil -> []
            value -> resolve.(value)
          end

        operations =
          case attrs["phx-value-operation"] do
            nil -> []
            value -> resolve.(value)
          end

        [
          %{
            record(event, "#{where} phx-click=#{event}", :click, id_prefix(attrs["id"]))
            | fields: MapSet.new(fields),
              actions: MapSet.new(actions),
              operations: MapSet.new(operations)
          }
        ]
    end
  end

  # JS.push("event", value: %{key: ...}) sends its literal map keys.
  defp pushes(expr, where, prefix) do
    {_, found} =
      Macro.prewalk(Code.string_to_quoted!(expr), [], fn
        {{:., _, [{:__aliases__, _, [:JS]}, :push]}, _, [event | opts]} = node, acc
        when is_binary(event) ->
          keys =
            case opts do
              [[value: {:%{}, _, pairs}]] -> Enum.map(pairs, &to_string(elem(&1, 0)))
              [] -> []
              _ -> raise ArgumentError, "Unresolved JS.push value at #{where}"
            end

          {node,
           [
             %{
               record(event, "#{where} JS.push(#{event})", :click, prefix)
               | fields: MapSet.new(keys)
             }
             | acc
           ]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp literal_event(attrs, key, where) do
    case attrs[key] do
      nil -> nil
      {:expr, _} -> raise ArgumentError, "Classify dynamic #{key} at #{where}"
      event -> event
    end
  end

  # "markdowns[fresh]" and {"markdowns[#{grade}]"} both send the "markdowns" field.
  defp field_name({:expr, expr}, where) do
    case Code.string_to_quoted!(expr) do
      {:<<>>, _, [prefix | _]} when is_binary(prefix) -> field_name(prefix, where)
      {:<>, _, [prefix, _]} when is_binary(prefix) -> field_name(prefix, where)
      other -> raise ArgumentError, "Unresolved field name #{Macro.to_string(other)} at #{where}"
    end
  end

  defp field_name(name, _where), do: name |> String.split("[", parts: 2) |> hd()

  # A small HEEx tag reader: opening tags with literal or {expression} attributes.
  defp tags(text), do: tags(text, [])
  defp tags("", acc), do: Enum.reverse(acc)
  defp tags("<!--" <> rest, acc), do: rest |> skip_to("-->") |> tags(acc)

  defp tags("{" <> _ = text, acc) do
    {_expr, rest} = braces(text)
    tags(rest, acc)
  end

  defp tags("</" <> rest, acc) do
    [name, rest] = Regex.run(~r/\A([\w.:-]+)[^>]*>(.*)\z/s, rest, capture: :all_but_first)
    tags(rest, [{:close, name} | acc])
  end

  defp tags("<" <> rest, acc) do
    case Regex.run(~r/\A([a-zA-Z.:][\w.:-]*)(.*)\z/s, rest, capture: :all_but_first) do
      [name, rest] ->
        {attrs, rest} = attributes(rest, %{})
        tags(rest, [{:open, name, attrs} | acc])

      nil ->
        tags(rest, acc)
    end
  end

  defp tags(<<_::utf8, rest::binary>>, acc), do: tags(rest, acc)

  defp attributes(text, acc) do
    text = String.trim_leading(text)

    cond do
      String.starts_with?(text, "/>") ->
        {acc, binary_part(text, 2, byte_size(text) - 2)}

      String.starts_with?(text, ">") ->
        {acc, binary_part(text, 1, byte_size(text) - 1)}

      String.starts_with?(text, "{") ->
        {_expr, rest} = braces(text)
        attributes(rest, acc)

      true ->
        [name, rest] = Regex.run(~r/\A([^\s=>\/]+)(.*)\z/s, text, capture: :all_but_first)

        case rest do
          "=\"" <> value ->
            [literal, rest] = String.split(value, "\"", parts: 2)
            attributes(rest, Map.put(acc, name, literal))

          "={" <> _ ->
            {expr, rest} = braces(binary_part(rest, 1, byte_size(rest) - 1))
            attributes(rest, Map.put(acc, name, {:expr, expr}))

          rest ->
            attributes(rest, Map.put(acc, name, true))
        end
    end
  end

  # Returns the inside of a balanced {...} and the text after it, skipping strings.
  defp braces("{" <> rest), do: braces(rest, 1, [])

  defp braces("}" <> rest, 1, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  defp braces("}" <> rest, depth, acc), do: braces(rest, depth - 1, ["}" | acc])
  defp braces("{" <> rest, depth, acc), do: braces(rest, depth + 1, ["{" | acc])

  defp braces("\"" <> rest, depth, acc) do
    {string, rest} = string(rest, ["\""])
    braces(rest, depth, [string | acc])
  end

  defp braces(<<c::utf8, rest::binary>>, depth, acc), do: braces(rest, depth, [<<c::utf8>> | acc])

  defp string("\\" <> <<c::utf8, rest::binary>>, acc), do: string(rest, [<<c::utf8>>, "\\" | acc])

  defp string("\"" <> rest, acc),
    do: {["\"" | acc] |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp string("\#{" <> rest, acc) do
    {inner, rest} = braces("{" <> rest)
    string(rest, ["}", inner, "\#{" | acc])
  end

  defp string(<<c::utf8, rest::binary>>, acc), do: string(rest, [<<c::utf8>> | acc])

  defp skip_to(text, marker), do: text |> String.split(marker, parts: 2) |> List.last()

  # -- handlers -------------------------------------------------------------

  @doc "Event => fields its handler reads by value (conversions) and actions it sets itself."
  def handler_facts(source \\ File.read!(@handlers)) do
    ast = Code.string_to_quoted!(source)
    locals = local_functions(ast)

    ast
    |> handle_event_clauses()
    |> Enum.reduce(%{}, fn {event, pattern, body}, acc ->
      {keys, variable} = pattern_keys(pattern)

      explicit =
        if variable, do: explicit_reads(variable, body, locals, MapSet.new()), else: MapSet.new()

      {command?, actions} = command_facts(body, locals, MapSet.new())

      fact = %{
        explicit: MapSet.union(keys, explicit),
        actions: actions,
        command?: command?
      }

      Map.update(acc, event, fact, fn other ->
        %{
          explicit: MapSet.union(other.explicit, fact.explicit),
          actions: MapSet.union(other.actions, fact.actions),
          command?: other.command? or fact.command?
        }
      end)
    end)
  end

  # Follow local helpers to both submission paths, retaining every fixed action.
  defp command_facts(body, locals, visited) do
    {_, facts} =
      body
      |> unpipe()
      |> Macro.prewalk({false, fixed_actions(body)}, fn
        {:run, _, [_, _]} = node, {_, actions} ->
          {node, {true, actions}}

        {{:., _, [{:__aliases__, _, module}, :command]}, _, [_, _, _]} = node,
        {command?, actions} ->
          {node, {command? or module in [[:Game], [:TijaraTides, :UseCases, :Game]], actions}}

        {fun, _, args} = node, {command?, actions} when is_atom(fun) and is_list(args) ->
          # A delegated event follows only its clauses; other helpers follow every clause.
          key =
            case {fun, args} do
              {:handle_event, [event | _]} when is_binary(event) -> {fun, length(args), event}
              _ -> {fun, length(args)}
            end

          clauses =
            case key do
              {:handle_event, arity, event} ->
                for {[^event | _], _} = clause <- Map.get(locals, {:handle_event, arity}, []),
                    do: clause

              _ ->
                Map.get(locals, key, [])
            end

          facts =
            if key in visited do
              {command?, actions}
            else
              Enum.reduce(clauses, {command?, actions}, fn {_, inner}, {found?, fixed} ->
                {inner?, inner_actions} = command_facts(inner, locals, MapSet.put(visited, key))
                {found? or inner?, MapSet.union(fixed, inner_actions)}
              end)
            end

          {node, facts}

        node, acc ->
          {node, acc}
      end)

    facts
  end

  # Value reads only; forwarding the whole map is not a read of any particular field.
  defp explicit_reads(name, body, locals, visited) do
    {_, keys} =
      body
      |> unpipe()
      |> Macro.prewalk(MapSet.new(), fn node, acc ->
        case value_read(node, name, locals, visited) do
          {:read, keys} -> {node, MapSet.union(acc, keys)}
          :none -> {node, acc}
        end
      end)

    keys
  end

  defp value_read({{:., _, [Access, :get]}, _, [var, key]}, name, _, _) when is_binary(key),
    do: if(variable?(var, name), do: {:read, MapSet.new([key])}, else: :none)

  defp value_read({{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, [var, key | _]}, name, _, _)
       when fun in [:get, :fetch, :fetch!, :has_key?, :pop, :pop!] and is_binary(key),
       do: if(variable?(var, name), do: {:read, MapSet.new([key])}, else: :none)

  defp value_read({fun, _, args}, name, locals, visited) when is_atom(fun) and is_list(args) do
    key = {fun, length(args)}

    case Enum.find_index(args, &variable?(&1, name)) do
      index when is_integer(index) and is_map_key(locals, key) ->
        if key in visited do
          :none
        else
          {:read,
           locals[key]
           |> Enum.flat_map(fn {params, body} ->
             {keys, variable} = pattern_keys(Enum.at(params, index))

             inner =
               if variable,
                 do: explicit_reads(variable, body, locals, MapSet.put(visited, key)),
                 else: MapSet.new()

             MapSet.to_list(MapSet.union(keys, inner))
           end)
           |> MapSet.new()}
        end

      _ ->
        :none
    end
  end

  defp value_read(_, _, _, _), do: :none

  # Literal actions a handler assigns: Map.put(_, "action", "x") or %{"action" => "x"}.
  defp fixed_actions(body) do
    {_, actions} =
      body
      |> unpipe()
      |> Macro.prewalk(MapSet.new(), fn
        {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _, [_, "action", action]} = node, acc ->
          {node, MapSet.union(acc, strings(action))}

        {:%{}, _, pairs} = node, acc ->
          case List.keyfind(pairs, "action", 0) do
            {"action", action} -> {node, MapSet.union(acc, strings(action))}
            nil -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    actions
  end

  # Literals an action expression can evaluate to, e.g. if(sailing, do: "reroute", else: "sail").
  # Conditions are not results; any other expression shape is unresolved.
  defp strings(expression) do
    case results(expression) do
      :unresolved ->
        raise ArgumentError, "Unresolved action expression #{Macro.to_string(expression)}"

      values ->
        MapSet.new(values)
    end
  end

  defp results(value) when is_binary(value), do: [value]

  defp results({kind, _, [_condition, branches]})
       when kind in [:if, :unless] and is_list(branches),
       do: combine([results(branches[:do]), results(branches[:else])])

  defp results({:case, _, [_subject, [do: clauses]]}),
    do: combine(for {:->, _, [_pattern, body]} <- clauses, do: results(body))

  defp results({:__block__, _, expressions}), do: results(List.last(expressions))
  defp results(_), do: :unresolved

  defp combine(results),
    do: if(:unresolved in results, do: :unresolved, else: Enum.concat(results))

  defp handle_event_clauses(ast) do
    {_, clauses} =
      Macro.prewalk(ast, [], fn
        {:def, _, [head, body]} = node, acc ->
          case strip_guard(head) do
            {:handle_event, _, [event, pattern, _socket]} when is_binary(event) ->
              {node, [{event, pattern, body} | acc]}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    clauses
  end

  defp local_functions(ast) do
    {_, functions} =
      Macro.prewalk(ast, %{}, fn
        {kind, _, [head, body]} = node, acc when kind in [:def, :defp] ->
          case strip_guard(head) do
            {name, _, args} when is_atom(name) and is_list(args) ->
              {node, Map.update(acc, {name, length(args)}, [{args, body}], &[{args, body} | &1])}

            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    functions
  end

  defp strip_guard({:when, _, [head | _]}), do: head
  defp strip_guard(head), do: head

  defp clause_reads(pattern, body, locals) do
    {keys, variable} = pattern_keys(pattern)

    case variable do
      nil -> {:only, keys}
      name -> merge({:only, keys}, variable_reads(name, body, locals, MapSet.new()))
    end
  end

  defp pattern_keys({:=, _, [left, right]}) do
    {lk, lv} = pattern_keys(left)
    {rk, rv} = pattern_keys(right)
    {MapSet.union(lk, rk), lv || rv}
  end

  defp pattern_keys({:%{}, _, pairs}),
    do: {pairs |> Enum.map(&elem(&1, 0)) |> Enum.filter(&is_binary/1) |> MapSet.new(), nil}

  defp pattern_keys({name, _, context}) when is_atom(name) and is_atom(context) do
    if String.starts_with?(Atom.to_string(name), "_"),
      do: {MapSet.new(), nil},
      else: {MapSet.new(), name}
  end

  defp pattern_keys(_), do: {MapSet.new(), nil}

  # Walks a body for accessor uses of `name`; any other use forwards every field.
  defp variable_reads(name, body, locals, visited) do
    {_, result} =
      body
      |> unpipe()
      |> Macro.prewalk({:only, MapSet.new()}, fn node, acc ->
        case access(node, name, locals, visited) do
          {:read, reads} -> {:ok, merge(acc, reads)}
          :none -> {node, if(variable?(node, name), do: merge(acc, :all), else: acc)}
        end
      end)

    result
  end

  defp access({{:., _, [Access, :get]}, _, [var, key]}, name, _, _) when is_binary(key),
    do: if(variable?(var, name), do: {:read, {:only, MapSet.new([key])}}, else: :none)

  defp access({{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, [var, key | _]}, name, _, _)
       when fun in [:get, :fetch, :fetch!, :has_key?] and is_binary(key),
       do: if(variable?(var, name), do: {:read, {:only, MapSet.new([key])}}, else: :none)

  defp access({{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, [var, keys]}, name, _, _)
       when fun in [:take, :drop] do
    with true <- variable?(var, name), {:ok, keys} <- literal_keys(keys) do
      {:read, if(fun == :take, do: {:only, keys}, else: {:all_except, keys})}
    else
      _ -> :none
    end
  end

  # A local function receiving the params in one position reads what that clause reads.
  defp access({fun, _, args}, name, locals, visited) when is_atom(fun) and is_list(args) do
    positions = for {arg, index} <- Enum.with_index(args), variable?(arg, name), do: index
    key = {fun, length(args)}

    cond do
      positions == [] or not Map.has_key?(locals, key) ->
        :none

      length(positions) > 1 or key in visited ->
        {:read, :all}

      true ->
        [index] = positions

        reads =
          locals[key]
          |> Enum.map(fn {params, body} ->
            {keys, variable} = pattern_keys(Enum.at(params, index))

            inner =
              if variable, do: variable_reads(variable, body, locals, MapSet.put(visited, key))

            merge({:only, keys}, inner || {:only, MapSet.new()})
          end)
          |> Enum.reduce(&merge/2)

        {:read, merge(reads, variable_reads(name, List.delete_at(args, index), locals, visited))}
    end
  end

  defp access(_, _, _, _), do: :none

  defp literal_keys(keys) when is_list(keys),
    do: if(Enum.all?(keys, &is_binary/1), do: {:ok, MapSet.new(keys)}, else: :error)

  defp literal_keys({:sigil_w, _, [{:<<>>, _, [words]}, _]}),
    do: {:ok, MapSet.new(String.split(words))}

  defp literal_keys(_), do: :error

  defp variable?({name, _, context}, name) when is_atom(context), do: true
  defp variable?(_, _), do: false

  defp unpipe(ast) do
    Macro.prewalk(ast, fn
      {:|>, _, [left, {fun, meta, args}]} when is_list(args) -> unpipe({fun, meta, [left | args]})
      {:|>, _, [left, {fun, meta, nil}]} -> {fun, meta, [left]}
      node -> node
    end)
  end

  defp merge(:all, _), do: :all
  defp merge(_, :all), do: :all
  defp merge({:only, a}, {:only, b}), do: {:only, MapSet.union(a, b)}

  defp merge({:only, read}, {:all_except, dropped}),
    do: {:all_except, MapSet.difference(dropped, read)}

  defp merge({:all_except, dropped}, {:only, read}),
    do: {:all_except, MapSet.difference(dropped, read)}

  defp merge({:all_except, a}, {:all_except, b}), do: {:all_except, MapSet.intersection(a, b)}
end
