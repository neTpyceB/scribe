defmodule SocialScribeWeb.AnalyticsLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Analytics

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Analytics")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    window_days =
      params
      |> Map.get("window")
      |> parse_window()

    analytics = Analytics.snapshot(socket.assigns.current_user, window_days)

    {:noreply,
     socket
     |> assign(:window_days, window_days)
     |> assign(:supported_windows, Analytics.supported_windows())
     |> assign(:analytics, analytics)}
  end

  defp parse_window(nil), do: Analytics.normalize_window(nil)

  defp parse_window(window) when is_binary(window) do
    case Integer.parse(window) do
      {value, ""} -> Analytics.normalize_window(value)
      _ -> Analytics.normalize_window(nil)
    end
  end
end
