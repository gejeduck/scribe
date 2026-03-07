defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.Accounts
  alias SocialScribe.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "refreshes credential when token is expired" do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "oauth2/token") do
            %Tesla.Env{
              status: 200,
              body: %{
                "access_token" => "new_access_token",
                "instance_url" => "https://test.salesforce.com",
                "expires_in" => 7200
              }
            }
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
          token: "old_token",
          refresh_token: "refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), -300, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.token == "new_access_token"
      assert result.instance_url == "https://test.salesforce.com"
      assert result.id == credential.id
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "oauth2/token") do
            %Tesla.Env{
              status: 200,
              body: %{
                "access_token" => "new_access_token",
                "instance_url" => "https://test.salesforce.com",
                "expires_in" => 7200
              }
            }
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
          token: "old_token",
          refresh_token: "old_refresh",
          instance_url: "https://old.instance.salesforce.com"
        })

      {:ok, updated} = SalesforceTokenRefresher.refresh_credential(credential)

      assert updated.token == "new_access_token"
      assert updated.instance_url == "https://test.salesforce.com"
      assert updated.id == credential.id

      # Verify persisted in DB
      from_db = Accounts.get_user_credential!(updated.id)
      assert from_db.token == "new_access_token"
      assert from_db.instance_url == "https://test.salesforce.com"
    end

    test "preserves instance_url when not in refresh response" do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "oauth2/token") do
            %Tesla.Env{
              status: 200,
              body: %{
                "access_token" => "new_access_token",
                "expires_in" => 7200
              }
            }
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
          instance_url: "https://existing.instance.salesforce.com"
        })

      {:ok, updated} = SalesforceTokenRefresher.refresh_credential(credential)

      assert updated.token == "new_access_token"
      assert updated.instance_url == "https://existing.instance.salesforce.com"
    end
  end
end
