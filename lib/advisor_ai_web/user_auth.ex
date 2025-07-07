defmodule AdvisorAiWeb.UserAuth do
  @moduledoc """
  Handles user authentication and session management.
  """
  use AdvisorAiWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias AdvisorAi.Accounts

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_advisor_ai_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> put_session(:user_id, user.id)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      AdvisorAiWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)

    # Check if user has expired OAuth tokens and log them out if needed
    conn = check_and_handle_expired_tokens(conn, user)

    assign(conn, :current_user, user)
  end

  defp check_and_handle_expired_tokens(conn, nil), do: conn

  defp check_and_handle_expired_tokens(conn, user) do
    if has_expired_oauth_tokens?(user) do
      # Clear user tokens and log them out
      clear_user_oauth_tokens(user)

      # Log out the user
      log_out_user(conn)
    else
      conn
    end
  end

  defp has_expired_oauth_tokens?(user) do
    # Check Google token expiration
    google_expired =
      case user.google_token_expires_at do
        nil -> false
        expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
      end

    # Check HubSpot token expiration
    hubspot_expired =
      case user.hubspot_token_expires_at do
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

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/auth/google")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:user_id, conn.assigns[:current_user] && conn.assigns.current_user.id)
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/chat"
end
