defmodule AdvisorAi.AI.VectorEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vector_embeddings" do
    field :source_type, :string
    field :source_id, :string
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}

    belongs_to :user, AdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [:source_type, :source_id, :content, :embedding, :metadata, :user_id])
    |> validate_required([:source_type, :source_id, :content, :user_id])
    |> validate_inclusion(:source_type, [
      "email",
      "hubspot_contact",
      "hubspot_note",
      "calendar_event"
    ])
  end
end
