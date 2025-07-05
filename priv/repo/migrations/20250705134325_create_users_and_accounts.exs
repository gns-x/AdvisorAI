defmodule AdvisorAi.Repo.Migrations.CreateUsersAndAccounts do
  use Ecto.Migration

  def change do
    # Enable UUID extension
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"", ""
    execute "CREATE EXTENSION IF NOT EXISTS \"vector\"", ""

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string
      add :avatar_url, :string
      add :is_active, :boolean, default: true
      add :last_login_at, :utc_datetime

      timestamps()
    end

    create unique_index(:users, [:email])

    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_id, :string, null: false
      add :access_token, :text
      add :refresh_token, :text
      add :token_expires_at, :utc_datetime
      add :scopes, {:array, :string}, default: []
      add :raw_data, :map, default: %{}

      timestamps()
    end

    create index(:accounts, [:user_id])
    create unique_index(:accounts, [:provider, :provider_id])
    create index(:accounts, [:provider])

    # Tables for AI features
    create table(:vector_embeddings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # "email", "hubspot_contact", "hubspot_note"
      add :source_type, :string, null: false
      add :source_id, :string, null: false
      add :content, :text, null: false
      add :embedding, :vector, size: 1536
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:vector_embeddings, [:user_id])
    create index(:vector_embeddings, [:source_type, :source_id])

    execute "CREATE INDEX vector_embeddings_embedding_idx ON vector_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
            "DROP INDEX vector_embeddings_embedding_idx"

    # Conversations and Messages
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string
      add :context, :map, default: %{}

      timestamps()
    end

    create index(:conversations, [:user_id])

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      # "user", "assistant", "system"
      add :role, :string, null: false
      add :content, :text, null: false
      add :tool_calls, :map
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:messages, [:conversation_id])

    # Tasks for agent memory
    create table(:agent_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, type: :binary_id), null: true
      add :type, :string, null: false
      add :status, :string, default: "pending"
      add :description, :text
      add :context, :map, default: %{}
      add :scheduled_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:agent_tasks, [:user_id])
    create index(:agent_tasks, [:status])
    create index(:agent_tasks, [:scheduled_at])

    # Agent Instructions
    create table(:agent_instructions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :instruction, :text, null: false
      add :is_active, :boolean, default: true
      # "email_received", "calendar_event", "hubspot_update", etc.
      add :trigger_type, :string
      add :conditions, :map, default: %{}

      timestamps()
    end

    create index(:agent_instructions, [:user_id, :is_active])
  end
end
