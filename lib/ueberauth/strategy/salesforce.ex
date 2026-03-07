defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.

  Supports production and sandbox orgs. Configure the site in Ueberauth.Strategy.Salesforce.OAuth:
  - Production: https://login.salesforce.com
  - Sandbox: https://test.salesforce.com
  """

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "api id refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @pkce_session_key "ueberauth_salesforce_code_verifier"

  @doc """
  Handles initial request for Salesforce authentication.
  Includes PKCE (code_challenge) when Connected App requires it.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    code_verifier = Ueberauth.Strategy.Salesforce.PKCE.generate_code_verifier()
    code_challenge = Ueberauth.Strategy.Salesforce.PKCE.generate_code_challenge(code_verifier)

    conn =
      conn
      |> put_private(:salesforce_code_verifier, code_verifier)
      |> Plug.Conn.put_session(@pkce_session_key, code_verifier)

    opts =
      [scope: scopes, redirect_uri: callback_url(conn)]
      |> Keyword.put(:code_challenge, code_challenge)
      |> Keyword.put(:code_challenge_method, "S256")
      # Force consent screen so user always sees "Allow Access?" even when already logged in
      |> Keyword.put(:prompt, "consent")
      |> with_state_param(conn)

    redirect!(conn, Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Salesforce.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    code_verifier = Plug.Conn.get_session(conn, @pkce_session_key)

    conn = Plug.Conn.delete_session(conn, @pkce_session_key)

    opts =
      [redirect_uri: callback_url(conn)]
      |> maybe_put_code_verifier(code_verifier)

    case Ueberauth.Strategy.Salesforce.OAuth.get_access_token([code: code], opts) do
      {:ok, token} ->
        fetch_user(conn, token)

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  defp maybe_put_code_verifier(opts, nil), do: opts
  defp maybe_put_code_verifier(opts, verifier), do: Keyword.put(opts, :code_verifier, verifier)

  @doc """
  Cleans up the private area of the connection.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
    |> Plug.Conn.delete_session(@pkce_session_key)
  end

  @doc """
  Fetches the uid field from the response (user_id).
  """
  def uid(conn) do
    uid_field =
      conn
      |> option(:uid_field)
      |> to_string()

    conn.private.salesforce_user[uid_field]
  end

  @doc """
  Includes the credentials from the Salesforce response.
  """
  def credentials(conn) do
    token = conn.private.salesforce_token

    # Salesforce token may not have expires_at; use long expiry if missing
    expires_at =
      if token.expires_at do
        token.expires_at
      else
        # Salesforce access tokens typically last 2 hours; use 2h from now
        DateTime.add(DateTime.utc_now(), 7200, :second) |> DateTime.to_unix()
      end

    %Credentials{
      expires: true,
      expires_at: expires_at,
      scopes: (token.other_params["scope"] || "") |> String.split(" ", trim: true),
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type || "Bearer"
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.salesforce_user

    %Info{
      email: user["preferred_username"] || user["email"],
      name: user["name"] || user["preferred_username"]
    }
  end

  @doc """
  Stores the raw information obtained from the Salesforce callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.salesforce_token,
        user: conn.private.salesforce_user,
        instance_url: conn.private.salesforce_user["instance_url"]
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :salesforce_token, token)

    instance_url = token.other_params["instance_url"]

    case Ueberauth.Strategy.Salesforce.OAuth.get_userinfo(token.access_token, instance_url) do
      {:ok, user} ->
        put_private(conn, :salesforce_user, user)

      {:error, reason} ->
        set_errors!(conn, [error("userinfo_error", reason)])
    end
  end

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
