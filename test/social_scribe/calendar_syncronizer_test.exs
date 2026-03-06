defmodule SocialScribe.CalendarSyncronizerTest do
  use SocialScribe.DataCase, async: true

  import Mox
  import Ecto.Query
  import SocialScribe.AccountsFixtures

  # The context containing the sync logic
  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Calendar.CalendarEvent
  alias SocialScribe.TokenRefresherMock
  alias SocialScribe.GoogleCalendarApiMock, as: GoogleApiMock

  # Mock data for a Google Calendar API response
  @mock_google_events [
    %{
      "id" => "zoom-event-123",
      "summary" => "Zoom Meeting",
      "location" => "https://zoom.us/j/12345",
      "start" => %{"dateTime" => "2025-05-25T10:00:00-03:00"},
      "end" => %{"dateTime" => "2025-05-25T11:00:00-03:00"},
      "status" => "confirmed",
      "htmlLink" => "https://calendar.google.com/calendar/event?eid=zoom-event-123"
    },
    %{
      "id" => "meet-event-456",
      "summary" => "Google Meet Call",
      "hangoutLink" => "https://meet.google.com/abc-def-ghi",
      "start" => %{"dateTime" => "2025-05-26T14:00:00-03:00"},
      "end" => %{"dateTime" => "2025-05-26T14:30:00-03:00"},
      "status" => "confirmed",
      "htmlLink" => "https://calendar.google.com/calendar/event?eid=meet-event-456"
    },
    %{
      "id" => "zoom-description-321",
      "summary" => "Zoom in Description",
      "description" => "Join here: https://zoom.us/j/54321?pwd=abcd",
      "start" => %{"dateTime" => "2025-05-26T15:00:00-03:00"},
      "end" => %{"dateTime" => "2025-05-26T15:30:00-03:00"},
      "status" => "confirmed",
      "htmlLink" => "https://calendar.google.com/calendar/event?eid=zoom-description-321"
    },
    %{
      "id" => "no-link-event-789",
      "summary" => "Lunch Break",
      "start" => %{"dateTime" => "2025-05-26T12:00:00-03:00"},
      "end" => %{"dateTime" => "2025-05-26T13:00:00-03:00"},
      "status" => "confirmed",
      "htmlLink" => nil
    }
  ]

  @oversized_event_id String.duplicate("google-event-id-", 30)
  @oversized_event_link "https://www.google.com/calendar/event?eid=" <>
                          String.duplicate("abc", 120)

  describe "sync_events_for_user/1" do
    setup do
      stub_with(GoogleApiMock, SocialScribe.GoogleCalendar)
      stub_with(TokenRefresherMock, SocialScribe.TokenRefresher)
      :ok
    end

    test "fetches and syncs new events with meeting links to the database" do
      user = user_fixture()

      credential =
        user_credential_fixture(%{
          provider: "google",
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      expect(GoogleApiMock, :list_events, fn _token, _start_time, _end_time, calendar_id ->
        assert calendar_id == "primary"
        {:ok, %{"items" => @mock_google_events}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      assert Repo.aggregate(CalendarEvent, :count, :id) == 3

      zoom_event = Repo.get_by!(CalendarEvent, google_event_id: "zoom-event-123")
      assert zoom_event.summary == "Zoom Meeting"
      assert zoom_event.user_id == user.id
      assert zoom_event.user_credential_id == credential.id

      meet_event = Repo.get_by!(CalendarEvent, google_event_id: "meet-event-456")
      assert meet_event.summary == "Google Meet Call"

      description_zoom = Repo.get_by!(CalendarEvent, google_event_id: "zoom-description-321")
      assert description_zoom.hangout_link == "https://zoom.us/j/54321?pwd=abcd"

      assert Repo.get_by(CalendarEvent, google_event_id: "no-link-event-789") == nil
    end

    test "refreshes token if expired and then syncs events" do
      user = user_fixture()

      credential =
        user_credential_fixture(%{
          provider: "google",
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -100, :second)
        })

      new_token_data = %{"access_token" => "new-refreshed-token", "expires_in" => 3600}
      refresh_token = credential.refresh_token

      expect(TokenRefresherMock, :refresh_token, fn ^refresh_token ->
        {:ok, new_token_data}
      end)

      expect(GoogleApiMock, :list_events, fn "new-refreshed-token", _, _, _ ->
        {:ok, %{"items" => [@mock_google_events |> Enum.at(0)]}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      assert Repo.aggregate(CalendarEvent, :count, :id) == 1
      assert Repo.get_by!(CalendarEvent, google_event_id: "zoom-event-123")
    end

    test "does not crash when google event fields exceed varchar limits" do
      user = user_fixture()

      credential =
        user_credential_fixture(%{
          provider: "google",
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      large_event = %{
        "id" => @oversized_event_id,
        "summary" => String.duplicate("S", 500),
        "description" =>
          "Event details " <>
            String.duplicate("D", 1100) <>
            " Join here: https://teams.microsoft.com/meet/12345?p=abc",
        "location" => String.duplicate("L", 400),
        "htmlLink" => @oversized_event_link,
        "status" => String.duplicate("C", 500),
        "start" => %{"dateTime" => "2025-05-26T12:00:00-03:00"},
        "end" => %{"dateTime" => "2025-05-26T13:00:00-03:00"}
      }

      expect(GoogleApiMock, :list_events, fn _token, _start_time, _end_time, "primary" ->
        {:ok, %{"items" => [large_event]}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      event =
        Repo.one(
          from e in CalendarEvent,
            where: e.user_id == ^user.id and e.summary == ^String.duplicate("S", 255)
        )

      assert event.user_credential_id == credential.id
      assert String.length(event.google_event_id) <= 255
      assert String.length(event.html_link) <= 255
      assert String.length(event.location) <= 255
      assert String.length(event.status) <= 255
    end
  end
end
