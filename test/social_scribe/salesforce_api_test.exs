defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.CrmApi
  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  @instance_url "https://test.salesforce.com"

  setup do
    Tesla.Mock.mock(fn
      %{method: :get, url: url} ->
        cond do
          String.contains?(url, "parameterizedSearch") ->
            %Tesla.Env{
              status: 200,
              body: %{
                "searchRecords" => [
                  %{
                    "Id" => "003xx000001",
                    "FirstName" => "Jane",
                    "LastName" => "Doe",
                    "Email" => "jane@example.com",
                    "Phone" => "555-0100",
                    "Title" => "Engineer"
                  }
                ]
              }
            }

          String.contains?(url, "sobjects/Contact/") and not String.contains?(url, "parameterizedSearch") ->
            contact_id = url |> String.split("/") |> List.last() |> String.split("?") |> List.first()

            %Tesla.Env{
              status: 200,
              body: %{
                "Id" => contact_id,
                "FirstName" => "Jane",
                "LastName" => "Doe",
                "Email" => "jane@example.com",
                "Phone" => "555-0100",
                "Title" => "Engineer",
                "MailingStreet" => "123 Main St",
                "MailingCity" => "San Francisco",
                "MailingState" => "CA",
                "MailingPostalCode" => "94102",
                "MailingCountry" => "USA"
              }
            }

          true ->
            %Tesla.Env{status: 404, body: %{}}
        end

      %{method: :patch, url: url} ->
        if String.contains?(url, "sobjects/Contact/") do
          %Tesla.Env{status: 204, body: nil}
        else
          %Tesla.Env{status: 404, body: %{}}
        end

      _ ->
        %Tesla.Env{status: 404, body: %{}}
    end)

    :ok
  end

  describe "search_contacts/2" do
    test "returns contacts from parameterized search" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:ok, contacts} = SalesforceApi.search_contacts(credential, "Jane")
      assert length(contacts) == 1
      assert hd(contacts).id == "003xx000001"
      assert hd(contacts).firstname == "Jane"
      assert hd(contacts).lastname == "Doe"
      assert hd(contacts).email == "jane@example.com"
      assert hd(contacts).display_name == "Jane Doe"
    end

    test "returns empty list when no results" do
      Tesla.Mock.mock(fn
        %{method: :get, url: url} ->
          if String.contains?(url, "parameterizedSearch") do
            %Tesla.Env{status: 200, body: %{"searchRecords" => []}}
          else
            %Tesla.Env{status: 404, body: %{}}
          end

        _ ->
          %Tesla.Env{status: 404, body: %{}}
      end)

      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:ok, []} = SalesforceApi.search_contacts(credential, "nonexistent")
    end

    test "returns error when instance_url is missing" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: nil})

      assert {:error, :missing_instance_url} = SalesforceApi.search_contacts(credential, "Jane")
    end

    test "returns api_error on non-200 response" do
      Tesla.Mock.mock(fn
        %{method: :get, url: url} ->
          if String.contains?(url, "parameterizedSearch") do
            %Tesla.Env{status: 500, body: %{"message" => "Internal server error"}}
          else
            %Tesla.Env{status: 404, body: %{}}
          end

        _ ->
          %Tesla.Env{status: 404, body: %{}}
      end)

      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:error, {:api_error, 500, _}} = SalesforceApi.search_contacts(credential, "Jane")
    end

    test "refreshes token on 401 and retries" do
      call_count = :counters.new(1, [])

      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "oauth2/token") do
            %Tesla.Env{
              status: 200,
              body: %{
                "access_token" => "refreshed_token",
                "instance_url" => "https://test.salesforce.com",
                "expires_in" => 7200
              }
            }
          else
            %Tesla.Env{status: 404, body: %{}}
          end

        %{method: :get, url: url} ->
          if String.contains?(url, "parameterizedSearch") do
            :counters.add(call_count, 1, 1)

            if :counters.get(call_count, 1) == 1 do
              %Tesla.Env{status: 401, body: %{"error" => "invalid_token"}}
            else
              %Tesla.Env{
                status: 200,
                body: %{
                  "searchRecords" => [
                    %{"Id" => "003retry", "FirstName" => "Retry", "LastName" => "User", "Email" => "retry@example.com"}
                  ]
                }
              }
            end
          else
            %Tesla.Env{status: 404, body: %{}}
          end

        _ ->
          %Tesla.Env{status: 404, body: %{}}
      end)

      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          instance_url: @instance_url,
          expires_at: DateTime.add(DateTime.utc_now(), -600, :second)
        })

      assert {:ok, contacts} = SalesforceApi.search_contacts(credential, "Retry")
      assert length(contacts) == 1
      assert hd(contacts).id == "003retry"
    end
  end

  describe "get_contact/2" do
    test "returns contact by id" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:ok, contact} = SalesforceApi.get_contact(credential, "003xx000001")
      assert contact.id == "003xx000001"
      assert contact.firstname == "Jane"
      assert contact.lastname == "Doe"
      assert contact.email == "jane@example.com"
      assert contact.address == "123 Main St"
      assert contact.city == "San Francisco"
      assert contact.state == "CA"
      assert contact.zip == "94102"
      assert contact.country == "USA"
    end

    test "returns error when instance_url is missing" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: nil})

      assert {:error, :missing_instance_url} = SalesforceApi.get_contact(credential, "003xx000001")
    end

    test "returns not_found for missing contact" do
      Tesla.Mock.mock(fn
        %{method: :get, url: url} ->
          if String.contains?(url, "sobjects/Contact/") do
            %Tesla.Env{status: 404, body: %{"errorCode" => "NOT_FOUND"}}
          else
            %Tesla.Env{status: 404, body: %{}}
          end

        _ ->
          %Tesla.Env{status: 404, body: %{}}
      end)

      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:error, :not_found} = SalesforceApi.get_contact(credential, "003nonexistent")
    end
  end

  describe "update_contact/3" do
    test "returns error when instance_url is missing" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: nil})

      assert {:error, :missing_instance_url} =
               SalesforceApi.update_contact(credential, "003xx000001", %{"phone" => "555"})
    end

    test "updates contact and returns refreshed contact" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      updates = %{"firstname" => "John", "phone" => "555-9999"}

      assert {:ok, contact} = SalesforceApi.update_contact(credential, "003xx000001", updates)
      assert contact.id == "003xx000001"
    end
  end

  describe "apply_updates/3" do
    test "returns :no_updates when no fields have apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003xx000001", updates)
    end

    test "filters only updates with apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: true},
        %{field: "email", new_value: "ignored@example.com", apply: false}
      ]

      assert {:ok, contact} = SalesforceApi.apply_updates(credential, "003xx000001", updates)
      assert contact.id == "003xx000001"
    end
  end

  describe "CrmApi delegation" do
    test "CrmApi.search_contacts delegates to SalesforceApi for salesforce credential" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:ok, contacts} = CrmApi.search_contacts(credential, "Jane")
      assert length(contacts) == 1
      assert hd(contacts).id == "003xx000001"
    end

    test "CrmApi.get_contact delegates to SalesforceApi for salesforce credential" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:ok, contact} = CrmApi.get_contact(credential, "003xx000001")
      assert contact.id == "003xx000001"
      assert contact.email == "jane@example.com"
    end

    test "CrmApi.update_contact delegates to SalesforceApi for salesforce credential" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      assert {:ok, _contact} = CrmApi.update_contact(credential, "003xx000001", %{"phone" => "555-0000"})
    end

    test "CrmApi.apply_updates delegates to SalesforceApi for salesforce credential" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id, instance_url: @instance_url})

      updates = [%{field: "phone", new_value: "555-1111", apply: true}]
      assert {:ok, contact} = CrmApi.apply_updates(credential, "003xx000001", updates)
      assert contact.id == "003xx000001"
    end
  end
end
