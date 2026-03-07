defmodule SocialScribeWeb.HomeLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Calendar
  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Bots

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :sync_calendars)

    admin_mode =
      socket.assigns.current_user.id
      |> Bots.get_user_bot_preference()
      |> case do
        %{is_admin_mode: true} -> true
        _ -> false
      end

    socket =
      socket
      |> assign(:page_title, "Upcoming Meetings")
      |> assign(:admin_mode, admin_mode)
      |> assign(:events, Calendar.list_upcoming_events(socket.assigns.current_user))
      |> assign(:loading, true)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_record", %{"id" => event_id}, socket) do
    event = Calendar.get_calendar_event!(event_id)

    {:ok, event} =
      Calendar.update_calendar_event(event, %{record_meeting: not event.record_meeting})

    send(self(), {:schedule_bot, event})

    updated_events =
      Enum.map(socket.assigns.events, fn e ->
        if e.id == event.id, do: event, else: e
      end)

    {:noreply, assign(socket, :events, updated_events)}
  end

  @impl true
  def handle_event("toggle_admin_mode", %{"enabled" => enabled}, socket) do
    admin_mode = enabled == "true"
    current_user = socket.assigns.current_user

    result =
      case Bots.get_user_bot_preference(current_user.id) do
        nil ->
          Bots.create_user_bot_preference(%{
            user_id: current_user.id,
            join_minute_offset: 2,
            is_admin_mode: admin_mode
          })

        preference ->
          Bots.update_user_bot_preference(preference, %{is_admin_mode: admin_mode})
      end

    case result do
      {:ok, _preference} ->
        {:noreply,
         socket
         |> assign(:admin_mode, admin_mode)
         |> push_navigate(to: ~p"/dashboard")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not update admin mode.")
         |> assign(:admin_mode, false)}
    end
  end

  @impl true
  def handle_info({:schedule_bot, event}, socket) do
    socket =
      if event.record_meeting do
        case Bots.create_and_dispatch_bot(socket.assigns.current_user, event) do
          {:ok, _} ->
            socket

          {:error, reason} ->
            Logger.error("Failed to create bot: #{inspect(reason)}")

            put_flash(
              socket,
              :error,
              "Failed to schedule recording bot. Please check your Recall API configuration."
            )
        end
      else
        case Bots.cancel_and_delete_bot(event) do
          {:ok, _} ->
            socket

          {:error, reason} ->
            Logger.error("Failed to cancel bot: #{inspect(reason)}")
            socket
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:sync_calendars, socket) do
    CalendarSyncronizer.sync_events_for_user(socket.assigns.current_user)

    events = Calendar.list_upcoming_events(socket.assigns.current_user)

    socket =
      socket
      |> assign(:events, events)
      |> assign(:loading, false)

    {:noreply, socket}
  end
end
