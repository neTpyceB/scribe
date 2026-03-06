defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce OAuth strategy for Ueberauth.
  """

  import Plug.Conn

  use Ueberauth.Strategy,
    uid_field: :id,
    default_scope: "api refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Auth.Info

  @pkce_verifier_bytes 64

  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    code_verifier = generate_code_verifier()
    code_challenge = code_challenge(code_verifier)

    opts =
      [
        scope: scopes,
        redirect_uri: callback_url(conn),
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      ]
      |> with_optional(:prompt, conn)
      |> with_param(:prompt, conn)
      |> with_state_param(conn)

    conn
    |> put_session(:salesforce_pkce_verifier, code_verifier)
    |> redirect!(Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(opts))
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    code_verifier = get_session(conn, :salesforce_pkce_verifier)
    opts = [redirect_uri: callback_url(conn)]
    token_params = [code: code]

    token_params =
      if is_binary(code_verifier) and code_verifier != "" do
        Keyword.put(token_params, :code_verifier, code_verifier)
      else
        token_params
      end

    case Ueberauth.Strategy.Salesforce.OAuth.get_access_token(token_params, opts) do
      {:ok, token} ->
        conn
        |> delete_session(:salesforce_pkce_verifier)
        |> fetch_user(token)

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  def uid(conn) do
    uid_field = conn |> option(:uid_field) |> to_string()
    conn.private.salesforce_user[uid_field]
  end

  def credentials(conn) do
    token = conn.private.salesforce_token

    %Credentials{
      expires: !is_nil(token.expires_at),
      expires_at: token.expires_at,
      scopes: String.split(token.other_params["scope"] || "", " "),
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type
    }
  end

  def info(conn) do
    user = conn.private.salesforce_user

    %Info{
      email: user["email"],
      name: user["display_name"] || user["username"] || user["email"]
    }
  end

  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.salesforce_token,
        user: conn.private.salesforce_user
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :salesforce_token, token)

    case Ueberauth.Strategy.Salesforce.OAuth.get_identity(token) do
      {:ok, user} ->
        user = Map.put(user, "id", "#{user["organization_id"]}:#{user["user_id"]}")
        put_private(conn, :salesforce_user, user)

      {:error, reason} ->
        set_errors!(conn, [error("identity_error", reason)])
    end
  end

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp generate_code_verifier do
    @pkce_verifier_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp code_challenge(code_verifier) do
    code_verifier
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
