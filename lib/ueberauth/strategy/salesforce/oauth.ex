defmodule Ueberauth.Strategy.Salesforce.OAuth do
  @moduledoc """
  OAuth2 for Salesforce (Connected App).

  Supports both production (login.salesforce.com) and sandbox (test.salesforce.com).
  Set `site` in config to "https://test.salesforce.com" for sandbox.

  Add to your configuration:

      config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
        client_id: System.get_env("SALESFORCE_CLIENT_ID"),
        client_secret: System.get_env("SALESFORCE_CLIENT_SECRET"),
        site: System.get_env("SALESFORCE_SITE", "https://login.salesforce.com")
  """

  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://login.salesforce.com",
    authorize_url: "/services/oauth2/authorize",
    token_url: "/services/oauth2/token"
  ]

  @doc """
  Construct a client for requests to Salesforce.
  """
  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])
    site = Keyword.get(config, :site, "https://login.salesforce.com")

    opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)
      |> Keyword.put(:site, site)

    json_library = Ueberauth.json_library()

    client = OAuth2.Client.new(opts) |> OAuth2.Client.put_serializer("application/json", json_library)

    if redirect_uri = Keyword.get(opts, :redirect_uri) do
      %{client | redirect_uri: redirect_uri}
    else
      client
    end
  end

  @doc """
  Provides the authorize url for the request phase of Ueberauth.
  """
  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> OAuth2.Client.authorize_url!(params)
  end

  @doc """
  Fetches an access token from the Salesforce token endpoint.
  Pass code_verifier in opts when PKCE is required by the Connected App.
  """
  def get_access_token(params \\ [], opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])

    params =
      params
      |> Keyword.put(:client_id, config[:client_id])
      |> Keyword.put(:client_secret, config[:client_secret])
      |> maybe_put_code_verifier(Keyword.get(opts, :code_verifier))

    client_opts = Keyword.take(opts, [:redirect_uri])
    case client(client_opts) |> OAuth2.Client.get_token(params) do
      {:ok, %OAuth2.Client{token: %OAuth2.AccessToken{} = token}} ->
        {:ok, token}

      {:ok, %OAuth2.Client{token: nil}} ->
        {:error, {"no_token", "No token returned from Salesforce"}}

      {:error, %OAuth2.Response{body: body}} when is_map(body) ->
        error = Map.get(body, "error", "unknown")
        description = Map.get(body, "error_description", inspect(body))
        {:error, {error, description}}

      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, {"oauth2_error", to_string(reason)}}

      {:error, other} ->
        {:error, {"oauth2_error", inspect(other)}}
    end
  end

  @doc """
  Fetches user info from Salesforce using the instance_url from the token response.
  The token's other_params should contain instance_url from Salesforce's token response.
  Falls back to site if instance_url not present.
  """
  def get_userinfo(access_token, instance_url \\ nil) do
    base_url =
      instance_url ||
        Application.get_env(:ueberauth, __MODULE__, [])[:site] ||
        "https://login.salesforce.com"

    url = "#{String.trim_trailing(base_url, "/")}/services/oauth2/userinfo"

    headers = [{"Authorization", "Bearer #{access_token}"}]

    case Tesla.get(http_client(), url, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to get user info: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  defp maybe_put_code_verifier(params, nil), do: params
  defp maybe_put_code_verifier(params, verifier), do: Keyword.put(params, :code_verifier, verifier)

  defp http_client do
    Tesla.client([Tesla.Middleware.JSON])
  end

  # OAuth2.Strategy callbacks

  @impl OAuth2.Strategy
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  @impl OAuth2.Strategy
  def get_token(client, params, headers) do
    client
    |> put_param(:grant_type, "authorization_code")
    |> put_header("Content-Type", "application/x-www-form-urlencoded")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
