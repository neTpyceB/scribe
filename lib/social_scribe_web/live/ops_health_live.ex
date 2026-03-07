defmodule SocialScribeWeb.OpsHealthLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.OpsHealth

  @refresh_interval_ms 15_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval_ms, :refresh_health)

    {:ok, refresh(socket)}
  end

  @impl true
  def handle_event("refresh_health", _params, socket) do
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
