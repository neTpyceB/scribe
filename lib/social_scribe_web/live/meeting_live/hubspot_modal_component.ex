defmodule SocialScribeWeb.MeetingLive.HubspotModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  alias SocialScribe.HubspotApi
  alias SocialScribe.InputGuard
  alias SocialScribe.RateLimiter

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "hubspot-modal-wrapper" end)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">
          Update in HubSpot
        </h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          Here are suggested updates to sync with your integrations based on this
          <span class="block">meeting</span>
        </p>
      </div>

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@searching}
        open={@dropdown_open}
        query={@query}
        target={@myself}
        error={@error}
      />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true

  defp suggestions_section(assigns) do
    assigns = assign(assigns, :selected_count, Enum.count(assigns.suggestions, & &1.apply))

    ~H"""
    <div class="space-y-4">
      <%= if @loading do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Generating suggestions...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No update suggestions found from this meeting."
            submessage="The AI didn't detect any new contact information in the transcript."
          />
        <% else %>
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto pr-2">
              <.suggestion_card :for={suggestion <- @suggestions} suggestion={suggestion} />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update HubSpot"
              submit_class="bg-hubspot-button hover:bg-hubspot-button-hover"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"1 object, #{@selected_count} fields in 1 integration selected to update"}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)
      |> assign_new(:step, fn -> :search end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:selected_contact, fn -> nil end)
      |> assign_new(:suggestions, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:current_user_id, fn -> nil end)

    {:ok, socket}
  end

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions})
       when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query || "")

    case InputGuard.validate_crm_search_query(query, min_len: 2) do
      {:ok, validated_query} when validated_query == "" ->
        {:noreply, assign(socket, query: "", contacts: [], dropdown_open: false, error: nil)}

      {:ok, validated_query} ->
        case rate_limit(socket, :crm_search) do
          :ok ->
            socket =
              assign(socket,
                searching: true,
                error: nil,
                query: validated_query,
                dropdown_open: true
              )

            send(self(), {:hubspot_search, validated_query, socket.assigns.credential})
            {:noreply, socket}

          {:error, retry_after_ms} when is_integer(retry_after_ms) ->
            retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

            {:noreply,
             assign(
               socket,
               error: "Too many HubSpot searches. Try again in #{retry_after_seconds} seconds.",
               searching: false,
               dropdown_open: true
             )}
        end

      {:error, {:too_short, min_len}} ->
        {:noreply,
         assign(socket,
           query: query,
           contacts: [],
           dropdown_open: query != "",
           error: "Enter at least #{min_len} characters to search."
         )}

      {:error, {:too_long, max_len}} ->
        {:noreply,
         assign(socket,
           contacts: [],
           searching: false,
           dropdown_open: true,
           error: "Search query is too long. Maximum #{max_len} characters."
         )}

      {:error, :invalid_chars} ->
        {:noreply,
         assign(socket,
           contacts: [],
           searching: false,
           dropdown_open: true,
           error: "Search query contains invalid characters."
         )}
    end
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      socket = assign(socket, dropdown_open: true, searching: true)

      query =
        "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"

      send(self(), {:hubspot_search, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      case rate_limit(socket, :ai_suggestions) do
        :ok ->
          socket =
            assign(socket,
              loading: true,
              selected_contact: contact,
              error: nil,
              dropdown_open: false,
              query: "",
              suggestions: []
            )

          send(
            self(),
            {:generate_suggestions, contact, socket.assigns.meeting, socket.assigns.credential}
          )

          {:noreply, socket}

        {:error, retry_after_ms} when is_integer(retry_after_ms) ->
          retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

          {:noreply,
           assign(
             socket,
             error: "Too many suggestion requests. Try again in #{retry_after_seconds} seconds."
           )}
      end
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply,
     assign(socket,
       step: :search,
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       contacts: [],
       query: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    checked_fields = Map.keys(applied_fields)

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            new_value -> %{suggestion | new_value: new_value}
          end

        %{suggestion | apply: apply?}
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, ""))
      end)

    with :ok <- rate_limit(socket, :crm_update),
         {:ok, sanitized_updates} <-
           InputGuard.sanitize_crm_updates(updates, HubspotApi.allowed_update_fields()) do
      socket = assign(socket, loading: true, error: nil)

      send(
        self(),
        {:apply_hubspot_updates, sanitized_updates, socket.assigns.selected_contact,
         socket.assigns.credential}
      )

      {:noreply, socket}
    else
      {:error, retry_after_ms} when is_integer(retry_after_ms) ->
        retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

        {:noreply,
         assign(
           socket,
           loading: false,
           error: "Too many update requests. Try again in #{retry_after_seconds} seconds."
         )}

      {:error, {:unknown_fields, _fields}} ->
        {:noreply,
         assign(socket, loading: false, error: "One or more selected fields are not allowed.")}

      {:error, {:too_many_fields, max_fields}} ->
        {:noreply,
         assign(socket,
           loading: false,
           error: "Too many fields selected. Limit is #{max_fields}."
         )}

      {:error, {:value_too_long, field, max_chars}} ->
        {:noreply,
         assign(
           socket,
           loading: false,
           error: "Value for #{field} is too long (max #{max_chars} characters)."
         )}

      {:error, :invalid_chars} ->
        {:noreply, assign(socket, loading: false, error: "Update contains invalid characters.")}
    end
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end

  defp rate_limit(socket, action) do
    actor =
      case socket.assigns.current_user_id do
        id when is_integer(id) -> "user:#{id}"
        _ -> "anon:hubspot_modal"
      end

    RateLimiter.allow(action, "#{actor}:#{action}")
  end
end
