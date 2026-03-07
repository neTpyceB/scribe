defmodule SocialScribeWeb.RunbookLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.BotsFixtures

  describe "RunbookLive" do
    setup :register_and_log_in_user

    test "redirects if user is not logged in", %{conn: conn} do
      conn = recycle(conn)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/runbook")
      assert path == ~p"/"
    end

    test "redirects if user is not in admin mode", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/runbook")
      assert path == ~p"/dashboard"
    end

    test "renders manuals and quick links", %{conn: conn, user: user} do
      user_bot_preference_fixture(%{user_id: user.id, is_admin_mode: true})

      {:ok, view, _html} = live(conn, ~p"/dashboard/runbook")

      assert has_element?(view, "h1", "Runbook")
      assert has_element?(view, "h2", "Manual 1: No meetings appear on dashboard")
      assert has_element?(view, "h2", "Manual 2: Transcript missing after recording")
      assert has_element?(view, "a", "Open Health")
      assert has_element?(view, "a", "Open Settings")
      assert has_element?(view, "a", "Open Meetings")
      assert has_element?(view, "a", "Open Analytics")
    end
  end
end
