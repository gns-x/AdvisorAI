defmodule AdvisorAiWeb.WebhookController do
  use AdvisorAiWeb, :controller

  alias AdvisorAi.Accounts
  alias AdvisorAi.AI.Agent

  def gmail(conn, params) do
    # Example: params = %{"user_id" => user_id, "email_data" => ...}
    user = Accounts.get_user(params["user_id"])

    if user do
      Agent.handle_trigger(user, "email_received", params["email_data"] || %{})
    end

    conn |> put_status(:ok) |> json(%{status: "received"})
  end

  def calendar(conn, params) do
    # Example: params = %{"user_id" => user_id, "event_data" => ...}
    user = Accounts.get_user(params["user_id"])

    if user do
      Agent.handle_trigger(user, "calendar_event", params["event_data"] || %{})
    end

    conn |> put_status(:ok) |> json(%{status: "received"})
  end

  def hubspot(conn, params) do
    # Example: params = %{"user_id" => user_id, "hubspot_data" => ...}
    user = Accounts.get_user(params["user_id"])

    if user do
      Agent.handle_trigger(user, "hubspot_update", params["hubspot_data"] || %{})
    end

    conn |> put_status(:ok) |> json(%{status: "received"})
  end
end
