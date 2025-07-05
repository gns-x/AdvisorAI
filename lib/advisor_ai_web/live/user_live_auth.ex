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
      {:cont, socket}
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
end
