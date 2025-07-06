defmodule AdvisorAi.Repo.Migrations.AddOauthTokensToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Google OAuth tokens
      add :google_access_token, :text
      add :google_refresh_token, :text
      add :google_token_expires_at, :utc_datetime

      # HubSpot OAuth tokens
      add :hubspot_access_token, :text
      add :hubspot_refresh_token, :text
      add :hubspot_token_expires_at, :utc_datetime
    end
  end
end
