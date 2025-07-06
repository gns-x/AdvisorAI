defmodule AdvisorAiWeb.UserLiveAuth do
  @moduledoc """
  Handles user authentication in LiveViews
  """
  use AdvisorAiWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component
  alias AdvisorAi.Accounts

  def on_mount(:default, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user do
      # Check for expired OAuth tokens
      if has_expired_oauth_tokens?(socket.assigns.current_user) do
        # Clear tokens and redirect to login
        clear_user_oauth_tokens(socket.assigns.current_user)

        socket =
          socket
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: ~p"/")

        {:halt, socket}
      else
      {:cont, socket}
      end
    else
      socket =
        socket
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  defp assign_current_user(socket, session) do
    case session do
      %{"user_token" => user_token} ->
        assign_new(socket, :current_user, fn ->
          Accounts.get_user_by_session_token(user_token)
        end)

      %{} ->
        assign_new(socket, :current_user, fn -> nil end)
    end
  end

  defp has_expired_oauth_tokens?(user) do
    # Check Google token expiration
    google_expired = case user.google_token_expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end

    # Check HubSpot token expiration
    hubspot_expired = case user.hubspot_token_expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end

    # If user has any OAuth tokens and they're expired, return true
    (user.google_access_token && google_expired) ||
    (user.hubspot_access_token && hubspot_expired)
  end

  defp clear_user_oauth_tokens(user) do
    # Clear OAuth tokens from user record
    user_params = %{
      google_access_token: nil,
      google_refresh_token: nil,
      google_token_expires_at: nil,
      google_scopes: [],
      hubspot_access_token: nil,
      hubspot_refresh_token: nil,
      hubspot_token_expires_at: nil
    }

    Accounts.update_user(user, user_params)
  end
end
