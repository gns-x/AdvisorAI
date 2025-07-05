defmodule AdvisorAi.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :provider, :string
    field :provider_id, :string
    field :access_token, :string
    field :refresh_token, :string
    field :token_expires_at, :utc_datetime
    field :scopes, {:array, :string}, default: []
    field :raw_data, :map, default: %{}

    belongs_to :user, AdvisorAi.Accounts.User

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:provider, :provider_id, :access_token, :refresh_token,
                    :token_expires_at, :scopes, :raw_data, :user_id])
    |> validate_required([:provider, :provider_id, :user_id])
    |> unique_constraint([:provider, :provider_id])
  end
end
