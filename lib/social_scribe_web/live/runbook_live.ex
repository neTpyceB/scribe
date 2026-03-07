defmodule SocialScribeWeb.RunbookLive do
  use SocialScribeWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Runbook")}
  end
end
