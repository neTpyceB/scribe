defmodule SocialScribeWeb.AuthControllerLinkedInTest do
  use SocialScribeWeb.ConnCase, async: true

  import SocialScribe.AccountsFixtures

  alias SocialScribeWeb.AuthController

  describe "linkedin oauth callback failure handling" do
    test "retries once on transient oauth2 unknown error", %{conn: conn} do
      failure = %Ueberauth.Failure{
        provider: :linkedin,
        strategy: Ueberauth.Strategy.LinkedIn,
        errors: [%Ueberauth.Failure.Error{message_key: "OAuth2", message: "Unknown error"}]
      }

      conn =
        conn
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> assign(:ueberauth_failure, failure)

      conn = AuthController.callback(conn, %{"provider" => "linkedin"})

      assert redirected_to(conn) == ~p"/auth/linkedin"
      assert get_session(conn, :linkedin_oauth_retry_once) == true
    end

    test "stops retrying after one attempt and redirects to settings", %{conn: conn} do
      failure = %Ueberauth.Failure{
        provider: :linkedin,
        strategy: Ueberauth.Strategy.LinkedIn,
        errors: [%Ueberauth.Failure.Error{message_key: "OAuth2", message: "Unknown error"}]
      }

      conn =
        conn
        |> init_test_session(%{linkedin_oauth_retry_once: true})
        |> Phoenix.Controller.fetch_flash([])
        |> assign(:ueberauth_failure, failure)

      conn = AuthController.callback(conn, %{"provider" => "linkedin"})

      assert redirected_to(conn) == ~p"/dashboard/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "LinkedIn connection failed. Please try again."

      refute get_session(conn, :linkedin_oauth_retry_once)
    end
  end

  describe "linkedin oauth callback success handling" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "clears retry marker on successful connect", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        provider: :linkedin,
        uid: "urn:li:person:test123",
        info: %Ueberauth.Auth.Info{email: "linkedin@example.com", name: "LinkedIn User"},
        extra: %Ueberauth.Auth.Extra{raw_info: %{user: %{"sub" => "test123"}}},
        credentials: %Ueberauth.Auth.Credentials{
          token: "linkedin-token",
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
        }
      }

      conn =
        conn
        |> init_test_session(%{linkedin_oauth_retry_once: true})
        |> Phoenix.Controller.fetch_flash([])
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = AuthController.callback(conn, %{"provider" => "linkedin"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      refute get_session(conn, :linkedin_oauth_retry_once)
    end
  end
end
