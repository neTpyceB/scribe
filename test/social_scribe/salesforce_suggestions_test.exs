defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase, async: true

  import Mox
  import SocialScribe.MeetingsFixtures

  alias SocialScribe.SalesforceSuggestions
  alias SocialScribe.Meetings

  setup :verify_on_exit!

  test "keeps only supported changed fields and merges current contact values, then reuses cache" do
    meeting = meeting_fixture()
    transcript = meeting_transcript_fixture(%{meeting_id: meeting.id, content: %{"data" => [%{"words" => [%{"text" => "seed"}]}]}})
    meeting = Meetings.get_meeting_with_details(transcript.meeting_id)

    contact = %{
      phone: "123",
      email: "same@example.com",
      firstname: "Old"
    }

    SocialScribe.AIContentGeneratorMock
    |> expect(:generate_hubspot_suggestions, fn ^meeting ->
      {:ok,
       [
         %{field: "phone", value: "8885550000", context: "My phone is 8885550000"},
         %{field: "email", value: "same@example.com", context: "Email is same@example.com"},
         %{field: "website", value: "https://example.com", context: "My website..."},
         %{field: "firstname", value: "New", context: "Call me New"}
       ]}
    end)

    assert {:ok, suggestions} = SalesforceSuggestions.generate_suggestions(meeting, contact)
    assert Enum.count(suggestions) == 2

    assert Enum.any?(suggestions, fn s ->
             s.field == "phone" and s.current_value == "123" and s.new_value == "8885550000"
           end)

    assert Enum.any?(suggestions, fn s ->
             s.field == "firstname" and s.current_value == "Old" and s.new_value == "New"
           end)

    meeting_after_cache = Meetings.get_meeting_with_details(meeting.id)

    assert is_binary(meeting_after_cache.meeting_transcript.salesforce_ai_transcript_hash)
    assert is_map(meeting_after_cache.meeting_transcript.salesforce_ai_suggestions)

    # Second call should use transcript-hash cache and not call AI again.
    assert {:ok, cached_suggestions} =
             SalesforceSuggestions.generate_suggestions(meeting_after_cache, contact)

    assert cached_suggestions == suggestions
  end

  test "invalidates cache when transcript content changes and re-analyzes" do
    meeting = meeting_fixture()

    transcript =
      meeting_transcript_fixture(%{
        meeting_id: meeting.id,
        content: %{"data" => [%{"words" => [%{"text" => "old transcript"}]}]}
      })

    meeting = Meetings.get_meeting_with_details(transcript.meeting_id)
    contact = %{phone: "123", email: "old@example.com"}

    SocialScribe.AIContentGeneratorMock
    |> expect(:generate_hubspot_suggestions, fn ^meeting ->
      {:ok, [%{field: "phone", value: "111", context: "first"}]}
    end)
    |> expect(:generate_hubspot_suggestions, fn _meeting_after_update ->
      {:ok, [%{field: "email", value: "new@example.com", context: "second"}]}
    end)

    assert {:ok, first} = SalesforceSuggestions.generate_suggestions(meeting, contact)
    assert Enum.any?(first, &(&1.field == "phone" and &1.new_value == "111"))

    {:ok, _updated_transcript} =
      Meetings.update_meeting_transcript(meeting.meeting_transcript, %{
        content: %{"data" => [%{"words" => [%{"text" => "new transcript"}]}]}
      })

    meeting_after_update = Meetings.get_meeting_with_details(meeting.id)

    assert {:ok, second} =
             SalesforceSuggestions.generate_suggestions(meeting_after_update, contact)

    assert Enum.any?(second, &(&1.field == "email" and &1.new_value == "new@example.com"))
  end
end
