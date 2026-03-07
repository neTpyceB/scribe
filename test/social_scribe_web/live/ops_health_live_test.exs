defmodule SocialScribeWeb.OpsHealthLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures

  describe "OpsHealthLive" do
    setup :register_and_log_in_user

    test "redirects if user is not logged in", %{conn: conn} do
      conn = recycle(conn)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/health")
      assert path == ~p"/"
    end

    test "renders health dashboard sections", %{conn: conn, user: user} do
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
      assert has_element?(view, "td", "google")
    end
  end
end
