defmodule AdvisorAi.Repo.Migrations.AddCascadeDeleteToAgentTasks do
  use Ecto.Migration

  def change do
    # Drop the existing foreign key constraint
    drop constraint(:agent_tasks, "agent_tasks_conversation_id_fkey")

    # Add the foreign key constraint with cascade delete
    alter table(:agent_tasks) do
      modify :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all)
    end
  end
end
