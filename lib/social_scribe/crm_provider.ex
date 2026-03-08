defmodule SocialScribe.CrmProvider do
  @moduledoc """
  Registry for CRM provider implementations.

  Maps provider identifiers (e.g. "hubspot") to implementation modules and
  display labels. Add new CRM providers by extending the @providers map.
  """

  @providers %{
    "hubspot" => %{
      module: SocialScribe.HubspotApi,
      label: "HubSpot"
    },
    "salesforce" => %{
      module: SocialScribe.SalesforceApi,
      label: "Salesforce"
    }
  }

  @doc """
  Returns the implementation module for a given provider.
  In test, Application config :crm_provider_overrides can override implementations.
  """
  def impl_for(provider) when is_binary(provider) do
    overrides = Application.get_env(:social_scribe, :crm_provider_overrides, %{})

    case Map.get(overrides, provider) do
      nil ->
        case Map.get(@providers, provider) do
          %{module: module} when not is_nil(module) -> module
          _ -> nil
        end

      override_module ->
        override_module
    end
  end

  @doc """
  Returns the display label for a provider (e.g. "HubSpot").
  """
  def label_for(provider) when is_binary(provider) do
    case Map.get(@providers, provider) do
      %{label: label} -> label
      nil -> provider
    end
  end

  @doc """
  Returns the list of known CRM provider identifiers.
  """
  def known_providers do
    Map.keys(@providers)
  end

  @doc """
  Checks if a provider is a known CRM provider.
  """
  def crm_provider?(provider) when is_binary(provider) do
    Map.has_key?(@providers, provider)
  end

  def crm_provider?(_), do: false
end
