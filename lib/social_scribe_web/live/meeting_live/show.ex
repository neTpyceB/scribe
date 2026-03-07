defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton

  import SocialScribeWeb.ModalComponents,
    only: [
      hubspot_modal: 1,
      suggestion_card: 1,
      modal_footer: 1,
      empty_state: 1,
      contact_select: 1
    ]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.HubspotSuggestions
  alias SocialScribe.InputGuard
  alias SocialScribe.RateLimiter
  alias SocialScribe.SalesforceSuggestions
  alias SocialScribe.SalesforceFields
  require Logger

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

      salesforce_field_mappings =
        Accounts.get_user_salesforce_field_mappings_map(socket.assigns.current_user.id)

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
        |> assign(:salesforce_dropdown_open, false)
        |> assign(:salesforce_query, "")
        |> assign(:salesforce_selecting_contact, false)
        |> assign(:salesforce_selecting_contact_id, nil)
        |> assign(:salesforce_suggestions, [])
        |> assign(:salesforce_selected_count, 0)
        |> assign(:salesforce_suggestions_loading, false)
        |> assign(:salesforce_updating, false)
        |> assign(:salesforce_field_mappings, salesforce_field_mappings)
        |> assign(:salesforce_mapping_options, salesforce_mapping_options())
        |> assign(:show_salesforce_mapping_editor, false)
        |> assign(:salesforce_mapping_error, nil)
        |> assign(:salesforce_mapping_saving, false)
        |> assign(:salesforce_mapping_source_field, nil)
        |> assign(
          :salesforce_mapping_form,
          to_form(%{"source_field" => "", "target_field" => ""}, as: :salesforce_mapping)
        )
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
    {:noreply,
     socket
     |> assign(:show_salesforce_modal, true)
     |> assign(:show_salesforce_mapping_editor, false)
     |> assign(:salesforce_mapping_error, nil)}
  end

  @impl true
  def handle_event("close_salesforce_review", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_salesforce_modal, false)
     |> assign(:show_salesforce_mapping_editor, false)
     |> assign(:salesforce_mapping_error, nil)}
  end

  @impl true
  def handle_event("open_salesforce_mapping", %{"field" => source_field}, socket) do
    if SalesforceFields.valid_field?(source_field) do
      target_field = Map.get(socket.assigns.salesforce_field_mappings, source_field, source_field)

      {:noreply,
       socket
       |> assign(:show_salesforce_mapping_editor, true)
       |> assign(:salesforce_mapping_error, nil)
       |> assign(:salesforce_mapping_source_field, source_field)
       |> assign(:salesforce_mapping_saving, false)
       |> assign(
         :salesforce_mapping_form,
         to_form(
           %{"source_field" => source_field, "target_field" => target_field},
           as: :salesforce_mapping
         )
       )}
    else
      {:noreply,
       assign(socket, :salesforce_search_error, "Unsupported Salesforce field mapping.")}
    end
  end

  @impl true
  def handle_event("close_salesforce_mapping", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_salesforce_mapping_editor, false)
     |> assign(:salesforce_mapping_error, nil)
     |> assign(:salesforce_mapping_saving, false)
     |> assign(:salesforce_mapping_source_field, nil)}
  end

  @impl true
  def handle_event("save_salesforce_mapping", %{"salesforce_mapping" => params}, socket) do
    source_field = String.trim(Map.get(params, "source_field", ""))
    target_field = String.trim(Map.get(params, "target_field", ""))

    cond do
      !SalesforceFields.valid_field?(source_field) ->
        {:noreply, assign(socket, :salesforce_mapping_error, "Invalid source field.")}

      !SalesforceFields.valid_field?(target_field) ->
        {:noreply, assign(socket, :salesforce_mapping_error, "Select a valid Salesforce field.")}

      true ->
        case Accounts.upsert_user_salesforce_field_mapping(
               socket.assigns.current_user.id,
               source_field,
               target_field
             ) do
          {:ok, _mapping} ->
            mappings =
              Map.put(socket.assigns.salesforce_field_mappings, source_field, target_field)

            socket =
              socket
              |> assign(:salesforce_field_mappings, mappings)
              |> assign(:show_salesforce_mapping_editor, false)
              |> assign(:salesforce_mapping_error, nil)
              |> assign(:salesforce_mapping_saving, false)
              |> assign(:salesforce_mapping_source_field, nil)
              |> put_flash(:info, "Salesforce field mapping updated.")

            if socket.assigns.salesforce_selected_contact do
              meeting = Meetings.get_meeting_with_details(socket.assigns.meeting.id)

              {suggestions, search_error} =
                case SalesforceSuggestions.generate_suggestions(
                       meeting,
                       socket.assigns.salesforce_selected_contact,
                       field_mappings: mappings
                     ) do
                  {:ok, suggestions} -> {suggestions, nil}
                  {:error, reason} -> {[], format_salesforce_suggestions_error(reason)}
                end

              {:noreply,
               socket
               |> assign(:meeting, meeting)
               |> assign(:salesforce_suggestions, suggestions)
               |> assign(:salesforce_selected_count, Enum.count(suggestions, & &1.apply))
               |> assign(:salesforce_search_error, search_error)}
            else
              {:noreply, socket}
            end

          {:error, _changeset} ->
            {:noreply,
             assign(
               socket,
               :salesforce_mapping_error,
               "Failed to save mapping. Please review fields and try again."
             )}
        end
    end
  end

  @impl true
  def handle_event(
        "salesforce_contact_search",
        %{"salesforce_search" => %{"query" => query}},
        socket
      ) do
    run_salesforce_contact_search(query, socket)
  end

  @impl true
  def handle_event(
        "salesforce_contact_search_input",
        %{"value" => query},
        socket
      ) do
    run_salesforce_contact_search(query, socket)
  end

  @impl true
  def handle_event("open_salesforce_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, :salesforce_dropdown_open, true)}
  end

  @impl true
  def handle_event("close_salesforce_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, :salesforce_dropdown_open, false)}
  end

  @impl true
  def handle_event("toggle_salesforce_contact_dropdown", _params, socket) do
    {:noreply,
     assign(socket, :salesforce_dropdown_open, !socket.assigns.salesforce_dropdown_open)}
  end

  @impl true
  def handle_event("select_salesforce_contact", %{"id" => contact_id}, socket) do
    credential = socket.assigns.salesforce_credential

    cond do
      is_nil(credential) ->
        {:noreply,
         assign(socket, :salesforce_search_error, "Salesforce account is not connected.")}

      true ->
        case rate_limit(socket, :ai_suggestions) do
          :ok ->
            send(
              self(),
              {:salesforce_select_contact, credential, contact_id, socket.assigns.meeting}
            )

            {:noreply,
             socket
             |> assign(:salesforce_search_error, nil)
             |> assign(:salesforce_dropdown_open, false)
             |> assign(:salesforce_query, "")
             |> assign(:salesforce_suggestions, [])
             |> assign(:salesforce_selected_count, 0)
             |> assign(:salesforce_selecting_contact, true)
             |> assign(:salesforce_selecting_contact_id, contact_id)
             |> assign(:salesforce_suggestions_loading, true)}

          {:error, retry_after_ms} when is_integer(retry_after_ms) ->
            retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

            {:noreply,
             assign(
               socket,
               :salesforce_search_error,
               "Too many suggestion requests. Try again in #{retry_after_seconds} seconds."
             )}
        end
    end
  end

  @impl true
  def handle_event("clear_salesforce_contact", _params, socket) do
    {:noreply,
     socket
     |> assign(:salesforce_selected_contact, nil)
     |> assign(:salesforce_contacts, [])
     |> assign(:salesforce_dropdown_open, false)
     |> assign(:salesforce_query, "")
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
  def handle_event("apply_salesforce_updates", params, socket) do
    credential = socket.assigns.salesforce_credential
    selected_contact = socket.assigns.salesforce_selected_contact

    cond do
      is_nil(credential) ->
        {:noreply,
         assign(socket, :salesforce_search_error, "Salesforce account is not connected.")}

      is_nil(selected_contact) ->
        {:noreply, assign(socket, :salesforce_search_error, "Select a Salesforce contact first.")}

      true ->
        values = Map.get(params, "values", %{})

        suggestions_with_values =
          Enum.map(socket.assigns.salesforce_suggestions, fn suggestion ->
            new_value = Map.get(values, suggestion.field, suggestion.new_value)
            %{suggestion | new_value: new_value}
          end)

        updates_list =
          suggestions_with_values
          |> Enum.filter(& &1.apply)
          |> Enum.map(fn s -> %{field: s.field, new_value: s.new_value, apply: true} end)

        cond do
          Enum.empty?(updates_list) ->
            {:noreply,
             assign(socket, :salesforce_search_error, "Select at least one field to update.")}

          true ->
            updates_map =
              updates_list
              |> Enum.reduce(%{}, fn update, acc ->
                Map.put(acc, update.field, update.new_value)
              end)

            with :ok <- rate_limit(socket, :crm_update),
                 {:ok, _sanitized_updates} <-
                   InputGuard.sanitize_crm_updates(updates_map, SalesforceFields.allowed_fields()) do
              send(
                self(),
                {:apply_salesforce_updates, credential, selected_contact.id, updates_list,
                 socket.assigns.meeting}
              )

              {:noreply,
               socket
               |> assign(:salesforce_suggestions, suggestions_with_values)
               |> assign(:salesforce_updating, true)
               |> assign(:salesforce_search_error, nil)}
            else
              {:error, retry_after_ms} when is_integer(retry_after_ms) ->
                retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

                {:noreply,
                 assign(
                   socket,
                   :salesforce_search_error,
                   "Too many update requests. Try again in #{retry_after_seconds} seconds."
                 )}

              {:error, {:unknown_fields, _fields}} ->
                {:noreply,
                 assign(
                   socket,
                   :salesforce_search_error,
                   "Some selected fields are not allowed for Salesforce updates."
                 )}

              {:error, {:too_many_fields, max_fields}} ->
                {:noreply,
                 assign(
                   socket,
                   :salesforce_search_error,
                   "Too many fields selected. Limit is #{max_fields} fields per update."
                 )}

              {:error, {:value_too_long, field, max_chars}} ->
                {:noreply,
                 assign(
                   socket,
                   :salesforce_search_error,
                   "Value for #{field} is too long (max #{max_chars} characters)."
                 )}

              {:error, :invalid_chars} ->
                {:noreply,
                 assign(
                   socket,
                   :salesforce_search_error,
                   "Update contains invalid characters."
                 )}
            end
        end
    end
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
          error: format_hubspot_error(reason),
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
         |> assign(:salesforce_searching, false)
         |> assign(:salesforce_dropdown_open, true)}

      {:error, reason} ->
        Logger.warning("Salesforce contact search failed: #{inspect(reason)}")

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
          case SalesforceSuggestions.generate_suggestions(
                 meeting,
                 contact,
                 field_mappings: socket.assigns.salesforce_field_mappings
               ) do
            {:ok, suggestions} ->
              {suggestions, nil}

            {:error, reason} ->
              {[], format_salesforce_suggestions_error(reason)}
          end

        refreshed_meeting = Meetings.get_meeting_with_details(meeting.id)

        {:noreply,
         socket
         |> assign(:meeting, refreshed_meeting)
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
  def handle_info(
        {:apply_salesforce_updates, credential, contact_id, updates_list, meeting},
        socket
      ) do
    case SalesforceApi.apply_updates(credential, contact_id, updates_list) do
      {:ok, :no_updates} ->
        {:noreply,
         socket
         |> assign(:salesforce_updating, false)
         |> assign(:salesforce_search_error, "Select at least one field to update.")}

      {:ok, _response} ->
        case SalesforceApi.get_contact(credential, contact_id) do
          {:ok, refreshed_contact} ->
            refreshed_meeting = Meetings.get_meeting_with_details(meeting.id)

            {suggestions, suggestion_error} =
              case SalesforceSuggestions.generate_suggestions(
                     refreshed_meeting,
                     refreshed_contact,
                     field_mappings: socket.assigns.salesforce_field_mappings
                   ) do
                {:ok, suggestions} -> {suggestions, nil}
                {:error, reason} -> {[], format_salesforce_suggestions_error(reason)}
              end

            {:noreply,
             socket
             |> assign(:salesforce_updating, false)
             |> assign(:meeting, refreshed_meeting)
             |> assign(:salesforce_selected_contact, refreshed_contact)
             |> assign(:salesforce_suggestions, suggestions)
             |> assign(:salesforce_selected_count, Enum.count(suggestions, & &1.apply))
             |> assign(:salesforce_search_error, suggestion_error)
             |> put_flash(
               :info,
               "Successfully updated #{length(updates_list)} field(s) in Salesforce."
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:salesforce_updating, false)
             |> assign(:salesforce_search_error, format_salesforce_error(reason))
             |> put_flash(:info, "Updated Salesforce, but failed to reload contact details.")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:salesforce_updating, false)
         |> assign(:salesforce_search_error, format_salesforce_update_error(reason))}
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
          error: format_hubspot_update_error(reason),
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

  defp format_salesforce_error({:invalid_input, {:too_long, max}}),
    do: "Search query is too long. Maximum #{max} characters."

  defp format_salesforce_error({:invalid_input, :invalid_chars}),
    do: "Search query contains invalid characters."

  defp format_salesforce_error({:upstream_unavailable, :econnrefused}),
    do: "Cannot reach Salesforce API. Check SALESFORCE_SITE and try again."

  defp format_salesforce_error({:upstream_timeout, _reason}),
    do: "Network error while contacting Salesforce. Please try again."

  defp format_salesforce_error({:upstream_unavailable, _reason}),
    do: "Network error while contacting Salesforce. Please try again."

  defp format_salesforce_error({:http_error, :econnrefused}),
    do: "Cannot reach Salesforce API. Check SALESFORCE_SITE and try again."

  defp format_salesforce_error({:http_error, :timeout}),
    do: "Network error while contacting Salesforce. Please try again."

  defp format_salesforce_error({:http_error, _reason}),
    do: "Network error while contacting Salesforce. Please try again."

  defp format_salesforce_error(_reason),
    do: "Failed to search Salesforce contacts."

  defp format_hubspot_error({:invalid_input, {:too_long, max}}),
    do: "Search query is too long. Maximum #{max} characters."

  defp format_hubspot_error({:invalid_input, :invalid_chars}),
    do: "Search query contains invalid characters."

  defp format_hubspot_error({:upstream_timeout, _}),
    do: "HubSpot request timed out. Please try again."

  defp format_hubspot_error({:upstream_unavailable, _}),
    do: "Network error while contacting HubSpot. Please try again."

  defp format_hubspot_error({:api_error, _status, _body}),
    do: "Failed to search contacts."

  defp format_hubspot_error(_), do: "Failed to search HubSpot contacts."

  defp format_salesforce_suggestions_error({:api_error, 429, _body}),
    do: "Gemini quota exceeded. Enable billing or wait for quota reset, then try again."

  defp format_salesforce_suggestions_error({:api_error, 404, _body}),
    do: "Configured Gemini model is unavailable. Update app model configuration and retry."

  defp format_salesforce_suggestions_error({:config_error, _message}),
    do: "Gemini API key is missing. Set GEMINI_API_KEY and restart the app."

  defp format_salesforce_suggestions_error(_reason),
    do: "Failed to generate Salesforce suggestions from transcript."

  defp format_salesforce_update_error({:api_error, 401, body}),
    do: format_salesforce_error({:api_error, 401, body})

  defp format_salesforce_update_error({:invalid_input, {:too_many_fields, max_fields}}),
    do: "Too many fields selected. Limit is #{max_fields}."

  defp format_salesforce_update_error({:invalid_input, {:value_too_long, field, max_chars}}),
    do: "Value for #{field} is too long (max #{max_chars} characters)."

  defp format_salesforce_update_error({:invalid_input, {:unknown_fields, _fields}}),
    do: "One or more selected fields are not allowed for Salesforce updates."

  defp format_salesforce_update_error({:api_error, _status, _body}),
    do: "Failed to update Salesforce contact."

  defp format_salesforce_update_error({:upstream_timeout, _reason}),
    do: "Salesforce request timed out. Please try again."

  defp format_salesforce_update_error({:upstream_unavailable, _reason}),
    do: "Network error while updating Salesforce. Please try again."

  defp format_salesforce_update_error({:http_error, :timeout}),
    do: "Salesforce request timed out. Please try again."

  defp format_salesforce_update_error({:http_error, _reason}),
    do: "Network error while updating Salesforce. Please try again."

  defp format_salesforce_update_error(_reason),
    do: "Failed to update Salesforce contact."

  defp format_hubspot_update_error({:invalid_input, {:unknown_fields, _fields}}),
    do: "One or more selected fields are not allowed for HubSpot updates."

  defp format_hubspot_update_error({:invalid_input, {:too_many_fields, max_fields}}),
    do: "Too many fields selected. Limit is #{max_fields}."

  defp format_hubspot_update_error({:invalid_input, {:value_too_long, field, max_chars}}),
    do: "Value for #{field} is too long (max #{max_chars} characters)."

  defp format_hubspot_update_error({:upstream_timeout, _}),
    do: "HubSpot request timed out. Please try again."

  defp format_hubspot_update_error({:upstream_unavailable, _}),
    do: "Network error while updating HubSpot. Please try again."

  defp format_hubspot_update_error({:api_error, _status, _body}),
    do: "HubSpot API rejected the update."

  defp format_hubspot_update_error(_), do: "Failed to update HubSpot contact."

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

  defp run_salesforce_contact_search(query, socket) do
    query = String.trim(query || "")
    credential = socket.assigns.salesforce_credential

    socket =
      socket
      |> assign(:salesforce_search_form, to_form(%{"query" => query}, as: :salesforce_search))
      |> assign(:salesforce_search_attempted, true)
      |> assign(:salesforce_search_error, nil)
      |> assign(:salesforce_search_notice, nil)
      |> assign(:salesforce_searching, query != "")
      |> assign(:salesforce_query, query)
      |> assign(:salesforce_selected_contact, nil)

    cond do
      is_nil(credential) ->
        {:noreply,
         socket
         |> assign(:salesforce_contacts, [])
         |> assign(:salesforce_searching, false)
         |> assign(:salesforce_search_error, "Salesforce account is not connected.")}

      query == "" ->
        {:noreply,
         socket
         |> assign(:salesforce_contacts, [])
         |> assign(:salesforce_searching, false)
         |> assign(:salesforce_dropdown_open, false)}

      true ->
        with {:ok, validated_query} <- InputGuard.validate_crm_search_query(query, min_len: 3),
             :ok <- rate_limit(socket, :crm_search) do
          send(self(), {:salesforce_search_contacts, credential, validated_query})
          {:noreply, socket}
        else
          {:error, {:too_short, min_len}} ->
            {:noreply,
             socket
             |> assign(:salesforce_contacts, [])
             |> assign(:salesforce_searching, false)
             |> assign(:salesforce_dropdown_open, true)
             |> assign(
               :salesforce_search_error,
               "Enter at least #{min_len} characters to search."
             )}

          {:error, {:too_long, max_len}} ->
            {:noreply,
             socket
             |> assign(:salesforce_contacts, [])
             |> assign(:salesforce_searching, false)
             |> assign(:salesforce_dropdown_open, true)
             |> assign(
               :salesforce_search_error,
               "Search query is too long. Maximum #{max_len} characters."
             )}

          {:error, :invalid_chars} ->
            {:noreply,
             socket
             |> assign(:salesforce_contacts, [])
             |> assign(:salesforce_searching, false)
             |> assign(:salesforce_dropdown_open, true)
             |> assign(:salesforce_search_error, "Search query contains invalid characters.")}

          {:error, retry_after_ms} when is_integer(retry_after_ms) ->
            retry_after_seconds = max(1, ceil(retry_after_ms / 1000))

            {:noreply,
             socket
             |> assign(:salesforce_contacts, [])
             |> assign(:salesforce_searching, false)
             |> assign(:salesforce_dropdown_open, true)
             |> assign(
               :salesforce_search_error,
               "Too many search requests. Try again in #{retry_after_seconds} seconds."
             )}
        end
    end
  end

  defp rate_limit(socket, action) do
    actor_key = "user:#{socket.assigns.current_user.id}:#{action}"

    case RateLimiter.allow(action, actor_key) do
      :ok -> :ok
      {:error, retry_after_ms} when is_integer(retry_after_ms) -> {:error, retry_after_ms}
    end
  end

  defp salesforce_mapping_options do
    SalesforceFields.allowed_fields()
    |> Enum.map(fn field -> {SalesforceFields.label(field), field} end)
  end

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
