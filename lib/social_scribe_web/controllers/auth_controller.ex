defmodule SocialScribeWeb.AuthController do
  use SocialScribeWeb, :controller

  alias SocialScribe.FacebookApi
  alias SocialScribe.Accounts
  alias SocialScribe.Limits
  alias SocialScribe.RateLimiter
  alias SocialScribeWeb.UserAuth

  plug :rate_limit_auth_flow when action in [:request, :callback]
  plug :inject_facebook_scope when action == :request
  plug Ueberauth

  require Logger
  @linkedin_retry_session_key :linkedin_oauth_retry_once

  @doc """
  Handles the initial request to the provider (e.g., Google).
  Ueberauth's plug will redirect the user to the provider's consent page.
  """
  def request(conn, _params) do
    render(conn, :request)
  end

  @doc """
  Handles the callback from the provider after the user has granted consent.
  """
  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "google"
      })
      when not is_nil(user) do
    Logger.info("Google OAuth")
    Logger.info(auth)

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, _credential} ->
        conn
        |> put_flash(:info, "Google account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not add Google account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "linkedin"
      }) do
    Logger.info("LinkedIn OAuth")
    Logger.info(auth)

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, credential} ->
        Logger.info("credential")
        Logger.info(credential)

        conn
        |> delete_session(@linkedin_retry_session_key)
        |> put_flash(:info, "LinkedIn account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error(reason)

        conn
        |> delete_session(@linkedin_retry_session_key)
        |> put_flash(:error, "Could not add LinkedIn account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, %{"provider" => "linkedin"}) do
    retry_once? = get_session(conn, @linkedin_retry_session_key) == true

    cond do
      retry_once? ->
        Logger.warning(
          "LinkedIn OAuth failed after retry: #{inspect(linkedin_failure_messages(failure))}"
        )

        conn
        |> delete_session(@linkedin_retry_session_key)
        |> put_flash(:error, "LinkedIn connection failed. Please try again.")
        |> redirect(to: ~p"/dashboard/settings")

      transient_linkedin_failure?(failure) ->
        Logger.warning(
          "LinkedIn OAuth transient failure, retrying once: #{inspect(linkedin_failure_messages(failure))}"
        )

        conn
        |> put_session(@linkedin_retry_session_key, true)
        |> put_flash(:info, "LinkedIn authorization had a temporary issue. Retrying once...")
        |> redirect(to: ~p"/auth/linkedin")

      true ->
        Logger.warning("LinkedIn OAuth failure: #{inspect(linkedin_failure_messages(failure))}")

        conn
        |> delete_session(@linkedin_retry_session_key)
        |> put_flash(:error, "LinkedIn connection failed. Please try again.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "facebook"
      })
      when not is_nil(user) do
    Logger.info("Facebook OAuth")
    Logger.info(auth)

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, credential} ->
        case FacebookApi.fetch_user_pages(credential.uid, credential.token) do
          {:ok, facebook_pages} ->
            facebook_pages
            |> Enum.each(fn page ->
              Accounts.link_facebook_page(user, credential, page)
            end)

            if Enum.empty?(facebook_pages) do
              conn
              |> put_flash(
                :info,
                "Facebook connected, but no manageable Pages were returned. Ensure your app has page permissions and your user has access to a Page."
              )
              |> redirect(to: ~p"/dashboard/settings")
            else
              conn
              |> put_flash(
                :info,
                "Facebook account added successfully. Please select a page to connect."
              )
              |> redirect(to: ~p"/dashboard/settings/facebook_pages")
            end

          {:error, reason} ->
            Logger.warning("Failed to fetch Facebook pages after OAuth: #{inspect(reason)}")

            conn
            |> put_flash(
              :info,
              "Facebook connected, but page access is not available yet. Verify page permissions in Meta App settings and try Refresh Auth."
            )
            |> redirect(to: ~p"/dashboard/settings")
        end

      {:error, reason} ->
        Logger.error("Could not persist Facebook credential: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not add Facebook account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "hubspot"
      })
      when not is_nil(user) do
    Logger.info("HubSpot OAuth")
    Logger.info(inspect(auth))

    hub_id = to_string(auth.uid)

    credential_attrs = %{
      user_id: user.id,
      provider: "hubspot",
      uid: hub_id,
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }

    case Accounts.find_or_create_hubspot_credential(user, credential_attrs) do
      {:ok, _credential} ->
        Logger.info("HubSpot account connected for user #{user.id}, hub_id: #{hub_id}")

        conn
        |> put_flash(:info, "HubSpot account connected successfully!")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Failed to save HubSpot credential: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not connect HubSpot account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "salesforce"
      })
      when not is_nil(user) do
    salesforce_uid = to_string(auth.uid)
    email = auth.info.email || "salesforce_#{salesforce_uid}@example.invalid"

    credential_attrs = %{
      user_id: user.id,
      provider: "salesforce",
      uid: salesforce_uid,
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: email
    }

    case Accounts.find_or_create_salesforce_credential(user, credential_attrs) do
      {:ok, _credential} ->
        conn
        |> put_flash(:info, "Salesforce account connected successfully!")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, reason} ->
        Logger.error("Failed to save Salesforce credential: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not connect Salesforce account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    Logger.info("Google OAuth Login")
    Logger.info(auth)

    case Accounts.find_or_create_user_from_oauth(auth) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)

      {:error, reason} ->
        Logger.info("error")
        Logger.info(reason)

        conn
        |> put_flash(:error, "There was an error signing you in.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, _params) do
    Logger.error("OAuth Login")
    Logger.error(conn)

    conn
    |> put_flash(:error, "There was an error signing you in. Please try again.")
    |> redirect(to: ~p"/")
  end

  defp rate_limit_auth_flow(conn, _opts) do
    provider = conn.params["provider"] || "unknown"
    actor = rate_limit_actor(conn)
    action = Phoenix.Controller.action_name(conn)
    state_param = conn.params["state"]

    state_too_long? =
      is_binary(state_param) and String.length(state_param) > Limits.input(:oauth_state_max_chars)

    cond do
      state_too_long? ->
        conn
        |> put_flash(:error, "Authentication request is invalid. Please try again.")
        |> redirect(to: ~p"/")
        |> halt()

      true ->
        action_key =
          case action do
            :request -> :auth_start
            :callback -> :auth_callback
            _ -> :auth_start
          end

        rate_limit_key = "oauth:#{provider}:#{actor}:#{Atom.to_string(action)}"

        case RateLimiter.allow(action_key, rate_limit_key) do
          :ok ->
            conn

          {:error, retry_after_ms} ->
            retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

            conn
            |> put_flash(
              :error,
              "Too many authentication attempts. Please try again in #{retry_after_seconds} seconds."
            )
            |> redirect(to: ~p"/")
            |> halt()
        end
    end
  end

  defp rate_limit_actor(conn) do
    case conn.assigns[:current_user] do
      %{id: id} when is_integer(id) -> "user:#{id}"
      _ -> "ip:#{remote_ip(conn)}"
    end
  end

  defp remote_ip(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  rescue
    _ -> "unknown"
  end

  defp inject_facebook_scope(%{params: %{"provider" => "facebook"}} = conn, _opts) do
    case Map.get(conn.params, "scope") do
      scope when is_binary(scope) and scope != "" ->
        conn

      _ ->
        facebook_scope = System.get_env("FACEBOOK_OAUTH_SCOPE", "public_profile")
        %{conn | params: Map.put(conn.params, "scope", facebook_scope)}
    end
  end

  defp inject_facebook_scope(conn, _opts), do: conn

  defp transient_linkedin_failure?(%Ueberauth.Failure{errors: errors}) when is_list(errors) do
    Enum.any?(errors, fn
      %Ueberauth.Failure.Error{message_key: "OAuth2", message: message}
      when is_binary(message) ->
        String.contains?(String.downcase(message), "unknown")

      _ ->
        false
    end)
  end

  defp transient_linkedin_failure?(_), do: false

  defp linkedin_failure_messages(%Ueberauth.Failure{errors: errors}) when is_list(errors) do
    Enum.map(errors, fn
      %Ueberauth.Failure.Error{message_key: key, message: message} ->
        %{message_key: key, message: message}

      other ->
        inspect(other)
    end)
  end

  defp linkedin_failure_messages(other), do: inspect(other)
end
