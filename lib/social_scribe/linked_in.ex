defmodule SocialScribe.LinkedIn do
  alias SocialScribe.Limits
  require Logger

  @behaviour SocialScribe.LinkedInApi

  @linkedin_api_base_url "https://api.linkedin.com/v2"

  @impl SocialScribe.LinkedInApi
  def post_text_share(token, author_urn, text_content) do
    body =
      %{
        "author" => author_urn,
        "lifecycleState" => "PUBLISHED",
        "specificContent" => %{
          "com.linkedin.ugc.ShareContent" => %{
            "shareCommentary" => %{
              "text" => text_content
            },
            "shareMediaCategory" => "NONE"
          }
        },
        "visibility" => %{
          "com.linkedin.ugc.MemberNetworkVisibility" => "PUBLIC"
        }
      }

    case Tesla.post(client(token), "/ugcPosts", body) do
      # HTTP 201 Created is success
      {:ok, %Tesla.Env{status: 201, body: response_body}} ->
        Logger.info("Successfully posted to LinkedIn. Response ID: #{response_body["id"]}")
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("LinkedIn API Error (Status: #{status}): #{inspect(error_body)}")
        message = get_in(error_body, ["message"]) || "Unknown API error"
        {:error, {:api_error, status, message, error_body}}

      {:error, reason} ->
        Logger.error("LinkedIn HTTP Error: #{inspect(reason)}")
        {:error, {:upstream_unavailable, reason}}
    end
  end

  defp client(token) do
    recv_timeout = Limits.http(:default_recv_timeout_ms)

    Tesla.client([
      {Tesla.Middleware.BaseUrl, @linkedin_api_base_url},
      {Tesla.Middleware.Retry,
       max_retries: Limits.http(:retry_attempts),
       delay: Limits.http(:retry_backoff_base_ms),
       max_delay: Limits.http(:retry_backoff_max_ms),
       should_retry: &should_retry?/3},
      {Tesla.Middleware.Timeout, timeout: recv_timeout},
      {Tesla.Middleware.Headers,
       [{"Authorization", "Bearer #{token}"}, {"X-Restli-Protocol-Version", "2.0.0"}]},
      Tesla.Middleware.JSON
    ])
  end

  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status in [408, 429], do: true
  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status >= 500, do: true
  defp should_retry?({:error, :timeout}, _env, _ctx), do: true
  defp should_retry?({:error, :econnrefused}, _env, _ctx), do: true
  defp should_retry?(_, _, _), do: false
end
