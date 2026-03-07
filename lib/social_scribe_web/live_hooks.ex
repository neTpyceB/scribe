defmodule SocialScribeWeb.LiveHooks do
  use SocialScribeWeb, :verified_routes

  alias SocialScribe.Bots

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3, redirect: 2]

  def on_mount(:assign_current_path, _params, _session, socket) do
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, &assign_current_path/3)

    {:cont, socket}
  end

  def on_mount(:require_admin_mode, _params, _session, socket) do
    if admin_mode_enabled?(socket.assigns.current_user.id) do
      {:cont, assign(socket, :admin_mode, true)}
    else
      socket =
        socket
        |> assign(:admin_mode, false)
        |> put_flash(:error, "Enable \"I am admin\" on Home to access this page.")
        |> redirect(to: ~p"/dashboard")

      {:halt, socket}
    end
  end

  defp assign_current_path(_params, uri, socket) do
    uri = URI.parse(uri)

    admin_mode =
      case socket.assigns[:current_user] do
        %{id: user_id} -> admin_mode_enabled?(user_id)
        _ -> false
      end

    {:cont, socket |> assign(:current_path, uri.path) |> assign(:admin_mode, admin_mode)}
  end

  defp admin_mode_enabled?(user_id) do
    case Bots.get_user_bot_preference(user_id) do
      %{is_admin_mode: true} -> true
      _ -> false
    end
  end
end
