defmodule AdvisorAi.Chat do
  @moduledoc """
  The Chat context.
  """
  import Ecto.Query
  alias AdvisorAi.Repo
  alias AdvisorAi.Chat.{Conversation, Message}

  def list_user_conversations(user_id) do
    Conversation
    |> where(user_id: ^user_id)
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  def get_conversation!(id, user_id) do
    Conversation
    |> where(id: ^id, user_id: ^user_id)
    |> Repo.one!()
  end

  def get_conversation_with_messages!(id, user_id) do
    Conversation
    |> where(id: ^id, user_id: ^user_id)
    |> preload(messages: ^from(m in Message, order_by: m.inserted_at))
    |> Repo.one!()
  end

  def create_conversation(user_id, attrs \\ %{}) do
    %Conversation{user_id: user_id}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def create_message(conversation_id, attrs) do
    %Message{conversation_id: conversation_id}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        # Update conversation's updated_at
        from(c in Conversation, where: c.id == ^conversation_id)
        |> Repo.update_all(set: [updated_at: DateTime.utc_now() |> DateTime.truncate(:second)])

        {:ok, message}

      error ->
        error
    end
  end

  def update_conversation_title(conversation, title) do
    conversation
    |> Conversation.changeset(%{title: title})
    |> Repo.update()
  end

  def delete_conversation(conversation) do
    Repo.delete(conversation)
  end

  def get_or_create_current_conversation(user_id) do
    case list_user_conversations(user_id) |> List.first() do
      nil -> create_conversation(user_id, %{title: "New Conversation"})
      conversation -> {:ok, conversation}
    end
  end

  def get_conversation_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    query =
      Message
      |> where(conversation_id: ^conversation_id)
      |> order_by(asc: :inserted_at)

    query =
      if limit do
        limit(query, ^limit)
      else
        query
      end

    Repo.all(query)
  end
end
