defmodule AdvisorAi.Integrations.ProcessedEmail do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "processed_emails" do
    field :user_id, :binary_id
    field :message_id, :string
    timestamps()
  end

  def changeset(email, attrs) do
    email
    |> cast(attrs, [:user_id, :message_id])
    |> validate_required([:user_id, :message_id])
    |> unique_constraint([:user_id, :message_id])
  end
end
