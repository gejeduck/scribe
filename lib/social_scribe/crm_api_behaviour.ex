defmodule SocialScribe.CrmApiBehaviour do
  @moduledoc """
  Behaviour for CRM provider integrations.

  Implement this behaviour to add support for a new CRM (HubSpot, Salesforce,
  Pipedrive, etc.). Each implementation handles provider-specific API calls
  and returns contacts in a normalized format.
  """

  alias SocialScribe.Accounts.UserCredential

  @doc """
  Searches for contacts by query string.
  Returns up to 10 matching contacts with basic properties.
  """
  @callback search_contacts(credential :: UserCredential.t(), query :: String.t()) ::
              {:ok, list(map())} | {:error, any()}

  @doc """
  Gets a single contact by ID with all properties.
  """
  @callback get_contact(credential :: UserCredential.t(), contact_id :: String.t()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Updates a contact's properties.
  `updates` should be a map of canonical field names to new values.
  """
  @callback update_contact(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates :: map()
            ) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Batch updates multiple properties on a contact.
  """
  @callback apply_updates(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates_list :: list(map())
            ) ::
              {:ok, map() | :no_updates} | {:error, any()}

  @doc """
  Canonical contact field names used across all CRM providers.
  Implementations map these to provider-specific field names.
  """
  def canonical_fields do
    [
      "firstname",
      "lastname",
      "email",
      "phone",
      "mobilephone",
      "company",
      "jobtitle",
      "address",
      "city",
      "state",
      "zip",
      "country",
      "website",
      "linkedin_url",
      "twitter_handle"
    ]
  end

  @doc """
  Human-readable labels for canonical CRM fields.
  Used when displaying suggestions in the UI.
  """
  def field_labels do
    %{
      "firstname" => "First Name",
      "lastname" => "Last Name",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "Mobile Phone",
      "company" => "Company",
      "jobtitle" => "Job Title",
      "address" => "Address",
      "city" => "City",
      "state" => "State",
      "zip" => "ZIP Code",
      "country" => "Country",
      "website" => "Website",
      "linkedin_url" => "LinkedIn",
      "twitter_handle" => "Twitter"
    }
  end
end
