defmodule SocialScribeWeb.OpsHealthLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.OpsHealth

  @refresh_interval_ms 15_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval_ms, :refresh_health)

    {:ok, socket |> assign(:action_result, nil) |> refresh()}
  end

  @impl true
  def handle_event("refresh_health", _params, socket) do
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("run_bot_poller", _params, socket) do
    socket =
      case OpsHealth.replay_bot_poller() do
        {:ok, _job} ->
          socket
          |> assign(:action_result, %{type: :info, message: "Bot poller job triggered."})
          |> put_flash(:info, "Bot poller job triggered.")

        {:error, reason} ->
          socket
          |> assign(:action_result, %{type: :error, message: "Failed to trigger bot poller."})
          |> put_flash(:error, "Failed to trigger bot poller: #{inspect(reason)}")
      end

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("rerun_latest_ai", _params, socket) do
    socket =
      case OpsHealth.rerun_latest_meeting_ai(socket.assigns.current_user) do
        {:ok, _job} ->
          socket
          |> assign(:action_result, %{
            type: :info,
            message: "AI re-run queued for latest meeting."
          })
          |> put_flash(:info, "AI re-run queued for latest meeting.")

        {:error, :no_meeting} ->
          socket
          |> assign(:action_result, %{type: :error, message: "No meeting available to re-run AI."})
          |> put_flash(:error, "No meeting available to re-run AI.")

        {:error, reason} ->
          socket
          |> assign(:action_result, %{type: :error, message: "Failed to queue AI re-run."})
          |> put_flash(:error, "Failed to queue AI re-run: #{inspect(reason)}")
      end

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("reset_salesforce_cache", _params, socket) do
    socket =
      case OpsHealth.reset_latest_salesforce_cache(socket.assigns.current_user) do
        {:ok, _transcript} ->
          socket
          |> assign(:action_result, %{type: :info, message: "Salesforce suggestion cache reset."})
          |> put_flash(:info, "Salesforce suggestion cache reset.")

        {:error, :no_meeting} ->
          socket
          |> assign(:action_result, %{
            type: :error,
            message: "No meeting available for cache reset."
          })
          |> put_flash(:error, "No meeting available for cache reset.")

        {:error, :no_transcript} ->
          socket
          |> assign(:action_result, %{type: :error, message: "Latest meeting has no transcript."})
          |> put_flash(:error, "Latest meeting has no transcript.")

        {:error, reason} ->
          socket
          |> assign(:action_result, %{type: :error, message: "Failed to reset Salesforce cache."})
          |> put_flash(:error, "Failed to reset Salesforce cache: #{inspect(reason)}")
      end

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_info(:refresh_health, socket) do
    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    socket
    |> assign(:page_title, "Ops Health")
    |> assign(:health, OpsHealth.snapshot(socket.assigns.current_user))
  end
end
