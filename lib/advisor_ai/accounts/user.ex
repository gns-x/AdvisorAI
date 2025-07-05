defmodule AdvisorAi.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :is_active, :boolean, default: true
    field :last_login_at, :utc_datetime

    has_many :accounts, AdvisorAi.Accounts.Account
    has_many :conversations, AdvisorAi.Chat.Conversation
    has_many :agent_tasks, AdvisorAi.Tasks.AgentTask
    has_many :agent_instructions, AdvisorAi.AI.AgentInstruction
    has_many :vector_embeddings, AdvisorAi.AI.VectorEmbedding

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url, :is_active, :last_login_at])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> unique_constraint(:email)
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> put_change(:last_login_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
