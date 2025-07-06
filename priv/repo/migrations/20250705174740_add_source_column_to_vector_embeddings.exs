defmodule AdvisorAi.Repo.Migrations.AddSourceColumnToVectorEmbeddings do
  use Ecto.Migration

  def up do
    # Add the source column
    alter table(:vector_embeddings) do
      add :source, :string
    end

    # Update existing data to populate the source column
    execute """
    UPDATE vector_embeddings
    SET source = source_type
    WHERE source IS NULL
    """

    # Make source column not null after populating it
    alter table(:vector_embeddings) do
      modify :source, :string, null: false
    end

    # Drop the old columns
    alter table(:vector_embeddings) do
      remove :source_type
      remove :source_id
    end

    # Drop the old index using raw SQL
    execute "DROP INDEX IF EXISTS vector_embeddings_source_type_source_id_index"
  end

  def down do
    # Add back the old columns
    alter table(:vector_embeddings) do
      add :source_type, :string
      add :source_id, :string
    end

    # Populate old columns from source
    execute """
    UPDATE vector_embeddings
    SET source_type = source, source_id = id::text
    """

    # Make old columns not null
    alter table(:vector_embeddings) do
      modify :source_type, :string, null: false
      modify :source_id, :string, null: false
    end

    # Recreate the old index
    create index(:vector_embeddings, [:source_type, :source_id])

    # Remove the source column
    alter table(:vector_embeddings) do
      remove :source
    end
  end
end
