defmodule SocialScribe.Meetings.MeetingParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting

  schema "meeting_participants" do
    field :recall_participant_id, :string
    field :name, :string
    field :is_host, :boolean

    belongs_to :meeting, Meeting

    timestamps()
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:recall_participant_id, :name, :is_host, :meeting_id])
    |> truncate_string(:recall_participant_id, 255)
    |> truncate_string(:name, 255)
    |> validate_required([:recall_participant_id, :name, :meeting_id])
  end

  defp truncate_string(changeset, field, max) do
    update_change(changeset, field, fn value ->
      if is_binary(value) and String.length(value) > max do
        String.slice(value, 0, max)
      else
        value
      end
    end)
  end
end
