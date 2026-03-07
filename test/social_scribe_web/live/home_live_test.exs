defmodule SocialScribeWeb.HomeLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.BotsFixtures

  describe "HomeLive" do
    setup :register_and_log_in_user

    test "hides admin content by default", %{conn: conn, user: user} do
      user_bot_preference_fixture(%{user_id: user.id, is_admin_mode: false})

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      refute has_element?(view, "h2", "Top Advice / FAQ")
      refute has_element?(view, "a", "Analytics")
      refute has_element?(view, "a", "Health")
      refute has_element?(view, "a", "Runbook")
      assert has_element?(view, "label", "I am admin")
    end

    test "shows admin content when checkbox is enabled", %{conn: conn, user: user} do
      user_bot_preference_fixture(%{user_id: user.id, is_admin_mode: false})
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      redirect_response =
        view
        |> element("input[phx-click='toggle_admin_mode'][phx-value-enabled='true']")
        |> render_click()

      {:ok, view, _html} = follow_redirect(redirect_response, conn, ~p"/dashboard")

      assert has_element?(view, "h2", "Top Advice / FAQ")
      assert has_element?(view, "a", "Analytics")
      assert has_element?(view, "a", "Health")
      assert has_element?(view, "a", "Runbook")
      assert has_element?(view, "label", "I am admin")
    end
  end
end
