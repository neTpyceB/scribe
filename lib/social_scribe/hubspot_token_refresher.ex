defmodule SocialScribe.HubspotTokenRefresher do
  @moduledoc """
  Refreshes HubSpot OAuth tokens.
  """

  @hubspot_token_url "https://api.hubapi.com/oauth/v1/token"

  alias SocialScribe.ErrorMapper
  alias SocialScribe.Limits

  def client do
    recv_timeout = Limits.http(:default_recv_timeout_ms)

    Tesla.client([
      {Tesla.Middleware.Retry,
       max_retries: Limits.http(:retry_attempts),
       delay: Limits.http(:retry_backoff_base_ms),
       max_delay: Limits.http(:retry_backoff_max_ms),
       should_retry: &should_retry?/3},
      {Tesla.Middleware.Timeout, timeout: recv_timeout},
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ])
  end

  @doc """
  Refreshes a HubSpot access token using the refresh token.
  Returns {:ok, response_body} with new access_token, refresh_token, and expires_in.
  """
  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    case Tesla.post(client(), @hubspot_token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, ErrorMapper.http(reason)}
    end
  end

  @doc """
  Refreshes the token for a HubSpot credential and updates it in the database.
  """
  def refresh_credential(credential) do
    alias SocialScribe.Accounts

    case refresh_token(credential.refresh_token) do
      {:ok, response} ->
        attrs = %{
          token: response["access_token"],
          refresh_token: response["refresh_token"],
          expires_at: DateTime.add(DateTime.utc_now(), response["expires_in"], :second)
        }

        Accounts.update_user_credential(credential, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Refreshes if expired or about to expire (within 5 minutes).
  """
  def ensure_valid_token(credential) do
    buffer_seconds = 300

    if DateTime.compare(
         credential.expires_at,
         DateTime.add(DateTime.utc_now(), buffer_seconds, :second)
       ) == :lt do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end

  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status in [408, 429], do: true
  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status >= 500, do: true
  defp should_retry?({:error, :timeout}, _env, _ctx), do: true
  defp should_retry?({:error, :econnrefused}, _env, _ctx), do: true
  defp should_retry?(_, _, _), do: false
end
