defmodule AdvisorAi.Workers.EmailSyncWorker do
  use Oban.Worker, queue: :ai_processing

  alias AdvisorAi.Accounts
  alias AdvisorAi.Integrations.Gmail
  alias AdvisorAi.Repo
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Get all users with Google tokens
    users_with_google = get_users_with_google_tokens()

    # Sync emails for each user with intelligent processing
    Enum.each(users_with_google, fn user ->
      case Gmail.sync_emails_intelligent(user, max_results: 1000) do
        {:ok, result} ->
          Logger.info("Intelligent email sync completed for user #{user.id}: #{result}")

        {:error, reason} ->
          Logger.error("Intelligent email sync failed for user #{user.id}: #{reason}")
      end
    end)

    :ok
  end

  defp get_users_with_google_tokens do
    import Ecto.Query

    Accounts.User
    |> where([u], not is_nil(u.google_access_token))
    |> Repo.all()
  end

  # Schedule periodic email sync (every 30 minutes)
  def schedule_periodic_sync do
    %{}
    |> new(schedule: {:extended, "*/30 * * * *"})
    |> Oban.insert()
  end
end
