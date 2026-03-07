defmodule SocialScribeWeb.UserSettingsLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.Bots

  @impl true
  def mount(_params, session, socket) do
    current_user = socket.assigns.current_user

    google_accounts = Accounts.list_user_credentials(current_user, provider: "google")

    linkedin_accounts = Accounts.list_user_credentials(current_user, provider: "linkedin")

    facebook_accounts = Accounts.list_user_credentials(current_user, provider: "facebook")
    selected_facebook_page = Accounts.get_user_selected_facebook_page_credential(current_user)

    selected_facebook_pages_by_credential =
      case selected_facebook_page do
        nil -> %{}
        page -> %{page.user_credential_id => page}
      end

    hubspot_accounts = Accounts.list_user_credentials(current_user, provider: "hubspot")
    salesforce_accounts = Accounts.list_user_credentials(current_user, provider: "salesforce")

    user_bot_preference =
      Bots.get_user_bot_preference(current_user.id) || %Bots.UserBotPreference{}

    changeset = Bots.change_user_bot_preference(user_bot_preference)

    socket =
      socket
      |> assign(:page_title, "User Settings")
      |> assign(:google_accounts, google_accounts)
      |> assign(:linkedin_accounts, linkedin_accounts)
      |> assign(:facebook_accounts, facebook_accounts)
      |> assign(:selected_facebook_page, selected_facebook_page)
      |> assign(:selected_facebook_pages_by_credential, selected_facebook_pages_by_credential)
      |> assign(:hubspot_accounts, hubspot_accounts)
      |> assign(:salesforce_accounts, salesforce_accounts)
      |> assign(:user_bot_preference, user_bot_preference)
      |> assign(:user_bot_preference_form, to_form(changeset))
      |> assign(:session_user_token, session["user_token"])

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      :facebook_pages ->
        facebook_page_options =
          socket.assigns.current_user
          |> Accounts.list_linked_facebook_pages()
          |> Enum.map(&{&1.page_name, &1.id})

        socket =
          socket
          |> assign(:facebook_page_options, facebook_page_options)
          |> assign(:facebook_page_form, to_form(%{"facebook_page" => ""}))

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    changeset =
      socket.assigns.user_bot_preference
      |> Bots.change_user_bot_preference(params)

    {:noreply, assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("update_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    params = Map.put(params, "user_id", socket.assigns.current_user.id)

    case create_or_update_user_bot_preference(socket.assigns.user_bot_preference, params) do
      {:ok, bot_preference} ->
        {:noreply,
         socket
         |> assign(:user_bot_preference, bot_preference)
         |> put_flash(:info, "Bot preference updated successfully")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  @impl true
  def handle_event("select_facebook_page", %{"facebook_page" => facebook_page}, socket) do
    facebook_page_credential = Accounts.get_facebook_page_credential!(facebook_page)

    case Accounts.update_facebook_page_credential(facebook_page_credential, %{selected: true}) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Facebook page selected successfully")
          |> push_navigate(to: ~p"/dashboard/settings")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    end
  end

  @impl true
  def handle_event("disconnect_account", %{"id" => id, "provider" => provider}, socket) do
    accounts = provider_accounts(socket, provider)

    case Enum.find(accounts, &("#{&1.id}" == id && &1.provider == provider)) do
      nil ->
        {:noreply, put_flash(socket, :error, "#{provider_label(provider)} account not found.")}

      credential ->
        case Accounts.disconnect_user_credential(credential) do
          {:ok, _deleted_credential} ->
            refreshed_accounts =
              Accounts.list_user_credentials(socket.assigns.current_user, provider: provider)

            socket =
              socket
              |> assign(provider_assign(provider), refreshed_accounts)
              |> put_flash(:info, "#{provider_label(provider)} account disconnected successfully.")

            if provider == "google" and Enum.empty?(refreshed_accounts) do
              maybe_delete_session_token(socket.assigns.session_user_token)

              {:noreply,
               socket
               |> put_flash(:info, "Last Google account disconnected. Please log in again.")
               |> redirect(to: ~p"/")}
            else
              {:noreply, socket}
            end

          {:error, _changeset} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Failed to disconnect #{provider_label(provider)} account."
             )}
        end
    end
  end

  defp create_or_update_user_bot_preference(bot_preference, params) do
    case bot_preference do
      %Bots.UserBotPreference{id: nil} ->
        Bots.create_user_bot_preference(params)

      bot_preference ->
        Bots.update_user_bot_preference(bot_preference, params)
    end
  end

  defp provider_accounts(socket, "google"), do: socket.assigns.google_accounts
  defp provider_accounts(socket, "hubspot"), do: socket.assigns.hubspot_accounts
  defp provider_accounts(socket, "salesforce"), do: socket.assigns.salesforce_accounts
  defp provider_accounts(socket, "facebook"), do: socket.assigns.facebook_accounts
  defp provider_accounts(socket, "linkedin"), do: socket.assigns.linkedin_accounts
  defp provider_accounts(_socket, _provider), do: []

  defp provider_assign("google"), do: :google_accounts
  defp provider_assign("hubspot"), do: :hubspot_accounts
  defp provider_assign("salesforce"), do: :salesforce_accounts
  defp provider_assign("facebook"), do: :facebook_accounts
  defp provider_assign("linkedin"), do: :linkedin_accounts

  defp provider_label("google"), do: "Google"
  defp provider_label("hubspot"), do: "HubSpot"
  defp provider_label("salesforce"), do: "Salesforce"
  defp provider_label("facebook"), do: "Facebook"
  defp provider_label("linkedin"), do: "LinkedIn"
  defp provider_label(provider), do: provider

  defp maybe_delete_session_token(token) when is_binary(token) do
    Accounts.delete_user_session_token(token)
  end

  defp maybe_delete_session_token(_), do: :ok
end
