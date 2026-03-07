defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Workers.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "does nothing when no Salesforce tokens are expiring soon" do
      user = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      assert SalesforceTokenRefresher.perform(%Oban.Job{}) == :ok
    end

    test "refreshes expiring Salesforce tokens" do
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

        _ ->
          %Tesla.Env{status: 404, body: %{}}
      end)

      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -600, :second),
          refresh_token: "valid_refresh"
        })

      assert SalesforceTokenRefresher.perform(%Oban.Job{}) == :ok

      updated = SocialScribe.Repo.get!(SocialScribe.Accounts.UserCredential, credential.id)
      assert updated.token == "refreshed_token"
    end

    test "continues when refresh fails for one credential" do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          if String.contains?(url, "oauth2/token") do
            %Tesla.Env{status: 400, body: %{"error" => "invalid_grant"}}
          else
            %Tesla.Env{status: 404, body: %{}}
          end

        _ ->
          %Tesla.Env{status: 404, body: %{}}
      end)

      user = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), -600, :second)
      })

      assert SalesforceTokenRefresher.perform(%Oban.Job{}) == :ok
    end
  end
end
