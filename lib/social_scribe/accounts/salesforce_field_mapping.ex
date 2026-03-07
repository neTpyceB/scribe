defmodule SocialScribe.Accounts.SalesforceFieldMapping do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.SalesforceFields

  schema "user_salesforce_field_mappings" do
    field :source_field, :string
    field :target_field, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [:user_id, :source_field, :target_field])
    |> validate_required([:user_id, :source_field, :target_field])
    |> validate_inclusion(:source_field, SalesforceFields.allowed_fields())
    |> validate_inclusion(:target_field, SalesforceFields.allowed_fields())
    |> unique_constraint([:user_id, :source_field],
      name: :user_salesforce_field_mappings_user_id_source_field_index
    )
  end
end
