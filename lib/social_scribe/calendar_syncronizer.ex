defmodule SocialScribe.CalendarSyncronizer do
  @moduledoc """
  Fetches and syncs Google Calendar events.
  """

  require Logger

  alias SocialScribe.GoogleCalendarApi
  alias SocialScribe.Calendar
  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.TokenRefresherApi

  @doc """
  Syncs events for a user.

  Currently, only works for the primary calendar.
  Meeting links are extracted from hangoutLink, location, description, and
  conference entry points.

  #TODO: Add support for syncing only since the last sync time and record sync attempts
  """
  def sync_events_for_user(user) do
    user
    |> Accounts.list_user_credentials(provider: "google")
    |> Task.async_stream(&fetch_and_sync_for_credential/1, ordered: false, on_timeout: :kill_task)
    |> Stream.run()

    {:ok, :sync_complete}
  end

  defp fetch_and_sync_for_credential(%UserCredential{} = credential) do
    with {:ok, token} <- ensure_valid_token(credential),
         {:ok, %{"items" => items}} <-
           GoogleCalendarApi.list_events(
             token,
             DateTime.utc_now() |> Timex.beginning_of_day() |> Timex.shift(days: -1),
             DateTime.utc_now() |> Timex.end_of_day() |> Timex.shift(days: 7),
             "primary"
           ),
         :ok <- sync_items(items, credential.user_id, credential.id) do
      :ok
    else
      {:error, reason} ->
        # Log errors but don't crash the sync for other accounts
        Logger.error("Failed to sync credential #{credential.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_valid_token(%UserCredential{} = credential) do
    if DateTime.compare(credential.expires_at || DateTime.utc_now(), DateTime.utc_now()) == :lt do
      case TokenRefresherApi.refresh_token(credential.refresh_token) do
        {:ok, new_token_data} ->
          {:ok, updated_credential} =
            Accounts.update_credential_tokens(credential, new_token_data)

          {:ok, updated_credential.token}

        {:error, reason} ->
          {:error, {:refresh_failed, reason}}
      end
    else
      {:ok, credential.token}
    end
  end

  defp sync_items(items, user_id, credential_id) do
    Enum.each(items, fn item ->
      case extract_meeting_url(item) do
        nil ->
          :ok

        meeting_url ->
          attrs = parse_google_event(item, user_id, credential_id, meeting_url)

          try do
            case Calendar.create_or_update_calendar_event(attrs) do
              {:ok, _event} ->
                :ok

              {:error, changeset} ->
                Logger.error(
                  "Failed to persist calendar event #{attrs.google_event_id}: #{inspect(changeset.errors)}"
                )
            end
          rescue
            error ->
              Logger.error(
                "Failed to persist calendar event #{attrs.google_event_id}: #{Exception.message(error)}"
              )
          end
      end
    end)

    :ok
  end

  defp parse_google_event(item, user_id, credential_id, meeting_url) do
    start_time_str = Map.get(item["start"], "dateTime", Map.get(item["start"], "date"))
    end_time_str = Map.get(item["end"], "dateTime", Map.get(item["end"], "date"))

    %{
      google_event_id: normalize_google_event_id(item["id"]),
      summary: truncate(Map.get(item, "summary", "No Title"), 255),
      description: Map.get(item, "description"),
      location: truncate(Map.get(item, "location"), 255),
      html_link: truncate(Map.get(item, "htmlLink"), 255),
      hangout_link: truncate(meeting_url, 255),
      status: truncate(Map.get(item, "status"), 255),
      start_time: to_utc_datetime(start_time_str),
      end_time: to_utc_datetime(end_time_str),
      user_id: user_id,
      user_credential_id: credential_id
    }
  end

  defp to_utc_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        nil
    end
  end

  defp extract_meeting_url(item) do
    conference_urls =
      item
      |> Map.get("conferenceData", %{})
      |> Map.get("entryPoints", [])
      |> Enum.map(&Map.get(&1, "uri"))

    [
      Map.get(item, "hangoutLink"),
      Map.get(item, "location"),
      Map.get(item, "description")
      | conference_urls
    ]
    |> Enum.find_value(&extract_supported_url/1)
  end

  defp extract_supported_url(value) when is_binary(value) do
    if supported_meeting_url?(value) do
      value
    else
      Regex.scan(~r/https?:\/\/[^\s<>"']+/i, value)
      |> List.flatten()
      |> Enum.find(&supported_meeting_url?/1)
    end
  end

  defp extract_supported_url(_), do: nil

  defp supported_meeting_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        String.contains?(host, "zoom.us") ||
          String.contains?(host, "meet.google.com") ||
          String.contains?(host, "teams.microsoft.com")

      _ ->
        false
    end
  end

  defp truncate(value, _max) when is_nil(value), do: nil

  defp truncate(value, max) when is_binary(value) do
    if String.length(value) <= max do
      value
    else
      String.slice(value, 0, max)
    end
  end

  defp normalize_google_event_id(value) when is_binary(value) do
    if String.length(value) <= 255 do
      value
    else
      "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
    end
  end

  defp normalize_google_event_id(_), do: "missing-google-event-id"
end
