defmodule AdvisorAi.Repo.Migrations.AddGoogleScopesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_scopes, {:array, :string}, default: []
    end
  end
end
