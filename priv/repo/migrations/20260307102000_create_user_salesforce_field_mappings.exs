defmodule SocialScribe.Repo.Migrations.CreateUserSalesforceFieldMappings do
  use Ecto.Migration

  def change do
    create table(:user_salesforce_field_mappings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :source_field, :string, null: false
      add :target_field, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_salesforce_field_mappings, [:user_id, :source_field])
  end
end
