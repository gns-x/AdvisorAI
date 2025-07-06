defmodule AdvisorAi.AI.VectorEmbedding do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vector_embeddings" do
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}
    field :source, :string
    belongs_to :user, AdvisorAi.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(vector_embedding, attrs) do
    vector_embedding
    |> cast(attrs, [:content, :embedding, :metadata, :source, :user_id])
    |> validate_required([:content, :embedding, :user_id])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Find similar content using vector similarity search.
  """
  def find_similar(user_id, query_embedding, limit \\ 5) do
    from v in __MODULE__,
      where: v.user_id == ^user_id,
      order_by: [desc: fragment("embedding <=> ?", ^query_embedding)],
      limit: ^limit,
      select: %{
        id: v.id,
        content: v.content,
        metadata: v.metadata,
        source: v.source,
        similarity: fragment("embedding <=> ?", ^query_embedding)
      }
  end

  @doc """
  Store a new vector embedding.
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> AdvisorAi.Repo.insert()
  end

  @doc """
  Get embeddings by user ID.
  """
  def list_by_user(user_id, limit \\ 100) do
    from v in __MODULE__,
      where: v.user_id == ^user_id,
      order_by: [desc: v.inserted_at],
      limit: ^limit
  end
end
