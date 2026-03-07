defmodule SocialScribe.GoogleCalendar do
  @moduledoc """
  Simplified Google Calendar API client.
  """

  @base_url "https://www.googleapis.com/calendar/v3"
  alias SocialScribe.ErrorMapper
  alias SocialScribe.Limits

  @behaviour SocialScribe.GoogleCalendarApi

  # TODO: Mock for testing
  def list_events(token, start_time, end_time, calendar_id) do
    Tesla.get(client(token), "/calendars/#{calendar_id}/events",
      query: [
        timeMin: Timex.format!(start_time, "{RFC3339}"),
        timeMax: Timex.format!(end_time, "{RFC3339}"),
        singleEvents: true,
        orderBy: "startTime"
      ]
    )
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, ErrorMapper.http(reason)}
    end
  end

  defp client(token) do
    recv_timeout = Limits.http(:default_recv_timeout_ms)

    Tesla.client([
      {Tesla.Middleware.BaseUrl, @base_url},
      {Tesla.Middleware.Retry,
       max_retries: Limits.http(:retry_attempts),
       delay: Limits.http(:retry_backoff_base_ms),
       max_delay: Limits.http(:retry_backoff_max_ms),
       should_retry: &should_retry?/3},
      {Tesla.Middleware.Timeout, timeout: recv_timeout},
      {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{token}"}]},
      Tesla.Middleware.JSON
    ])
  end

  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status in [408, 429], do: true
  defp should_retry?({:ok, %{status: status}}, _env, _ctx) when status >= 500, do: true
  defp should_retry?({:error, :timeout}, _env, _ctx), do: true
  defp should_retry?({:error, :econnrefused}, _env, _ctx), do: true
  defp should_retry?(_, _, _), do: false
end
