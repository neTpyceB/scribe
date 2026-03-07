defmodule SocialScribeWeb.AnalyticsLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.CalendarFixtures
  import SocialScribe.MeetingsFixtures

  alias SocialScribe.Automations

  describe "AnalyticsLive" do
    setup :register_and_log_in_user

    test "redirects if user is not logged in", %{conn: conn} do
      conn = recycle(conn)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/analytics")
      assert path == ~p"/"
    end

    test "renders analytics dashboard and supports window filter", %{conn: conn, user: user} do
      calendar_event = calendar_event_fixture(%{user_id: user.id})
      meeting = meeting_fixture(%{calendar_event_id: calendar_event.id})

      {:ok, automation} =
        Automations.create_automation(%{
          user_id: user.id,
          name: "LinkedIn Update",
          platform: :linkedin,
          description: "desc",
          example: "example",
          is_active: true
        })

      {:ok, _result} =
        Automations.create_automation_result(%{
          automation_id: automation.id,
          meeting_id: meeting.id,
          generated_content: "content",
          status: "draft"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/analytics")

      assert has_element?(view, "h1", "Analytics")
      assert has_element?(view, "h2", "Meetings Processed Per Day")
      assert has_element?(view, "h2", "Posted vs Draft By Platform")
      assert has_element?(view, "h2", "Top Automation Templates")
      assert has_element?(view, "td", "linkedin")

      view
      |> element("a", "7d")
      |> render_click()

      assert_patch(view, ~p"/dashboard/analytics?window=7")
      assert has_element?(view, "a", "7d")
    end
  end
end
