defmodule SocialScribeWeb.UserSettingsLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures

  describe "UserSettingsLive" do
    @describetag :capture_log

    setup :register_and_log_in_user

    test "redirects if user is not logged in", %{conn: conn} do
      conn = recycle(conn)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/settings")
      assert path == ~p"/users/log_in"
    end

    test "renders settings page for logged-in user", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "h1", "User Settings")
      assert has_element?(view, "h2", "Connected Google Accounts")
      assert has_element?(view, "h2", "Connected Salesforce Accounts")
      assert has_element?(view, "a", "Connect another Google Account")
    end

    test "displays a message if no Google accounts are connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
      assert has_element?(view, "p", "You haven't connected any Google accounts yet.")
    end

    test "displays connected Google accounts", %{conn: conn, user: user} do
      # Create a Google credential for the user
      # Assuming UserCredential has an :email field for display purposes.
      # If not, you might display the UID or another identifier.
      credential_attrs = %{
        user_id: user.id,
        provider: "google",
        uid: "google-uid-123",
        token: "test-token",
        email: "linked_account@example.com"
      }

      credential = user_credential_fixture(credential_attrs)

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "li", "UID: google-uid-123")
      assert has_element?(view, "li", "(linked_account@example.com)")
      assert has_element?(view, "#disconnect-google-#{credential.id}")
      refute has_element?(view, "p", "You haven't connected any Google accounts yet.")
    end

    test "disconnects connected Google account", %{conn: conn, user: user} do
      credential =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "google",
          uid: "google-disconnect-123",
          email: "google-disconnect@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "#disconnect-google-#{credential.id}")

      view
      |> element("#disconnect-google-#{credential.id}")
      |> render_click()

      refute has_element?(view, "#disconnect-google-#{credential.id}")
      assert has_element?(view, "p", "You haven't connected any Google accounts yet.")
    end

    test "displays a message if no Salesforce accounts are connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
      assert has_element?(view, "p", "You haven't connected any Salesforce accounts yet.")
      assert has_element?(view, "a", "Connect Salesforce")
    end

    test "displays connected Salesforce accounts", %{conn: conn, user: user} do
      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          uid: "sf-org-user-123",
          email: "sf-user@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "li", "UID: sf-org-user-123")
      assert has_element?(view, "li", "(sf-user@example.com)")
      assert has_element?(view, "a", "Connect another Salesforce Account")
      assert has_element?(view, "#disconnect-salesforce-#{credential.id}")
    end

    test "disconnects connected Salesforce account", %{conn: conn, user: user} do
      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          uid: "sf-org-user-789",
          email: "sf-disconnect@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "#disconnect-salesforce-#{credential.id}")

      view
      |> element("#disconnect-salesforce-#{credential.id}")
      |> render_click()

      refute has_element?(view, "#disconnect-salesforce-#{credential.id}")
      assert has_element?(view, "p", "You haven't connected any Salesforce accounts yet.")
    end

    test "disconnects connected HubSpot account", %{conn: conn, user: user} do
      credential =
        hubspot_credential_fixture(%{
          user_id: user.id,
          uid: "hub-disconnect-123",
          email: "hub-disconnect@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "#disconnect-hubspot-#{credential.id}")

      view
      |> element("#disconnect-hubspot-#{credential.id}")
      |> render_click()

      refute has_element?(view, "#disconnect-hubspot-#{credential.id}")
      assert has_element?(view, "p", "You haven't connected any HubSpot accounts yet.")
    end

    test "disconnects connected Facebook account", %{conn: conn, user: user} do
      credential =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "facebook",
          uid: "facebook-disconnect-123",
          email: "facebook-disconnect@example.com"
        })

      _page_credential =
        facebook_page_credential_fixture(%{
          user_id: user.id,
          user_credential_id: credential.id,
          facebook_page_id: "page-disconnect-123",
          selected: true
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "#disconnect-facebook-#{credential.id}")

      view
      |> element("#disconnect-facebook-#{credential.id}")
      |> render_click()

      refute has_element?(view, "#disconnect-facebook-#{credential.id}")
      assert has_element?(view, "p", "You haven't connected any Facebook accounts yet.")
    end

    test "shows selected Facebook page id in connected Facebook row", %{conn: conn, user: user} do
      credential =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "facebook",
          uid: "facebook-page-visible-123",
          email: "facebook-page-visible@example.com"
        })

      _page_credential =
        facebook_page_credential_fixture(%{
          user_id: user.id,
          user_credential_id: credential.id,
          page_name: "My Test Page",
          facebook_page_id: "page-visible-123",
          selected: true
        })

      selected_page = SocialScribe.Accounts.get_user_selected_facebook_page_credential(user)
      assert selected_page
      assert selected_page.facebook_page_id == "page-visible-123"

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert render(view) =~ "page-visible-123"
    end

    test "disconnects connected LinkedIn account", %{conn: conn, user: user} do
      credential =
        user_credential_fixture(%{
          user_id: user.id,
          provider: "linkedin",
          uid: "linkedin-disconnect-123",
          email: "linkedin-disconnect@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "#disconnect-linkedin-#{credential.id}")

      view
      |> element("#disconnect-linkedin-#{credential.id}")
      |> render_click()

      refute has_element?(view, "#disconnect-linkedin-#{credential.id}")
      assert has_element?(view, "p", "You haven't connected any LinkedIn accounts yet.")
    end
  end
end
