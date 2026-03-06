defmodule SocialScribe.OverflowSafetyTest do
  use ExUnit.Case, async: true

  alias SocialScribe.Bots.RecallBot
  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Meetings.MeetingParticipant

  test "meeting changeset truncates oversized title" do
    long_title = String.duplicate("T", 400)

    changeset =
      Meeting.changeset(%Meeting{}, %{
        title: long_title,
        recorded_at: DateTime.utc_now(),
        calendar_event_id: 1,
        recall_bot_id: 1
      })

    assert String.length(changeset.changes.title) == 255
  end

  test "meeting participant changeset truncates oversized fields" do
    changeset =
      MeetingParticipant.changeset(%MeetingParticipant{}, %{
        recall_participant_id: String.duplicate("R", 600),
        name: String.duplicate("N", 500),
        meeting_id: 1
      })

    assert String.length(changeset.changes.recall_participant_id) == 255
    assert String.length(changeset.changes.name) == 255
  end

  test "recall bot changeset truncates oversized fields" do
    changeset =
      RecallBot.changeset(%RecallBot{}, %{
        recall_bot_id: String.duplicate("B", 700),
        status: String.duplicate("S", 500),
        meeting_url: "https://zoom.us/j/" <> String.duplicate("9", 500),
        user_id: 1,
        calendar_event_id: 1
      })

    assert String.length(changeset.changes.recall_bot_id) == 255
    assert String.length(changeset.changes.status) == 255
    assert String.length(changeset.changes.meeting_url) == 255
  end
end
