defmodule AdvisorAi.Repo.Migrations.InstallPgvectorExtension do
  use Ecto.Migration

  def up do
    # Install the pgvector extension
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    # Create vector_embeddings table if it doesn't exist
    execute """
    CREATE TABLE IF NOT EXISTS vector_embeddings (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      content text NOT NULL,
      embedding vector NOT NULL,
      metadata jsonb DEFAULT '{}',
      source text,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """

    # Create indexes if they don't exist
    execute "CREATE INDEX IF NOT EXISTS vector_embeddings_user_id_index ON vector_embeddings(user_id)"

    execute "CREATE INDEX IF NOT EXISTS vector_embeddings_embedding_idx ON vector_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
  end

  def down do
    drop table(:vector_embeddings)
    execute "DROP EXTENSION IF EXISTS vector"
  end
end
