defmodule SocialScribe.RateLimiter do
  @moduledoc """
  Lightweight fixed-window limiter backed by ETS.
  """

  use GenServer

  alias SocialScribe.Limits

  @table :social_scribe_rate_limits
  @cleanup_interval_ms :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec allow(atom(), String.t()) :: :ok | {:error, non_neg_integer()}
  def allow(action, key) when is_atom(action) and is_binary(key) do
    allow(action, key, System.system_time(:millisecond))
  end

  @spec allow(atom(), String.t(), non_neg_integer()) :: :ok | {:error, non_neg_integer()}
  def allow(action, key, now_ms) when is_atom(action) and is_binary(key) and is_integer(now_ms) do
    ensure_table!()

    case Limits.rate_limit(action) do
      {:ok, %{window_ms: window_ms, max_requests: max_requests}} ->
        bucket = div(now_ms, window_ms)
        table_key = {action, key, bucket}

        count =
          :ets.update_counter(
            @table,
            table_key,
            {2, 1},
            {table_key, 0, now_ms + window_ms}
          )

        if count <= max_requests do
          :ok
        else
          retry_after_ms = window_ms - rem(now_ms, window_ms)
          {:error, max(retry_after_ms, 0)}
        end

      :error ->
        :ok
    end
  end

  @doc false
  def reset do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(state) do
    _ =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    ensure_table!()
    now_ms = System.system_time(:millisecond)

    @table
    |> :ets.tab2list()
    |> Enum.each(fn
      {key, _count, expires_at} when is_integer(expires_at) and expires_at <= now_ms ->
        :ets.delete(@table, key)

      _ ->
        :ok
    end)

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError ->
            # Another process created it in the meantime.
            :ok
        end

      _tid ->
        :ok
    end
  end
end
