defmodule SocialScribeWeb.AuthControllerFacebookTest do
  use SocialScribeWeb.ConnCase, async: true

  import Mox
  import SocialScribe.AccountsFixtures

  alias SocialScribe.Accounts
  alias SocialScribeWeb.AuthController

  setup :verify_on_exit!

  describe "facebook oauth callback" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "stores facebook credential even when provider email is missing", %{conn: conn, user: user} do
      SocialScribe.FacebookApiMock
      |> expect(:fetch_user_pages, fn "facebook-uid-123", "fb-token" ->
        {:ok, []}
      end)

      auth = %Ueberauth.Auth{
        provider: :facebook,
        uid: "facebook-uid-123",
        info: %Ueberauth.Auth.Info{email: nil, name: "FB User"},
        credentials: %Ueberauth.Auth.Credentials{
          token: "fb-token",
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = AuthController.callback(conn, %{"provider" => "facebook"})

      assert redirected_to(conn) == ~p"/dashboard/settings"

      credential = Accounts.get_user_credential(user, "facebook")
      assert credential.uid == "facebook-uid-123"
      assert credential.token == "fb-token"
      assert is_nil(credential.email)
    end

    test "redirects to page selection when pages are returned", %{conn: conn, user: user} do
      SocialScribe.FacebookApiMock
      |> expect(:fetch_user_pages, fn "facebook-uid-456", "fb-token-2" ->
        {:ok,
         [
           %{
             id: "page_1",
             name: "My Page",
             category: "Business",
             page_access_token: "page-token-1"
           }
         ]}
      end)

      auth = %Ueberauth.Auth{
        provider: :facebook,
        uid: "facebook-uid-456",
        info: %Ueberauth.Auth.Info{email: "user@example.com", name: "FB User"},
        credentials: %Ueberauth.Auth.Credentials{
          token: "fb-token-2",
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, auth)

      conn = AuthController.callback(conn, %{"provider" => "facebook"})

      assert redirected_to(conn) == ~p"/dashboard/settings/facebook_pages"
      assert length(Accounts.list_linked_facebook_pages(user)) == 1
    end
  end
end
