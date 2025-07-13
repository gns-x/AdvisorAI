defmodule AdvisorAi.Repo.Migrations.UpdateVectorEmbeddingsDimensions do
  use Ecto.Migration

  def up do
    # Drop the existing table and recreate it with proper vector dimensions
    execute "DROP TABLE IF EXISTS vector_embeddings CASCADE"

    # Recreate the table with 1024-dimensional vectors (mistral-embed)
    execute """
    CREATE TABLE vector_embeddings (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      content text NOT NULL,
      embedding vector(1024) NOT NULL,
      metadata jsonb DEFAULT '{}',
      source text,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    # Create indexes
    execute "CREATE INDEX vector_embeddings_user_id_index ON vector_embeddings(user_id)"

    execute "CREATE INDEX vector_embeddings_embedding_idx ON vector_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
  end

  def down do
    # Drop the table
    execute "DROP TABLE IF EXISTS vector_embeddings CASCADE"

    # Recreate the original table with 1024 dimensions
    execute """
    CREATE TABLE vector_embeddings (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      content text NOT NULL,
      embedding vector(1024) NOT NULL,
      metadata jsonb DEFAULT '{}',
      source text,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    # Recreate indexes
    execute "CREATE INDEX vector_embeddings_user_id_index ON vector_embeddings(user_id)"

    execute "CREATE INDEX vector_embeddings_embedding_idx ON vector_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
  end
end
