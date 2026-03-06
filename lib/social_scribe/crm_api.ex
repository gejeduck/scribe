defmodule SocialScribe.CrmApi do
  @moduledoc """
  Unified CRM API that delegates to provider-specific implementations.

  Use this module instead of calling HubspotApi (or other provider APIs)
  directly. It resolves the correct implementation from the credential's
  provider and delegates the call.
  """

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.CrmProvider

  def search_contacts(%UserCredential{provider: provider} = credential, query)
      when is_binary(query) do
    with {:ok, impl} <- resolve_impl(provider) do
      impl.search_contacts(credential, query)
    end
  end

  def get_contact(%UserCredential{provider: provider} = credential, contact_id) do
    with {:ok, impl} <- resolve_impl(provider) do
      impl.get_contact(credential, contact_id)
    end
  end

  def update_contact(%UserCredential{provider: provider} = credential, contact_id, updates)
      when is_map(updates) do
    with {:ok, impl} <- resolve_impl(provider) do
      impl.update_contact(credential, contact_id, updates)
    end
  end

  def apply_updates(%UserCredential{provider: provider} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    with {:ok, impl} <- resolve_impl(provider) do
      impl.apply_updates(credential, contact_id, updates_list)
    end
  end

  defp resolve_impl(provider) do
    case CrmProvider.impl_for(provider) do
      nil -> {:error, {:unsupported_crm_provider, provider}}
      impl -> {:ok, impl}
    end
  end
end
