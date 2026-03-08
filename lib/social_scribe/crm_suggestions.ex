defmodule SocialScribe.CrmSuggestions do
  @moduledoc """
  Generates and formats CRM contact update suggestions by combining
  AI-extracted data with existing contact information.

  Works with any CRM provider (HubSpot, Salesforce, etc.) using
  canonical field names defined in CrmApiBehaviour.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.CrmApi
  alias SocialScribe.CrmApiBehaviour
  alias SocialScribe.Accounts.UserCredential

  @doc """
  Generates suggested updates for a CRM contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the canonical field name
  - label: human-readable field label
  - current_value: the existing value in CRM (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default false)
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    with {:ok, contact} <- CrmApi.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
      suggestions =
        ai_suggestions
        |> Enum.map(fn s ->
          current_value = get_contact_field(contact, s.field)
          map_ai_suggestion_to_suggestion(s, current_value)
        end)
        |> Enum.filter(& &1.has_change)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  @doc """
  Generates suggestions without fetching contact data.
  Useful when contact hasn't been selected yet.
  """
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(&map_ai_suggestion_from_meeting/1)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)
      has_change = current_value != suggestion.new_value

      %{suggestion | current_value: current_value, has_change: has_change, apply: true}
    end)
    |> Enum.filter(& &1.has_change)
  end

  defp map_ai_suggestion_to_suggestion(suggestion, current_value) do
    %{
      field: suggestion.field,
      label: label_for(suggestion.field),
      current_value: current_value,
      new_value: suggestion.value,
      context: suggestion.context,
      apply: true,
      has_change: current_value != suggestion.value
    }
  end

  defp map_ai_suggestion_from_meeting(suggestion) do
    %{
      field: suggestion.field,
      label: label_for(suggestion.field),
      current_value: nil,
      new_value: suggestion.value,
      context: Map.get(suggestion, :context),
      timestamp: Map.get(suggestion, :timestamp),
      apply: true,
      has_change: true
    }
  end

  defp label_for(field), do: Map.get(CrmApiBehaviour.field_labels(), field, field)

  defp get_contact_field(contact, field) when is_map(contact) do
    field_atom = String.to_existing_atom(field)
    Map.get(contact, field_atom)
  rescue
    ArgumentError -> nil
  end

  defp get_contact_field(_, _), do: nil
end
