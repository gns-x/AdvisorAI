defmodule AdvisorAi.AI.AgentInstruction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_instructions" do
    field :instruction, :string
    field :is_active, :boolean, default: true
    field :trigger_type, :string  # "email_received", "calendar_event", "hubspot_update", etc.
    field :conditions, :map, default: %{}

    belongs_to :user, AdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(agent_instruction, attrs) do
    agent_instruction
    |> cast(attrs, [:instruction, :is_active, :trigger_type, :conditions, :user_id])
    |> validate_required([:instruction, :user_id])
  end
end
