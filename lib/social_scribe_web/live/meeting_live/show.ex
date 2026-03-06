defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [hubspot_modal: 1, suggestion_card: 1, modal_footer: 1, empty_state: 1]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.HubspotSuggestions
  alias SocialScribe.SalesforceSuggestions

  @impl true
  def mount(%{"id" => meeting_id}, _session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      {:error, socket}
    else
      hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)

      salesforce_credential =
        Accounts.get_user_salesforce_credential(socket.assigns.current_user.id)

      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(:salesforce_credential, salesforce_credential)
        |> assign(:show_salesforce_modal, false)
        |> assign(:salesforce_search_form, to_form(%{"query" => ""}, as: :salesforce_search))
        |> assign(:salesforce_contacts, [])
        |> assign(:salesforce_selected_contact, nil)
        |> assign(:salesforce_search_error, nil)
        |> assign(:salesforce_search_notice, nil)
        |> assign(:salesforce_search_attempted, false)
        |> assign(:salesforce_searching, false)
        |> assign(:salesforce_selecting_contact, false)
        |> assign(:salesforce_selecting_contact_id, nil)
        |> assign(:salesforce_suggestions, [])
        |> assign(:salesforce_selected_count, 0)
        |> assign(:salesforce_suggestions_loading, false)
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => ""
          })
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_salesforce_review", _params, socket) do
    {:noreply, assign(socket, :show_salesforce_modal, true)}
  end

  @impl true
  def handle_event("close_salesforce_review", _params, socket) do
    {:noreply, assign(socket, :show_salesforce_modal, false)}
  end

  @impl true
  def handle_event("salesforce_contact_search", %{"salesforce_search" => %{"query" => query}}, socket) do
    query = String.trim(query || "")
    credential = socket.assigns.salesforce_credential

    socket =
      socket
      |> assign(:salesforce_search_form, to_form(%{"query" => query}, as: :salesforce_search))
      |> assign(:salesforce_search_attempted, true)
      |> assign(:salesforce_search_error, nil)
      |> assign(:salesforce_search_notice, nil)
      |> assign(:salesforce_searching, true)
      |> assign(:salesforce_selected_contact, nil)

    cond do
      is_nil(credential) ->
        {:noreply,
         socket
         |> assign(:salesforce_contacts, [])
         |> assign(:salesforce_searching, false)
         |> assign(:salesforce_search_error, "Salesforce account is not connected.")}

      String.length(query) < 3 ->
        {:noreply,
         socket
         |> assign(:salesforce_contacts, [])
         |> assign(:salesforce_searching, false)
         |> assign(:salesforce_search_error, "Enter at least 3 characters to search.")}

      true ->
        send(self(), {:salesforce_search_contacts, credential, query})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_salesforce_contact", %{"id" => contact_id}, socket) do
    credential = socket.assigns.salesforce_credential

    if is_nil(credential) do
      {:noreply, assign(socket, :salesforce_search_error, "Salesforce account is not connected.")}
    else
      send(self(), {:salesforce_select_contact, credential, contact_id, socket.assigns.meeting})

      {:noreply,
       socket
       |> assign(:salesforce_search_error, nil)
       |> assign(:salesforce_selected_contact, nil)
       |> assign(:salesforce_suggestions, [])
       |> assign(:salesforce_selected_count, 0)
       |> assign(:salesforce_selecting_contact, true)
       |> assign(:salesforce_selecting_contact_id, contact_id)
       |> assign(:salesforce_suggestions_loading, true)}
    end
  end

  @impl true
  def handle_event("clear_salesforce_contact", _params, socket) do
    {:noreply,
     socket
     |> assign(:salesforce_selected_contact, nil)
     |> assign(:salesforce_suggestions, [])
     |> assign(:salesforce_selected_count, 0)
     |> assign(:salesforce_selecting_contact, false)
     |> assign(:salesforce_selecting_contact_id, nil)
     |> assign(:salesforce_suggestions_loading, false)}
  end

  @impl true
  def handle_event("toggle_salesforce_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    checked_fields = Map.keys(applied_fields)

    suggestions =
      Enum.map(socket.assigns.salesforce_suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            value -> %{suggestion | new_value: value}
          end

        %{suggestion | apply: apply?}
      end)

    {:noreply,
     socket
     |> assign(:salesforce_suggestions, suggestions)
     |> assign(:salesforce_selected_count, Enum.count(suggestions, & &1.apply))}
  end

  @impl true
  def handle_event("apply_salesforce_updates", _params, socket) do
    {:noreply, put_flash(socket, :info, "Salesforce update action is the next implementation step.")}
  end

  @impl true
  def handle_info({:hubspot_search, query, credential}, socket) do
    case HubspotApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          contacts: contacts,
          searching: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to search contacts: #{inspect(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:salesforce_search_contacts, credential, query}, socket) do
    case SalesforceApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        shown_contacts = Enum.take(contacts, 10)

        notice =
          cond do
            length(contacts) > 10 ->
              "Returned too many contacts. Showing first 10; please narrow your search."

            length(contacts) == 10 ->
              "Many contacts returned. If needed, narrow your search further."

            true ->
              nil
          end

        {:noreply,
         socket
         |> assign(:salesforce_contacts, shown_contacts)
         |> assign(:salesforce_search_notice, notice)
         |> assign(:salesforce_searching, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:salesforce_contacts, [])
         |> assign(:salesforce_search_notice, nil)
         |> assign(:salesforce_searching, false)
         |> assign(:salesforce_search_error, format_salesforce_error(reason))}
    end
  end

  @impl true
  def handle_info({:salesforce_select_contact, credential, contact_id, meeting}, socket) do
    case SalesforceApi.get_contact(credential, contact_id) do
      {:ok, contact} ->
        {suggestions, search_error} =
          case SalesforceSuggestions.generate_suggestions(meeting, contact) do
            {:ok, suggestions} ->
              {suggestions, nil}

            {:error, reason} ->
              {[], format_salesforce_suggestions_error(reason)}
          end

        {:noreply,
         socket
         |> assign(:salesforce_selected_contact, contact)
          |> assign(:salesforce_suggestions, suggestions)
         |> assign(:salesforce_selected_count, Enum.count(suggestions, & &1.apply))
         |> assign(:salesforce_suggestions_loading, false)
         |> assign(:salesforce_selecting_contact, false)
         |> assign(:salesforce_selecting_contact_id, nil)
         |> assign(:salesforce_search_error, search_error)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:salesforce_suggestions_loading, false)
         |> assign(:salesforce_selecting_contact, false)
         |> assign(:salesforce_selecting_contact_id, nil)
         |> assign(:salesforce_search_error, format_salesforce_error(reason))}
    end
  end

  @impl true
  def handle_info({:generate_suggestions, contact, meeting, _credential}, socket) do
    case HubspotSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = HubspotSuggestions.merge_with_contact(suggestions, normalize_contact(contact))

        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to generate suggestions: #{inspect(reason)}",
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:apply_hubspot_updates, updates, contact, credential}, socket) do
    case HubspotApi.update_contact(credential, contact.id, updates) do
      {:ok, _updated_contact} ->
        socket =
          socket
          |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in HubSpot")
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to update contact: #{inspect(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  defp normalize_contact(contact) do
    # Contact is already formatted with atom keys from HubspotApi.format_contact
    contact
  end

  defp format_salesforce_error({:api_error, 401, body}) do
    if salesforce_invalid_session?(body) do
      "Salesforce session expired. Reconnect Salesforce in Settings and try again."
    else
      "Salesforce authentication failed. Reconnect Salesforce in Settings and try again."
    end
  end

  defp format_salesforce_error({:api_error, _status, _body}),
    do: "Failed to search Salesforce contacts."

  defp format_salesforce_error({:http_error, :econnrefused}),
    do: "Cannot reach Salesforce API. Check SALESFORCE_SITE and try again."

  defp format_salesforce_error({:http_error, _reason}),
    do: "Network error while contacting Salesforce. Please try again."

  defp format_salesforce_error(_reason),
    do: "Failed to search Salesforce contacts."

  defp format_salesforce_suggestions_error({:api_error, 429, _body}),
    do: "Gemini quota exceeded. Enable billing or wait for quota reset, then try again."

  defp format_salesforce_suggestions_error({:api_error, 404, _body}),
    do: "Configured Gemini model is unavailable. Update app model configuration and retry."

  defp format_salesforce_suggestions_error({:config_error, _message}),
    do: "Gemini API key is missing. Set GEMINI_API_KEY and restart the app."

  defp format_salesforce_suggestions_error(_reason),
    do: "Failed to generate Salesforce suggestions from transcript."

  defp salesforce_invalid_session?(body) when is_list(body) do
    Enum.any?(body, fn
      %{"errorCode" => "INVALID_SESSION_ID"} -> true
      %{errorCode: "INVALID_SESSION_ID"} -> true
      _ -> false
    end)
  end

  defp salesforce_invalid_session?(body) when is_map(body) do
    Map.get(body, "errorCode") == "INVALID_SESSION_ID" ||
      Map.get(body, :errorCode) == "INVALID_SESSION_ID"
  end

  defp salesforce_invalid_session?(_), do: false

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {segment["speaker"] || "Unknown Speaker"}:
              </span>
              {Enum.map_join(segment["words"] || [], " ", & &1["text"])}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
