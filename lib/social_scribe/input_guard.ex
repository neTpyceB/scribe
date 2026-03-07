defmodule SocialScribe.InputGuard do
  @moduledoc """
  Validates and sanitizes user-provided input before external API calls.
  """

  alias SocialScribe.Limits

  @spec validate_crm_search_query(String.t(), keyword()) ::
          {:ok, String.t()}
          | {:error,
             {:too_short, non_neg_integer()} | {:too_long, pos_integer()} | :invalid_chars}
  def validate_crm_search_query(query, opts \\ []) when is_binary(query) do
    min_len = Keyword.get(opts, :min_len, 0)
    max_len = Limits.input(:crm_search_max_chars)
    trimmed = String.trim(query)
    len = String.length(trimmed)

    cond do
      contains_control_chars?(trimmed) ->
        {:error, :invalid_chars}

      len > max_len ->
        {:error, {:too_long, max_len}}

      len > 0 and len < min_len ->
        {:error, {:too_short, min_len}}

      true ->
        {:ok, trimmed}
    end
  end

  @spec validate_social_post(String.t()) ::
          {:ok, String.t()} | {:error, {:too_long, pos_integer()}}
  def validate_social_post(content) when is_binary(content) do
    max_len = Limits.input(:social_post_max_chars)

    if String.length(content) > max_len do
      {:error, {:too_long, max_len}}
    else
      {:ok, content}
    end
  end

  @spec sanitize_crm_updates(map(), MapSet.t() | [String.t()]) ::
          {:ok, map()}
          | {:error,
             {:unknown_fields, [String.t()]}
             | {:too_many_fields, pos_integer()}
             | {:value_too_long, String.t(), pos_integer()}
             | :invalid_chars}
  def sanitize_crm_updates(updates, allowed_fields) when is_map(updates) do
    allowed_set =
      case allowed_fields do
        %MapSet{} = set -> set
        list when is_list(list) -> MapSet.new(list)
      end

    max_fields = Limits.input(:crm_update_max_fields)
    max_value_len = Limits.input(:crm_field_value_max_chars)

    if map_size(updates) > max_fields do
      {:error, {:too_many_fields, max_fields}}
    else
      unknown_fields =
        updates
        |> Map.keys()
        |> Enum.map(&normalize_field/1)
        |> Enum.reject(&MapSet.member?(allowed_set, &1))

      cond do
        unknown_fields != [] ->
          {:error, {:unknown_fields, Enum.uniq(unknown_fields)}}

        true ->
          updates
          |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
            field = normalize_field(key)
            value_text = normalize_value(value)

            cond do
              contains_control_chars?(value_text) ->
                {:halt, {:error, :invalid_chars}}

              String.length(value_text) > max_value_len ->
                {:halt, {:error, {:value_too_long, field, max_value_len}}}

              true ->
                {:cont, {:ok, Map.put(acc, field, value_text)}}
            end
          end)
      end
    end
  end

  def sanitize_crm_updates(_, _), do: {:error, :invalid_chars}

  defp normalize_field(field) when is_atom(field),
    do: field |> Atom.to_string() |> String.downcase()

  defp normalize_field(field) when is_binary(field),
    do: field |> String.trim() |> String.downcase()

  defp normalize_field(field), do: field |> to_string() |> String.downcase()

  defp normalize_value(nil), do: ""
  defp normalize_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_value(value), do: value |> to_string() |> String.trim()

  defp contains_control_chars?(value) when is_binary(value) do
    String.match?(value, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/)
  end
end
