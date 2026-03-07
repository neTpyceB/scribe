defmodule SocialScribe.Repo.Migrations.AddIsAdminModeToUserBotPreferences do
  use Ecto.Migration

  def change do
    alter table(:user_bot_preferences) do
      add :is_admin_mode, :boolean, default: false, null: false
    end
  end
end
