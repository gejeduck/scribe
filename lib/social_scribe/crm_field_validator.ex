defmodule SocialScribe.CrmFieldValidator do
  @moduledoc """
  Validates CRM contact field values before applying updates.

  Ensures email, phone, and mobile phone fields meet format requirements
  to prevent invalid data from being sent to CRM providers.
  """

  @phone_fields ["phone", "mobilephone"]

  @doc """
  Validates a map of field updates.

  Returns `:ok` if all values are valid, or `{:error, field_errors}` where
  `field_errors` is a map of field name => error message.
  """
  def validate(updates) when is_map(updates) do
    field_errors =
      updates
      |> Enum.reduce(%{}, &validate_field/2)

    if map_size(field_errors) > 0 do
      {:error, field_errors}
    else
      :ok
    end
  end

  defp validate_field({"email", value}, acc) do
    if valid_email?(value), do: acc, else: Map.put(acc, "email", "Invalid email address")
  end

  defp validate_field({field, value}, acc) when field in @phone_fields do
    if valid_phone?(value), do: acc, else: Map.put(acc, field, "Invalid phone number")
  end

  defp validate_field({_field, _value}, acc), do: acc

  defp valid_email?(""), do: true
  defp valid_email?(nil), do: true

  defp valid_email?(value) when is_binary(value) do
    value = String.trim(value)
    value =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  end

  defp valid_phone?(""), do: true
  defp valid_phone?(nil), do: true

  defp valid_phone?(value) when is_binary(value) do
    value = String.trim(value)
    digit_count = value |> String.replace(~r/\D/, "") |> String.length()
    digit_count >= 5 and not String.contains?(String.downcase(value), " at ")
  end
end
