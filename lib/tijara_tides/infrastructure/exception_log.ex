defmodule TijaraTides.Infrastructure.ExceptionLog do
  @moduledoc "Exception diagnostics with messages, credential redaction, and argument-free stack traces."
  require Logger

  def error(context, exception, stacktrace) do
    Logger.error(format(context, exception, stacktrace))
  end

  def format(context, exception, stacktrace) do
    frames =
      Enum.map(stacktrace, fn
        {module, function, args, location} when is_list(args) ->
          {module, function, length(args), location}

        frame ->
          frame
      end)

    "#{context}: #{inspect(exception.__struct__)}: #{message(exception)}\n" <>
      Exception.format_stacktrace(frames)
  end

  # Postgrex appends the failing row's values as an unlabelled trailing paragraph and the
  # statement after "query:", so rebuild the message from the fields that name only schema.
  defp database(%{postgres: postgres}) do
    IO.iodata_to_binary([
      "#{postgres.severity} #{postgres.pg_code} (#{postgres.code}) #{postgres.message}",
      for(
        key <- [:table, :column, :constraint],
        value = postgres[key],
        do: "\n    #{key}: #{value}"
      ),
      if(postgres[:detail], do: "\n    detail: [REDACTED DATABASE DATA]", else: [])
    ])
  end

  defp message(exception) do
    message = Exception.message(exception)

    # These exception messages inspect arbitrary application values, which can be credentials.
    message =
      case exception do
        %CaseClauseError{} -> "no case clause matching: [REDACTED]"
        %MatchError{} -> "no match of right hand side value: [REDACTED]"
        %FunctionClauseError{} -> "no function clause matching; arguments [REDACTED]"
        %KeyError{key: key} -> "key #{inspect(key)} not found; value [REDACTED]"
        %BadMapError{} -> "expected a map, got: [REDACTED]"
        error when is_struct(error, Postgrex.Error) and is_map(error.postgres) -> database(error)
        _ -> message
      end

    message
    |> String.replace(~r{(\w+://)[^\s/@]+:[^\s/@]+@}, "\\1[REDACTED]@")
    |> String.replace(~r/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, "[REDACTED EMAIL]")
    |> String.replace(
      ~r/((?:password|secret|token|code|api[_-]?key|authorization)["\']?\s*(?:=>|[=:])\s*)(?:"[^"]*"|'[^']*'|[^\s,;}]+)/i,
      "\\1[REDACTED]"
    )
    |> String.replace(~r/\bBearer\s+\S+/i, "Bearer [REDACTED]")
    |> String.replace(~r/\b[A-Za-z0-9_-]{43,}\b/, "[REDACTED TOKEN]")
    |> String.replace(
      ~r/\b(?:DETAIL|QUERY|PARAMETERS):[^\n]*(?:\n(?![A-Z]+:)[^\n]*)*/i,
      "[REDACTED DATABASE DATA]"
    )
  end
end
