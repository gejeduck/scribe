defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  alias SocialScribe.Accounts
  alias SocialScribeWeb.AuthController

  import SocialScribe.AccountsFixtures

  describe "Salesforce OAuth callback" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "creates Salesforce credential and redirects to settings on success", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        provider: :salesforce,
        uid: "salesforce_user_123",
        info: %Ueberauth.Auth.Info{
          email: "salesforce@example.com",
          name: "Test User"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "sf_access_token",
          refresh_token: "sf_refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.to_unix()
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{
            user: %{"preferred_username" => "salesforce@example.com"},
            instance_url: "https://test.salesforce.com"
          }
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_session()
        |> fetch_flash()
        |> Plug.Conn.assign(:current_user, user)
        |> Plug.Conn.assign(:ueberauth_auth, auth)

      conn = AuthController.callback(conn, %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Salesforce account connected"

      credential = Accounts.get_user_crm_credential(user.id, "salesforce")
      assert credential != nil
      assert credential.provider == "salesforce"
      assert credential.uid == "salesforce_user_123"
      assert credential.token == "sf_access_token"
      assert credential.refresh_token == "sf_refresh_token"
      assert credential.instance_url == "https://test.salesforce.com"
    end

    test "updates existing Salesforce credential on re-auth", %{conn: conn, user: user} do
      existing = salesforce_credential_fixture(%{user_id: user.id, uid: "salesforce_user_456"})

      auth = %Ueberauth.Auth{
        provider: :salesforce,
        uid: "salesforce_user_456",
        info: %Ueberauth.Auth.Info{email: "updated@example.com"},
        credentials: %Ueberauth.Auth.Credentials{
          token: "new_access_token",
          refresh_token: "new_refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.to_unix()
        },
        extra: %Ueberauth.Auth.Extra{
          raw_info: %{
            user: %{"preferred_username" => "updated@example.com"},
            instance_url: "https://new.instance.salesforce.com"
          }
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_session()
        |> fetch_flash()
        |> Plug.Conn.assign(:current_user, user)
        |> Plug.Conn.assign(:ueberauth_auth, auth)

      conn = AuthController.callback(conn, %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"

      credential = Accounts.get_user_crm_credential(user.id, "salesforce")
      assert credential.id == existing.id
      assert credential.token == "new_access_token"
      assert credential.instance_url == "https://new.instance.salesforce.com"
    end
  end
end
