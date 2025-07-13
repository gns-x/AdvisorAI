defmodule AdvisorAi.Repo.Migrations.CreateProcessedEmails do
  use Ecto.Migration

  def change do
    create table(:processed_emails) do
      add :user_id, :integer
      add :message_id, :string
      timestamps()
    end

    create unique_index(:processed_emails, [:user_id, :message_id])
  end
end
