defmodule AdvisorAiWeb.AuthController do
  use AdvisorAiWeb, :controller

  alias AdvisorAi.Accounts
  alias AdvisorAiWeb.UserAuth

  plug Ueberauth

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      email: auth.info.email,
      name: auth.info.name,
      avatar_url: auth.info.image
    }

    account_params = %{
      provider: to_string(auth.provider),
      provider_id: auth.uid,
      access_token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      token_expires_at: auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at),
      scopes: Map.get(auth.credentials.other, :scope, "") |> String.split(" ", trim: true),
      raw_data: %{
        "info" => Map.from_struct(auth.info),
        "uid" => auth.uid,
        "provider" => to_string(auth.provider)
      }
    }

    case Accounts.get_or_create_user(user_params) do
      {:ok, user} ->
        {:ok, _account} = Accounts.create_or_update_account(user, account_params)

        conn
        |> UserAuth.log_in_user(user)
        |> put_flash(:info, "Welcome #{user.name}!")
        |> redirect(to: ~p"/chat")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: ~p"/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
  end
end
