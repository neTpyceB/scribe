defmodule SocialScribe.Meetings.MeetingTranscript do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting

  schema "meeting_transcripts" do
    field :content, :map
    field :language, :string
    field :salesforce_ai_suggestions, :map
    field :salesforce_ai_transcript_hash, :string

    belongs_to :meeting, Meeting

    timestamps()
  end

  def changeset(transcript, attrs) do
    transcript
    |> cast(attrs, [
      :content,
      :language,
      :meeting_id,
      :salesforce_ai_suggestions,
      :salesforce_ai_transcript_hash
    ])
    |> validate_required([:content, :meeting_id])
  end
end
