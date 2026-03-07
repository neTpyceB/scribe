defmodule SocialScribe.OpsHealth do
  @moduledoc """
  Aggregates runtime and integration health data for the dashboard health page.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Accounts
  alias SocialScribe.Automations
  alias SocialScribe.Meetings
  alias SocialScribe.Repo

  @providers ~w(google hubspot salesforce linkedin facebook)

  def snapshot(user) do
    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      system: system_health(),
      integrations: integration_health(user),
      jobs: oban_health(),
      pipeline: pipeline_health(user)
    }
  end

  defp system_health do
    db_status =
      case Repo.query("SELECT 1") do
        {:ok, _} -> %{up: true, error: nil}
        {:error, reason} -> %{up: false, error: inspect(reason)}
      end

    total_wall_clock_ms =
      case :erlang.statistics(:wall_clock) do
        {total, _since_last} when is_integer(total) -> total
        _ -> 0
      end

    memory_total =
      :erlang.memory()
      |> Keyword.get(:total, 0)
      |> bytes_to_mb()

    %{
      db: db_status,
      uptime_seconds: div(total_wall_clock_ms, 1000),
      process_count: :erlang.system_info(:process_count),
      run_queue: :erlang.statistics(:run_queue),
      memory_total_mb: memory_total
    }
  end

  defp integration_health(user) do
    credentials = Accounts.list_user_credentials(user)
    expiring_threshold = DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second)

    @providers
    |> Enum.map(fn provider ->
      provider_credentials = Enum.filter(credentials, &(&1.provider == provider))

      expiring_soon_count =
        Enum.count(provider_credentials, fn credential ->
          case credential.expires_at do
            %DateTime{} = expires_at ->
              DateTime.compare(expires_at, expiring_threshold) != :gt

            _ ->
              false
          end
        end)

      %{
        provider: provider,
        connected_count: length(provider_credentials),
        connected?: provider_credentials != [],
        expiring_soon_count: expiring_soon_count
      }
    end)
  end

  defp oban_health do
    state_counts =
      case Repo.query("SELECT state, COUNT(*)::bigint FROM oban_jobs GROUP BY state") do
        {:ok, %{rows: rows}} ->
          Enum.into(rows, %{}, fn [state, count] -> {state, count} end)

        {:error, _} ->
          %{}
      end

    recent_failures =
      case Repo.query("""
             SELECT worker, queue, attempted_at
             FROM oban_jobs
             WHERE state IN ('retryable', 'discarded')
             ORDER BY attempted_at DESC NULLS LAST
             LIMIT 5
           """) do
        {:ok, %{rows: rows}} ->
          Enum.map(rows, fn [worker, queue, attempted_at] ->
            %{worker: worker, queue: queue, attempted_at: attempted_at}
          end)

        {:error, _} ->
          []
      end

    %{state_counts: state_counts, recent_failures: recent_failures}
  end

  defp pipeline_health(user) do
    last_meeting =
      user
      |> Meetings.list_user_meetings()
      |> List.first()

    case last_meeting do
      nil ->
        %{
          has_meeting?: false,
          meeting_title: nil,
          recorded_at: nil,
          transcript_present?: false,
          follow_up_present?: false,
          automation_results_count: 0
        }

      meeting ->
        automation_results_count =
          meeting.id
          |> Automations.list_automation_results_for_meeting()
          |> length()

        %{
          has_meeting?: true,
          meeting_title: meeting.title,
          recorded_at: meeting.recorded_at,
          transcript_present?: transcript_present?(meeting),
          follow_up_present?:
            is_binary(meeting.follow_up_email) and meeting.follow_up_email != "",
          automation_results_count: automation_results_count
        }
    end
  end

  defp transcript_present?(meeting) do
    case meeting.meeting_transcript do
      %{content: %{"data" => data}} when is_list(data) -> data != []
      _ -> false
    end
  end

  defp bytes_to_mb(bytes) when is_integer(bytes) and bytes >= 0 do
    bytes
    |> Kernel./(1024 * 1024)
    |> Float.round(1)
  end
end
