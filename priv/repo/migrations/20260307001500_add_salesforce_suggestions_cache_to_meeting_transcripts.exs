defmodule SocialScribe.Repo.Migrations.AddSalesforceSuggestionsCacheToMeetingTranscripts do
  use Ecto.Migration

  def change do
    alter table(:meeting_transcripts) do
      add :salesforce_ai_suggestions, :map
      add :salesforce_ai_transcript_hash, :string, size: 64
    end
  end
end
