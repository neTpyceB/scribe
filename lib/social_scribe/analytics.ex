defmodule SocialScribe.Analytics do
  @moduledoc """
  Read models for dashboard analytics metrics.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Automations.{Automation, AutomationResult}
  alias SocialScribe.Calendar.CalendarEvent
  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Repo

  @supported_windows [7, 30, 90]

  def supported_windows, do: @supported_windows

  def normalize_window(window) when is_integer(window) and window in @supported_windows,
    do: window

  def normalize_window(_), do: 30

  def snapshot(user, window_days) do
    window_days = normalize_window(window_days)
    from_dt = DateTime.utc_now() |> DateTime.add(-window_days * 86_400, :second)

    %{
      window_days: window_days,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      meetings_per_day: meetings_per_day(user.id, from_dt, window_days),
      automation_results_per_day: automation_results_per_day(user.id, from_dt, window_days),
      platform_post_stats: platform_post_stats(user.id, from_dt),
      top_automations: top_automations(user.id, from_dt)
    }
  end

  defp meetings_per_day(user_id, from_dt, window_days) do
    counts =
      from(m in Meeting,
        join: ce in CalendarEvent,
        on: ce.id == m.calendar_event_id,
        where: ce.user_id == ^user_id and m.recorded_at >= ^from_dt,
        group_by: fragment("date(?)", m.recorded_at),
        select: {fragment("date(?)", m.recorded_at), count(m.id)}
      )
      |> Repo.all()
      |> Map.new()

    date_series(window_days)
    |> Enum.map(fn date ->
      %{date: date, count: Map.get(counts, date, 0)}
    end)
  end

  defp automation_results_per_day(user_id, from_dt, window_days) do
    counts =
      from(ar in AutomationResult,
        join: a in Automation,
        on: a.id == ar.automation_id,
        where: a.user_id == ^user_id and ar.inserted_at >= ^from_dt,
        group_by: fragment("date(?)", ar.inserted_at),
        select: {fragment("date(?)", ar.inserted_at), count(ar.id)}
      )
      |> Repo.all()
      |> Map.new()

    date_series(window_days)
    |> Enum.map(fn date ->
      %{date: date, count: Map.get(counts, date, 0)}
    end)
  end

  defp platform_post_stats(user_id, from_dt) do
    grouped =
      from(ar in AutomationResult,
        join: a in Automation,
        on: a.id == ar.automation_id,
        where: a.user_id == ^user_id and ar.inserted_at >= ^from_dt,
        group_by: [a.platform, ar.status],
        select: {a.platform, ar.status, count(ar.id)}
      )
      |> Repo.all()

    Enum.reduce([:linkedin, :facebook], %{}, fn platform, acc ->
      platform_rows = Enum.filter(grouped, fn {p, _s, _c} -> p == platform end)
      draft = status_count(platform_rows, "draft")
      posted = status_count(platform_rows, "posted")
      failed = status_count(platform_rows, "generation_failed")

      Map.put(acc, platform, %{
        draft: draft,
        posted: posted,
        generation_failed: failed,
        total: draft + posted + failed
      })
    end)
  end

  defp top_automations(user_id, from_dt) do
    from(ar in AutomationResult,
      join: a in Automation,
      on: a.id == ar.automation_id,
      where: a.user_id == ^user_id and ar.inserted_at >= ^from_dt,
      group_by: [a.id, a.name, a.platform],
      order_by: [desc: count(ar.id)],
      limit: 5,
      select: %{id: a.id, name: a.name, platform: a.platform, count: count(ar.id)}
    )
    |> Repo.all()
  end

  defp status_count(rows, status) do
    rows
    |> Enum.find_value(0, fn
      {_platform, ^status, count} -> count
      _ -> nil
    end)
  end

  defp date_series(window_days) do
    today = Date.utc_today()
    first = Date.add(today, -(window_days - 1))

    0..(window_days - 1)
    |> Enum.map(&Date.add(first, &1))
  end
end
