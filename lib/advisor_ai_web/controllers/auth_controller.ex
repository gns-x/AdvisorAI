defmodule AdvisorAiWeb.AuthController do
  use AdvisorAiWeb, :controller

  alias AdvisorAi.Accounts
  alias AdvisorAiWeb.UserAuth

  plug Ueberauth

  def request(conn, %{"provider" => provider}) do
    # For connecting services, we need to pass the current user ID
    current_user = conn.assigns.current_user

    if current_user do
      # Connecting a service to existing user
      try do
        redirect(conn,
          external:
            Ueberauth.authorize_url!(provider,
              state: current_user.id,
              scope: get_oauth_scopes(provider)
            )
        )
      rescue
        _ ->
          conn
          |> put_flash(
            :error,
            "#{String.capitalize(provider)} OAuth is not configured. Please set up the OAuth credentials."
          )
          |> redirect(to: ~p"/settings/integrations")
      end
    else
      # Initial login
      try do
        redirect(conn, external: Ueberauth.authorize_url!(provider))
      rescue
        _ ->
          conn
          |> put_flash(:error, "#{String.capitalize(provider)} OAuth is not configured.")
          |> redirect(to: ~p"/")
      end
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    current_user = conn.assigns.current_user

    if current_user do
      # Connecting service to existing user
      connect_service(conn, auth, current_user)
    else
      # Initial login
      handle_initial_login(conn, auth)
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: ~p"/settings/integrations")
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
  end

  defp connect_service(conn, auth, user) do
    provider = to_string(auth.provider)

    case provider do
      "google" ->
        # Save to accounts table instead of users table
        account_params = %{
          provider: "google",
          provider_id: auth.uid,
          access_token: auth.credentials.token,
          refresh_token: auth.credentials.refresh_token,
          token_expires_at:
            auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at),
          scopes: auth.credentials.scopes || [],
          raw_data: %{
            "info" => Map.from_struct(auth.info),
            "uid" => auth.uid,
            "provider" => "google"
          }
        }

        case Accounts.create_or_update_account(user, account_params) do
          {:ok, _account} ->
            # Reload user to get updated token fields
            updated_user = Accounts.get_user!(user.id)

            # Set up Gmail push notifications for this user
            webhook_url = System.get_env("WEBHOOK_URL") || "https://your-netlify-app.netlify.app/webhook/gmail"

            case AdvisorAi.Integrations.Gmail.setup_push_notifications(updated_user, webhook_url) do
              {:ok, _} ->
                conn
                |> put_flash(
                  :info,
                  "Google connected successfully! Real-time email automation is now enabled."
                )
                |> assign(:current_user, updated_user)
                |> redirect(to: ~p"/settings/integrations")

              {:error, reason} ->
                conn
                |> put_flash(
                  :error,
                  "Google connected, but real-time email automation could not be enabled: #{reason}"
                )
                |> assign(:current_user, updated_user)
                |> redirect(to: ~p"/settings/integrations")
            end

          {:error, changeset} ->
            require Logger
            Logger.error("Failed to create or update account: #{inspect(changeset.errors)}")

            conn
            |> put_flash(:error, "Failed to connect Google account: #{inspect(changeset.errors)}")
            |> redirect(to: ~p"/settings/integrations")
        end

      "hubspot" ->
        account_params = %{
          provider: "hubspot",
          provider_id: auth.uid,
          access_token: auth.credentials.token,
          refresh_token: auth.credentials.refresh_token,
          token_expires_at:
            auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at),
          raw_data: %{
            "info" => Map.from_struct(auth.info),
            "uid" => auth.uid,
            "provider" => "hubspot"
          }
        }

        case Accounts.create_or_update_account(user, account_params) do
          {:ok, _account} ->
            conn
            |> put_flash(:info, "HubSpot connected successfully!")
            |> redirect(to: ~p"/settings/integrations")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to connect HubSpot")
            |> redirect(to: ~p"/settings/integrations")
        end

      _ ->
        conn
        |> put_flash(:error, "Unknown provider: #{provider}")
        |> redirect(to: ~p"/settings/integrations")
    end
  end

  defp handle_initial_login(conn, auth) do
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
      token_expires_at:
        auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at),
      scopes: auth.credentials.scopes || [],
      raw_data: %{
        "info" => Map.from_struct(auth.info),
        "uid" => auth.uid,
        "provider" => to_string(auth.provider)
      }
    }

    case Accounts.get_or_create_user(user_params) do
      {:ok, user} ->
        case Accounts.create_or_update_account(user, account_params) do
          {:ok, _account} ->
            conn
            |> put_flash(:info, "Welcome #{user.name}!")
            |> UserAuth.log_in_user(user)

          {:error, changeset} ->
            require Logger
            Logger.error("Failed to create or update account: #{inspect(changeset.errors)}")

            conn
            |> put_flash(:error, "Failed to connect Google account: #{inspect(changeset.errors)}")
            |> redirect(to: ~p"/settings/integrations")
        end

      {:error, changeset} ->
        require Logger
        Logger.error("Failed to create or get user: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Authentication failed: #{inspect(changeset.errors)}")
        |> redirect(to: ~p"/")
    end
  end

  defp get_oauth_scopes("google") do
    "email profile https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/calendar.events"
  end

  defp get_oauth_scopes("hubspot") do
    ""
  end

  defp get_oauth_scopes(_), do: ""
end
