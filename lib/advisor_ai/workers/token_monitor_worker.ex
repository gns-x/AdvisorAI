defmodule AdvisorAi.Workers.TokenMonitorWorker do
  @moduledoc """
  Background worker that monitors OAuth token expiration and notifies users.
  """

  use Oban.Worker, queue: :default
  alias AdvisorAi.{Accounts, Chat, Repo}
  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    # Check all Google accounts for token expiration
    check_google_tokens()

    # Check all HubSpot accounts for token expiration
    check_hubspot_tokens()

    :ok
  end

  defp check_google_tokens() do
    # Get all Google accounts with tokens
    google_accounts =
      from a in AdvisorAi.Accounts.Account,
      where: a.provider == "google" and not is_nil(a.token_expires_at),
      preload: [:user]

    Repo.all(google_accounts)
    |> Enum.each(fn account ->
      check_token_expiration(account, "Google")
    end)
  end

  defp check_hubspot_tokens() do
    # Get all HubSpot accounts with tokens
    hubspot_accounts =
      from a in AdvisorAi.Accounts.Account,
      where: a.provider == "hubspot" and not is_nil(a.token_expires_at),
      preload: [:user]

    Repo.all(hubspot_accounts)
    |> Enum.each(fn account ->
      check_token_expiration(account, "HubSpot")
    end)
  end

  defp check_token_expiration(account, provider_name) do
    now = DateTime.utc_now()

    # Check if token expires in the next 24 hours
    expires_in_24h = DateTime.add(now, 24 * 60 * 60, :second)

    cond do
      # Token has already expired
      DateTime.compare(account.token_expires_at, now) == :lt ->
        notify_token_expired(account.user, provider_name)

      # Token expires in the next 24 hours
      DateTime.compare(account.token_expires_at, expires_in_24h) == :lt ->
        notify_token_expiring_soon(account.user, provider_name, account.token_expires_at)

      # Token is still valid
      true ->
        :ok
    end
  end

  defp notify_token_expired(user, provider_name) do
    message = """
    ⚠️ **#{provider_name} Connection Lost**

    Your #{provider_name} connection has expired and needs to be reconnected.

    **What this means:**
    - I can no longer access your #{provider_name} data
    - Email and calendar features are temporarily disabled
    - Automation rules are paused

    **To fix this:**
    1. Go to Settings → Integrations
    2. Click "Reconnect #{provider_name}"
    3. Authorize the app again

    This will restore all functionality immediately.
    """

    create_notification_message(user, message, "token_expired")
  end

  defp notify_token_expiring_soon(user, provider_name, expires_at) do
    expires_in_hours = DateTime.diff(expires_at, DateTime.utc_now(), :hour)

    message = """
    ⏰ **#{provider_name} Token Expiring Soon**

    Your #{provider_name} connection will expire in #{expires_in_hours} hours.

    **What happens when it expires:**
    - I won't be able to access your #{provider_name} data
    - Email and calendar features will be disabled
    - Automation rules will be paused

    **To prevent this:**
    1. Go to Settings → Integrations
    2. Click "Reconnect #{provider_name}"
    3. Authorize the app again

    This will refresh your connection and prevent any interruption.
    """

    create_notification_message(user, message, "token_expiring_soon")
  end

  defp create_notification_message(user, content, notification_type) do
    # Create a system conversation for notifications
    {:ok, conversation} = Chat.create_conversation(%{
      user_id: user.id,
      title: "System Notifications"
    })

    # Create the notification message
    Chat.create_message(conversation.id, %{
      role: "assistant",
      content: content,
      metadata: %{
        notification_type: notification_type,
        system_message: true
      }
    })
  end

  # Schedule the token monitor to run every hour
  def schedule_token_monitoring() do
    %{}
    |> new(schedule: {:extended, "0 * * * *"}) # Every hour
    |> Oban.insert()
  end
end
