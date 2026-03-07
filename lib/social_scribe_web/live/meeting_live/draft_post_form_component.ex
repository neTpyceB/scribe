defmodule SocialScribeWeb.MeetingLive.DraftPostFormComponent do
  use SocialScribeWeb, :live_component
  import SocialScribeWeb.ClipboardButton

  alias SocialScribe.InputGuard
  alias SocialScribe.Poster
  alias SocialScribe.RateLimiter

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Draft Post
        <:subtitle>Generate a post based on insights from this meeting.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="draft-post-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="post"
      >
        <.input
          field={@form[:generated_content]}
          type="textarea"
          value={@automation_result.generated_content}
          class="bg-black"
        />

        <:actions>
          <.clipboard_button id="draft-post-button" text={@form[:generated_content].value} />

          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click={JS.patch(~p"/dashboard/meetings/#{@meeting}")}
              phx-disable-with="Cancelling..."
              class="bg-slate-100 text-slate-700 leading-none py-2 px-4 rounded-md"
            >
              Cancel
            </button>
            <.button type="submit" phx-disable-with="Posting...">Post</.button>
          </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(
        form: to_form(%{"generated_content" => assigns.automation_result.generated_content})
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, form: to_form(params))}
  end

  @impl true
  def handle_event("post", %{"generated_content" => generated_content}, socket) do
    with {:ok, _validated} <- InputGuard.validate_social_post(generated_content),
         :ok <-
           RateLimiter.allow(:crm_update, "user:#{socket.assigns.current_user.id}:social_post") do
      case Poster.post_on_social_media(
             socket.assigns.automation.platform,
             generated_content,
             socket.assigns.current_user
           ) do
        {:ok, _} ->
          socket =
            socket
            |> put_flash(:info, "Post successful")
            |> push_patch(to: socket.assigns.patch)

          {:noreply, socket}

        {:error, error} ->
          socket =
            socket
            |> put_flash(:error, error)
            |> push_patch(to: socket.assigns.patch)

          {:noreply, socket}
      end
    else
      {:error, {:too_long, max_len}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Post is too long. Maximum #{max_len} characters.")
         |> push_patch(to: socket.assigns.patch)}

      {:error, retry_after_ms} ->
        retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

        {:noreply,
         socket
         |> put_flash(
           :error,
           "Too many posting attempts. Try again in #{retry_after_seconds} seconds."
         )
         |> push_patch(to: socket.assigns.patch)}
    end
  end
end
