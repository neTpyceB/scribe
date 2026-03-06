defmodule SocialScribeWeb.AuthControllerSalesforceTest do
  use SocialScribeWeb.ConnCase, async: true

  import SocialScribe.AccountsFixtures

  alias SocialScribe.Accounts
  alias SocialScribeWeb.AuthController

  describe "salesforce oauth callback" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "stores salesforce credential and redirects to settings", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        provider: :salesforce,
        uid: "org_123:user_456",
        info: %Ueberauth.Auth.Info{email: "sf@example.com"},
        credentials: %Ueberauth.Auth.Credentials{
          token: "access-token",
          refresh_token: "refresh-token",
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = AuthController.callback(conn, %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Salesforce account connected successfully!"

      credential = Accounts.get_user_salesforce_credential(user.id)
      assert credential.uid == "org_123:user_456"
      assert credential.token == "access-token"
      assert credential.refresh_token == "refresh-token"
      assert credential.email == "sf@example.com"
    end

    test "uses fallback email when salesforce identity has no email", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        provider: :salesforce,
        uid: "org_abc:user_xyz",
        info: %Ueberauth.Auth.Info{email: nil},
        credentials: %Ueberauth.Auth.Credentials{
          token: "access-token",
          refresh_token: "refresh-token",
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      _conn = AuthController.callback(conn, %{"provider" => "salesforce"})

      credential = Accounts.get_user_salesforce_credential(user.id)
      assert credential.email == "salesforce_org_abc:user_xyz@example.invalid"
    end
  end

  describe "salesforce oauth request" do
    setup do
      prev = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])

      Application.put_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
        client_id: "test-salesforce-client-id",
        client_secret: "test-salesforce-client-secret",
        site: "https://login.salesforce.com"
      )

      on_exit(fn ->
        Application.put_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, prev)
      end)

      :ok
    end

    test "request includes pkce parameters and stores verifier in session", %{conn: conn} do
      conn = get(conn, ~p"/auth/salesforce")

      location = redirected_to(conn, 302)

      assert String.contains?(location, "code_challenge=")
      assert String.contains?(location, "code_challenge_method=S256")

      assert get_session(conn, :salesforce_pkce_verifier)
             |> is_binary()
    end
  end
end
