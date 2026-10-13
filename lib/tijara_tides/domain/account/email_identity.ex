defmodule TijaraTides.Domain.Account.EmailIdentity do
  @moduledoc "Email address normalization independent of identity storage."
  def normalize(value) when is_binary(value) do
    email = if String.valid?(value), do: value |> String.trim() |> String.downcase(), else: ""

    # Stored addresses must equal PostgreSQL lower(). Assigned letters lowercase the
    # same way in both, but a C library may map an unassigned code point, so refuse
    # those (\p{Cn}) along with anything text cannot store.
    if byte_size(email) <= 254 and TijaraTides.Domain.ClientText.storable?(email) and
         not Regex.match?(~r/\p{Cn}/u, email) and
         Regex.match?(~r/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/, email),
       do: {:ok, email},
       else: {:error, :email_invalid}
  end

  def normalize(_), do: {:error, :email_invalid}
end
