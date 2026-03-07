defmodule SocialScribe.Facebook do
  @behaviour SocialScribe.FacebookApi

  alias SocialScribe.Limits

  require Logger

  @base_url "https://graph.facebook.com/v22.0"

  @impl SocialScribe.FacebookApi
  def post_message_to_page(page_id, page_access_token, message) do
    body_params = %{
      message: message,
      access_token: page_access_token
    }

    case Tesla.post(client(), "/#{page_id}/feed", body_params) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        Logger.info(
          "Successfully posted to Facebook Page #{page_id}. Response ID: #{response_body["id"]}"
        )

        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error(
          "Facebook Page Post API Error (Page ID: #{page_id}, Status: #{status}): #{inspect(error_body)}"
        )

        message = get_in(error_body, ["error", "message"]) || "Unknown API error"
        {:error, {:api_error_posting, status, message, error_body}}

      {:error, reason} ->
        Logger.error("Facebook Page Post HTTP Error (Page ID: #{page_id}): #{inspect(reason)}")
        {:error, {:upstream_unavailable, {:http_error_posting, reason}}}
    end
  end

  @impl SocialScribe.FacebookApi
  def fetch_user_pages(user_id, user_access_token) do
    case Tesla.get(client(), "/#{user_id}/accounts?access_token=#{user_access_token}") do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => pages_data}}} ->
        valid_pages =
          Enum.filter(pages_data, fn page ->
            Enum.member?(page["tasks"] || [], "CREATE_CONTENT") ||
              Enum.member?(page["tasks"] || [], "MANAGE")
          end)
          |> Enum.map(fn page ->
            %{
              id: page["id"],
              name: page["name"],
              category: page["category"],
              page_access_token: page["access_token"]
            }
          end)

        {:ok, valid_pages}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Failed to fetch user pages: #{status} - #{body}"}

      {:error, reason} ->
        {:error, "Failed to fetch user pages: #{inspect(reason)}"}
    end
  end

  defp client do
    recv_timeout = Limits.http(:default_recv_timeout_ms)

    Tesla.client([
      {Tesla.Middleware.BaseUrl, @base_url},
      {Tesla.Middleware.Retry,
       max_retries: Limits.http(:retry_attempts),
       delay: Limits.http(:retry_backoff_base_ms),
       max_delay: Limits.http(:retry_backoff_max_ms),
       should_retry: &should_retry?/3},
      {Tesla.Middleware.Timeout, timeout: recv_timeout},
      Tesla.Middleware.JSON
    ])
  end

  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status in [408, 429], do: true
  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status >= 500, do: true
  defp should_retry?({:error, :timeout}, _env, _ctx), do: true
  defp should_retry?({:error, :econnrefused}, _env, _ctx), do: true
  defp should_retry?(_, _, _), do: false
end
