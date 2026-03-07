defmodule SocialScribe.Limits do
  @moduledoc """
  Runtime accessors for security/performance limits configured in `config/runtime.exs`.
  """

  @default_inputs %{
    transcript_max_chars: 2_000_000,
    ai_prompt_max_chars: 2_200_000,
    crm_search_max_chars: 120,
    crm_update_max_fields: 25,
    crm_field_value_max_chars: 2_000,
    social_post_max_chars: 3_000,
    oauth_state_max_chars: 200
  }

  @default_rate_limits %{
    auth_start_window_ms: 60_000,
    auth_start_max_requests: 20,
    auth_callback_window_ms: 60_000,
    auth_callback_max_requests: 30,
    crm_search_window_ms: 60_000,
    crm_search_max_requests: 40,
    crm_update_window_ms: 60_000,
    crm_update_max_requests: 20,
    ai_suggestions_window_ms: 60_000,
    ai_suggestions_max_requests: 12
  }

  @default_http %{
    default_connect_timeout_ms: 5_000,
    default_recv_timeout_ms: 20_000,
    gemini_recv_timeout_ms: 180_000,
    retry_attempts: 2,
    retry_backoff_base_ms: 250,
    retry_backoff_max_ms: 2_000
  }

  @spec input(atom()) :: integer()
  def input(key) do
    get_map(:inputs, @default_inputs)
    |> Map.get(key, Map.fetch!(@default_inputs, key))
  end

  @spec http(atom()) :: integer()
  def http(key) do
    get_map(:http, @default_http)
    |> Map.get(key, Map.fetch!(@default_http, key))
  end

  @spec rate_limit(atom()) ::
          {:ok, %{window_ms: pos_integer(), max_requests: pos_integer()}} | :error
  def rate_limit(:auth_start),
    do: ok_rate(:auth_start_window_ms, :auth_start_max_requests)

  def rate_limit(:auth_callback),
    do: ok_rate(:auth_callback_window_ms, :auth_callback_max_requests)

  def rate_limit(:crm_search),
    do: ok_rate(:crm_search_window_ms, :crm_search_max_requests)

  def rate_limit(:crm_update),
    do: ok_rate(:crm_update_window_ms, :crm_update_max_requests)

  def rate_limit(:ai_suggestions),
    do: ok_rate(:ai_suggestions_window_ms, :ai_suggestions_max_requests)

  def rate_limit(_), do: :error

  defp ok_rate(window_key, max_key) do
    rates = get_map(:rate_limits, @default_rate_limits)

    {:ok,
     %{
       window_ms: Map.get(rates, window_key, Map.fetch!(@default_rate_limits, window_key)),
       max_requests: Map.get(rates, max_key, Map.fetch!(@default_rate_limits, max_key))
     }}
  end

  defp get_map(key, defaults) do
    limits =
      :social_scribe
      |> Application.get_env(:limits, %{})
      |> normalize_container()

    limits
    |> Map.get(key, %{})
    |> normalize_container()
    |> Map.merge(defaults, fn _k, configured, _default -> configured end)
  end

  defp normalize_container(value) when is_map(value), do: value
  defp normalize_container(value) when is_list(value), do: Map.new(value)
  defp normalize_container(_), do: %{}
end
