defmodule AdvisorAi.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    # "user", "assistant", "system"
    field :role, :string
    field :content, :string
    field :tool_calls, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :conversation, AdvisorAi.Chat.Conversation

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tool_calls, :metadata, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
    |> maybe_convert_tool_calls()
  end

  defp maybe_convert_tool_calls(changeset) do
    case get_change(changeset, :tool_calls) do
      nil ->
        changeset

      tool_calls when is_list(tool_calls) ->
        put_change(changeset, :tool_calls, %{"calls" => tool_calls})

      tool_calls when is_map(tool_calls) ->
        changeset

      _ ->
        put_change(changeset, :tool_calls, %{})
    end
  end
end
