defmodule AdvisorAi.Tasks.AgentTask do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_tasks" do
    field :type, :string
    field :status, :string, default: "pending"
    field :description, :string
    field :context, :map, default: %{}
    field :scheduled_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :user, AdvisorAi.Accounts.User
    belongs_to :conversation, AdvisorAi.Chat.Conversation

    timestamps()
  end

  def changeset(agent_task, attrs) do
    agent_task
    |> cast(attrs, [:type, :status, :description, :context, :scheduled_at, :completed_at, :user_id, :conversation_id])
    |> validate_required([:type, :user_id])
    |> validate_inclusion(:status, ["pending", "in_progress", "completed", "failed"])
  end
end
