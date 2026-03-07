defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Builds Salesforce contact update suggestions from meeting transcript AI output.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.Meetings
  alias SocialScribe.SalesforceFields

  @doc """
  Generates suggestions and merges with current Salesforce contact values.
  """
  def generate_suggestions(meeting, contact, opts \\ []) when is_map(contact) do
    field_mappings =
      opts
      |> Keyword.get(:field_mappings, %{})
      |> SalesforceFields.normalize_mappings()

    with {:ok, ai_suggestions} <- fetch_or_generate_ai_suggestions(meeting) do
      suggestions =
        ai_suggestions
        |> Enum.filter(&is_map/1)
        |> Enum.map(&normalize_suggestion(&1, field_mappings))
        |> Enum.filter(& &1)
        |> deduplicate_by_field()
        |> Enum.map(fn suggestion ->
          current_value = get_contact_field(contact, suggestion.field)
          has_change = normalize_string(current_value) != normalize_string(suggestion.new_value)

          suggestion
          |> Map.put(:current_value, current_value)
          |> Map.put(:has_change, has_change)
          |> Map.put(:apply, true)
        end)
        |> Enum.filter(& &1.has_change)

      {:ok, suggestions}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_or_generate_ai_suggestions(%{meeting_transcript: nil}) do
    {:error, :missing_transcript}
  end

  defp fetch_or_generate_ai_suggestions(meeting) do
    transcript = meeting.meeting_transcript
    transcript_hash = transcript_hash(transcript.content || %{})

    cached_hash = transcript.salesforce_ai_transcript_hash
    cached_suggestions = extract_cached_suggestions(transcript.salesforce_ai_suggestions)

    if cached_hash == transcript_hash and is_list(cached_suggestions) do
      {:ok, cached_suggestions}
    else
      case AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
        {:ok, ai_suggestions} when is_list(ai_suggestions) ->
          _ =
            Meetings.update_meeting_transcript(transcript, %{
              salesforce_ai_suggestions: %{items: ai_suggestions},
              salesforce_ai_transcript_hash: transcript_hash
            })

          {:ok, ai_suggestions}

        {:ok, _non_list} ->
          {:ok, []}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp normalize_suggestion(suggestion, field_mappings) do
    field = suggestion[:field] || suggestion["field"]
    value = suggestion[:value] || suggestion["value"]
    mapped_field = Map.get(field_mappings, field, field)

    with true <- is_binary(field),
         true <- is_binary(value),
         true <- SalesforceFields.valid_field?(mapped_field),
         true <- String.trim(value) != "" do
      %{
        field: mapped_field,
        source_field: field,
        label: SalesforceFields.label(mapped_field),
        new_value: String.trim(value),
        context: suggestion[:context] || suggestion["context"]
      }
    else
      _ -> nil
    end
  end

  defp deduplicate_by_field(suggestions) do
    suggestions
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.field)
    |> Enum.reverse()
  end

  defp get_contact_field(contact, field) do
    atom_key =
      case field do
        "firstname" -> :firstname
        "lastname" -> :lastname
        "email" -> :email
        "phone" -> :phone
        "mobilephone" -> :mobilephone
        "jobtitle" -> :jobtitle
        "address" -> :address
        "city" -> :city
        "state" -> :state
        "zip" -> :zip
        "country" -> :country
        "company" -> :company
        _ -> nil
      end

    if atom_key do
      Map.get(contact, atom_key) || Map.get(contact, field)
    else
      Map.get(contact, field)
    end
  end

  defp transcript_hash(content) do
    content
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp extract_cached_suggestions(%{items: items}) when is_list(items), do: items
  defp extract_cached_suggestions(%{"items" => items}) when is_list(items), do: items
  defp extract_cached_suggestions(_), do: []

  defp normalize_string(nil), do: ""
  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value), do: to_string(value)
end
