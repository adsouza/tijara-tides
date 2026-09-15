defmodule TijaraTides.Domain.Account.EmailIdentity do
  @moduledoc "Email address normalization independent of identity storage."
  def normalize(value) when is_binary(value) do
    email = if String.valid?(value), do: value |> String.trim() |> String.downcase(), else: ""

    if byte_size(email) <= 254 and Regex.match?(~r/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/, email),
      do: {:ok, email},
      else: {:error, :email_invalid}
  end

  def normalize(_), do: {:error, :email_invalid}
end
