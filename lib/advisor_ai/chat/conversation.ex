defmodule AdvisorAi.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :title, :string
    field :context, :map, default: %{}

    belongs_to :user, AdvisorAi.Accounts.User
    has_many :messages, AdvisorAi.Chat.Message
    has_many :agent_tasks, AdvisorAi.Tasks.AgentTask

    timestamps()
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :context, :user_id])
    |> validate_required([:user_id])
  end
end
