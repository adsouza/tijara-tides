defmodule TijaraTides.FormFields do
  @moduledoc """
  Static field inventory: what each template sends to an event, and what its handler reads.

  Templates are read from `~H` sigils. A field is sent by a named `input`, `select`,
  `textarea` or `button` inside `<form phx-submit="event">`, or by `phx-value-*`
  and `JS.push(..., value: %{...})` on a `phx-click="event"` element. A handler reads
  a field through its head pattern, `params["field"]`, `Map.get/2,3`, `Map.take/2`,
  or a local function receiving `params`. Passing `params` anywhere else forwards
  every field except literal `Map.drop/2` keys. Unresolvable names raise.
  """

  use Boundary

  @web "lib/tijara_tides_web/**/*.ex"
  @handlers "lib/tijara_tides_web/live/game_live.ex"
  @controls ~w(input select textarea button)

  @doc "Every web source as {path, contents}."
  def sources, do: for(path <- Path.wildcard(@web), do: {path, File.read!(path)})

  @doc "Event => MapSet of field names sent by templates. LiveView's own lv: events are omitted."
  def sent(sources \\ sources()) do
    scanned =
      sources
      |> Enum.flat_map(fn {path, source} -> templates(source, path) end)
      |> Enum.map(fn {component, template, where} ->
        {component, where, template_fields(template, where)}
      end)

    # Named controls outside a form belong to the submit forms that call their component.
    loose =
      Enum.reduce(scanned, %{}, fn {component, where, result}, acc ->
        if result.loose == [],
          do: acc,
          else:
            Map.update(acc, component, {where, result.loose}, fn {other, _} ->
              raise ArgumentError, "Ambiguous component .#{component} at #{other} and #{where}"
            end)
      end)

    calls = Enum.flat_map(scanned, fn {_, _, result} -> result.calls end)

    for {component, {where, _}} <- loose,
        not Enum.any?(calls, &(elem(&1, 1) == component)),
        do:
          raise(
            ArgumentError,
            "Named controls in .#{component} are never inside a submit form (#{where})"
          )

    nested =
      for {event, component} <- calls,
          {_where, fields} <- [Map.get(loose, component, {nil, []})],
          field <- component_fields(component, fields, loose, MapSet.new()),
          do: {event, field}

    (Enum.flat_map(scanned, fn {_, _, result} -> result.fields end) ++ nested)
    |> Enum.reject(fn {event, _} -> String.starts_with?(event, "lv:") end)
    |> Enum.reduce(%{}, fn {event, field}, acc ->
      Map.update(acc, event, MapSet.new([field]), &MapSet.put(&1, field))
    end)
  end

  defp component_fields(component, fields, loose, seen) do
    if component in seen, do: raise(ArgumentError, "Recursive component .#{component}")

    Enum.flat_map(fields, fn
      {:call, inner} ->
        {_where, inner_fields} = Map.get(loose, inner, {nil, []})
        component_fields(inner, inner_fields, loose, MapSet.put(seen, component))

      field ->
        [field]
    end)
  end

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

  defp template_fields(template, where) do
    template
    |> tags()
    |> Enum.reduce({%{fields: [], loose: [], calls: []}, :outside}, fn
      {:close, form}, {acc, _} when form in ["form", ".form"] ->
        {acc, :outside}

      {:open, form, attrs}, {acc, _} when form in ["form", ".form"] ->
        {acc, {:form, literal_event(attrs, "phx-submit", where)}}

      {:open, "." <> component, attrs}, {acc, form} ->
        component = component |> String.split(".") |> List.last()

        acc =
          case form do
            {:form, nil} -> acc
            {:form, event} -> %{acc | calls: [{event, component} | acc.calls]}
            :outside -> %{acc | loose: [{:call, component} | acc.loose]}
          end

        {%{acc | fields: click_fields(attrs, where) ++ acc.fields}, form}

      {:open, tag, attrs}, {acc, form} ->
        acc = %{acc | fields: click_fields(attrs, where) ++ acc.fields}

        acc =
          case control_fields(tag, attrs, form, where) do
            {:loose, field} -> %{acc | loose: [field | acc.loose]}
            fields -> %{acc | fields: fields ++ acc.fields}
          end

        {acc, form}

      _, state ->
        state
    end)
    |> elem(0)
    |> Map.update!(:loose, fn loose ->
      if Enum.all?(loose, &match?({:call, _}, &1)), do: [], else: loose
    end)
  end

  defp control_fields(tag, attrs, form, where) when tag in @controls do
    case {form, attrs["name"]} do
      {_, nil} -> []
      {:outside, name} -> {:loose, field_name(name, where)}
      # phx-change-only and plain HTTP forms do not reach handle_event on submit.
      {{:form, nil}, _} -> []
      {{:form, event}, name} -> [{event, field_name(name, where)}]
    end
  end

  defp control_fields(_tag, _attrs, _form, _where), do: []

  defp click_fields(attrs, where) do
    case attrs["phx-click"] do
      nil ->
        []

      {:expr, expr} ->
        pushes(expr, where)

      event ->
        for {"phx-value-" <> field, _} <- attrs, do: {event, field}
    end
  end

  # JS.push("event", value: %{key: ...}) sends its literal map keys.
  defp pushes(expr, where) do
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

          {node, Enum.map(keys, &{event, &1}) ++ acc}

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
