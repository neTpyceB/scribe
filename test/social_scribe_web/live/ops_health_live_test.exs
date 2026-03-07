defmodule SocialScribeWeb.OpsHealthLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.BotsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.MeetingsFixtures

  describe "OpsHealthLive" do
    setup :register_and_log_in_user

    test "redirects if user is not logged in", %{conn: conn} do
      conn = recycle(conn)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/health")
      assert path == ~p"/"
    end

    test "redirects if user is not in admin mode", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/health")
      assert path == ~p"/dashboard"
    end

    test "renders health dashboard sections", %{conn: conn, user: user} do
      user_bot_preference_fixture(%{user_id: user.id, is_admin_mode: true})

      _google =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "google",
          uid: "google-health-123"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/health")

      assert has_element?(view, "h1", "Ops Health")
      assert has_element?(view, "h2", "System Health")
      assert has_element?(view, "h2", "Integrations")
      assert has_element?(view, "h2", "Background Jobs")
      assert has_element?(view, "h2", "Replay Controls")
      assert has_element?(view, "td", "google")
    end

    test "triggers bot poller action", %{conn: conn, user: user} do
      user_bot_preference_fixture(%{user_id: user.id, is_admin_mode: true})
      {:ok, view, _html} = live(conn, ~p"/dashboard/health")

      view
      |> element("#health-run-bot-poller")
      |> render_click()

      assert has_element?(view, "#health-action-result", "Bot poller job triggered.")
    end

    test "shows error when rerun ai has no meeting", %{conn: conn, user: user} do
      user_bot_preference_fixture(%{user_id: user.id, is_admin_mode: true})
      {:ok, view, _html} = live(conn, ~p"/dashboard/health")

      view
      |> element("#health-rerun-latest-ai")
      |> render_click()

      assert has_element?(view, "#health-action-result", "No meeting available to re-run AI.")
    end

    test "resets salesforce cache for latest meeting transcript", %{conn: conn, user: user} do
      user_bot_preference_fixture(%{user_id: user.id, is_admin_mode: true})

      calendar_event =
        calendar_event_fixture(%{
          user_id: user.id
        })

      meeting = meeting_fixture(%{calendar_event_id: calendar_event.id})

      _transcript =
        meeting_transcript_fixture(%{
          meeting_id: meeting.id,
          content: %{"data" => [%{"speaker" => "A", "words" => [%{"text" => "Hello"}]}]},
          salesforce_ai_suggestions: %{"items" => [%{"field" => "phone", "value" => "123"}]},
          salesforce_ai_transcript_hash: "abc123"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/health")

      view
      |> element("#health-reset-salesforce-cache")
      |> render_click()

      assert has_element?(view, "#health-action-result", "Salesforce suggestion cache reset.")
      assert has_element?(view, "h1", "Ops Health")
    end
  end
end
