defmodule AdvisorAi.Integrations.ProcessedEmail do
  use Ecto.Schema
  import Ecto.Changeset

  schema "processed_emails" do
    field :user_id, :binary_id
    field :message_id, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(email, attrs) do
    email
    |> cast(attrs, [:user_id, :message_id])
    |> validate_required([:user_id, :message_id])
    |> unique_constraint([:user_id, :message_id])
  end
end
