defmodule AdvisorAi.Accounts do
  @moduledoc """
  The Accounts context.
  """
  alias AdvisorAi.Repo
  alias AdvisorAi.Accounts.{User, Account}
  alias AdvisorAi.Accounts.UserToken

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    with {:ok, query} <- UserToken.verify_session_token_query(token),
         %UserToken{} = user_token <- Repo.one(query) do
      user_token.user
    else
      _ -> nil
    end
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.token_query(token))
    :ok
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def get_or_create_user(attrs) do
    case get_user_by_email(attrs.email) do
      nil -> create_user(attrs)
      user -> {:ok, user |> touch_last_login()}
    end
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def touch_last_login(user) do
    user
    |> User.changeset(%{last_login_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update!()
  end

  def get_account(provider, provider_id) do
    Repo.get_by(Account, provider: provider, provider_id: provider_id)
    |> Repo.preload(:user)
  end

  def create_or_update_account(user, attrs) do
    result =
      case get_account(attrs.provider, attrs.provider_id) do
        nil ->
          %Account{user_id: user.id}
          |> Account.changeset(attrs)
          |> Repo.insert()

        account ->
          account
          |> Account.changeset(attrs)
          |> Repo.update()
      end

    # If this is a Google account, update the user's token fields as well
    if attrs.provider == "google" do
      user_token_attrs = %{
        google_access_token: attrs.access_token,
        google_refresh_token: attrs.refresh_token,
        google_token_expires_at: attrs.token_expires_at,
        google_scopes: attrs.scopes || []
      }
      update_user(user, user_token_attrs)
    end

    result
  end

  def get_user_google_account(user_id) do
    Repo.get_by(Account, user_id: user_id, provider: "google")
  end

  def get_user_google_account_by_refresh_token(refresh_token) do
    Repo.get_by(Account, refresh_token: refresh_token, provider: "google")
  end

  def get_user_hubspot_account(user_id) do
    Repo.get_by(Account, user_id: user_id, provider: "hubspot")
  end

  def update_account_tokens(account, new_token, expires_at) do
    account
    |> Account.changeset(%{
      access_token: new_token,
      token_expires_at: expires_at
    })
    |> Repo.update()
  end

  def update_user_hubspot_tokens(user, access_token, refresh_token, expires_at) do
    user
    |> Ecto.Changeset.change(%{
      hubspot_access_token: access_token,
      hubspot_refresh_token: refresh_token,
      hubspot_token_expires_at: expires_at
    })
    |> Repo.update()
  end
end
