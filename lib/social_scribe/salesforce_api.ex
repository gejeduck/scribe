defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements CrmApiBehaviour for multi-provider CRM support.
  Uses instance_url from the credential for API requests.
  """

  @behaviour SocialScribe.CrmApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @api_version "v59.0"

  @contact_fields ~w(
    Id FirstName LastName Email Phone MobilePhone Title
    MailingStreet MailingCity MailingState MailingPostalCode MailingCountry
  ) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp base_url(%UserCredential{instance_url: nil}), do: nil
  defp base_url(%UserCredential{instance_url: url}) when is_binary(url) do
    "#{String.trim_trailing(url, "/")}/services/data/#{@api_version}"
  end

  defp client(access_token, base) when is_binary(base) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, base},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string using Salesforce parameterized search.
  Returns up to 10 matching contacts.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      base = base_url(cred)
      if is_nil(base) do
        {:error, :missing_instance_url}
      else
        fields = Enum.join(@contact_fields, ",")
        params = [
          {"q", query},
          {"sobject", "Contact"},
          {"Contact.fields", fields},
          {"Contact.limit", "10"}
        ]
        qs = URI.encode_query(params)

        case Tesla.get(client(cred.token, base), "/parameterizedSearch/?#{qs}") do
          {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => records}}} ->
            contacts = Enum.map(records, &format_contact/1)
            {:ok, contacts}

          {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => nil}}} ->
            {:ok, []}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end
    end)
  end

  @doc """
  Gets a single contact by ID.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      base = base_url(cred)
      if is_nil(base) do
        {:error, :missing_instance_url}
      else
        fields = Enum.join(@contact_fields, ",")
        url = "/sobjects/Contact/#{contact_id}?fields=#{URI.encode_www_form(fields)}"

        case Tesla.get(client(cred.token, base), url) do
          {:ok, %Tesla.Env{status: 200, body: body}} ->
            {:ok, format_contact(body)}

          {:ok, %Tesla.Env{status: 404, body: _body}} ->
            {:error, :not_found}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      base = base_url(cred)
      if is_nil(base) do
        {:error, :missing_instance_url}
      else
        body = canonical_to_salesforce_fields(updates)

        case Tesla.patch(client(cred.token, base), "/sobjects/Contact/#{contact_id}", body) do
          {:ok, %Tesla.Env{status: status}} when status in [200, 204] ->
            get_contact(cred, contact_id)

          {:ok, %Tesla.Env{status: 404, body: _body}} ->
            {:error, :not_found}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  defp canonical_to_salesforce_fields(updates) when is_map(updates) do
    mapping = %{
      "firstname" => "FirstName",
      "lastname" => "LastName",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "MobilePhone",
      "jobtitle" => "Title",
      "address" => "MailingStreet",
      "city" => "MailingCity",
      "state" => "MailingState",
      "zip" => "MailingPostalCode",
      "country" => "MailingCountry",
      "website" => "Website"
    }

    Enum.reduce(updates, %{}, fn
      {k, v}, acc when is_atom(k) ->
        key = to_string(k)
        put_if_mapped(acc, mapping, key, v)

      {k, v}, acc when is_binary(k) ->
        put_if_mapped(acc, mapping, k, v)
    end)
  end

  defp put_if_mapped(acc, mapping, key, value) do
    case Map.get(mapping, key) do
      nil ->
        acc

      "MailingCountry" ->
        case normalize_country_for_salesforce(value) do
          nil -> acc
          normalized -> Map.put(acc, "MailingCountry", normalized)
        end

      sf_field ->
        Map.put(acc, sf_field, value)
    end
  end

  # Normalizes country values to Salesforce's standard picklist format.
  # Skips values that can't be confidently mapped to avoid FIELD_INTEGRITY_EXCEPTION.
  defp normalize_country_for_salesforce(nil), do: nil
  defp normalize_country_for_salesforce(""), do: nil

  defp normalize_country_for_salesforce(value) when is_binary(value) do
    normalized = String.trim(value) |> String.downcase()

    # Common variations -> standard Salesforce country names
    country_map = %{
      "usa" => "United States",
      "u.s.a." => "United States",
      "u.s.a" => "United States",
      "us" => "United States",
      "u.s." => "United States",
      "united states of america" => "United States",
      "united states" => "United States",
      "uk" => "United Kingdom",
      "u.k." => "United Kingdom",
      "united kingdom" => "United Kingdom",
      "great britain" => "United Kingdom",
      "britain" => "United Kingdom",
      "canada" => "Canada",
      "ca" => "Canada",
      "australia" => "Australia",
      "au" => "Australia",
      "germany" => "Germany",
      "de" => "Germany",
      "france" => "France",
      "fr" => "France",
      "india" => "India",
      "in" => "India",
      "china" => "China",
      "cn" => "China",
      "japan" => "Japan",
      "jp" => "Japan",
      "mexico" => "Mexico",
      "mx" => "Mexico",
      "brazil" => "Brazil",
      "br" => "Brazil",
      "ireland" => "Ireland",
      "ie" => "Ireland",
      "italy" => "Italy",
      "it" => "Italy",
      "spain" => "Spain",
      "es" => "Spain",
      "netherlands" => "Netherlands",
      "nl" => "Netherlands",
      "singapore" => "Singapore",
      "sg" => "Singapore",
      "south korea" => "South Korea",
      "korea" => "South Korea",
      "kr" => "South Korea"
    }

    case Map.get(country_map, normalized) do
      nil ->
        # Extract country from "City, Country" or "City. Country" patterns (e.g. "San Francisco. USA")
        extracted =
          normalized
          |> String.split(~r/[,.]/, parts: 2)
          |> List.last()
          |> case do
            nil -> nil
            part -> String.trim(part) |> String.downcase()
          end

        if extracted && extracted != normalized do
          Map.get(country_map, extracted)
        else
          # Unknown value - skip to avoid FIELD_INTEGRITY_EXCEPTION
          nil
        end

      mapped ->
        mapped
    end
  end

  defp normalize_country_for_salesforce(_), do: nil

  defp format_contact(%{"Id" => id} = record) do
    %{
      id: id,
      firstname: record["FirstName"],
      lastname: record["LastName"],
      email: record["Email"],
      phone: record["Phone"],
      mobilephone: record["MobilePhone"],
      company: nil,
      jobtitle: record["Title"],
      address: record["MailingStreet"],
      city: record["MailingCity"],
      state: record["MailingState"],
      zip: record["MailingPostalCode"],
      country: record["MailingCountry"],
      website: nil,
      linkedin_url: nil,
      twitter_handle: nil,
      display_name: format_display_name(record)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(record) do
    firstname = record["FirstName"] || ""
    lastname = record["LastName"] || ""
    email = record["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, status, body}} when status in [401, 403] ->
          if is_token_error?(body) do
            Logger.info("Salesforce token expired, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(%{"error" => "invalid_grant"}), do: true
  defp is_token_error?(%{"error" => "invalid_token"}), do: true
  defp is_token_error?(%{"message" => msg}) when is_binary(msg) do
    String.contains?(String.downcase(msg), ["token", "expired", "unauthorized", "session"])
  end
  defp is_token_error?(_), do: false
end
