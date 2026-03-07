defmodule SocialScribeWeb.UserSessionController do
  use SocialScribeWeb, :controller

  alias SocialScribe.Accounts
  alias SocialScribe.RateLimiter
  alias SocialScribeWeb.UserAuth

  plug :rate_limit_login_attempts when action in [:create]

  def new(conn, _params) do
    redirect(conn, to: ~p"/")
  end

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/dashboard/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # TODO: Add Google OAuth login

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/")
    end
  end

  defp rate_limit_login_attempts(conn, _opts) do
    key = "password_login:ip:#{remote_ip(conn)}"

    case RateLimiter.allow(:auth_start, key) do
      :ok ->
        conn

      {:error, retry_after_ms} ->
        retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

        conn
        |> put_flash(
          :error,
          "Too many login attempts. Please try again in #{retry_after_seconds} seconds."
        )
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  defp remote_ip(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  rescue
    _ -> "unknown"
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
