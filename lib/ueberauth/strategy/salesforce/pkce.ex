defmodule Ueberauth.Strategy.Salesforce.PKCE do
  @moduledoc """
  PKCE (Proof Key for Code Exchange) helpers for Salesforce OAuth.
  Required when the Connected App has "Require PKCE" enabled.
  """

  @doc """
  Generates a PKCE code_verifier (43-128 chars, URL-safe).
  """
  def generate_code_verifier do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates code_challenge from code_verifier using S256 method.
  Returns base64url-encoded SHA256 hash.
  """
  def generate_code_challenge(code_verifier) do
    code_verifier
    |> sha256()
    |> Base.url_encode64(padding: false)
  end

  defp sha256(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
  end
end
