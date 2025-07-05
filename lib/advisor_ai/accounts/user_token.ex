defmodule AdvisorAi.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias AdvisorAi.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @rand_size 32

  # It is very important to keep the session validity period very short
  @session_validity_in_days 60

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  def verify_session_token_query(token) do
    query =
      from token in token_query(token),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: token,
        preload: [user: user]

    {:ok, query}
  end

  def token_query(token) do
    from __MODULE__, where: [token: ^token]
  end
end
