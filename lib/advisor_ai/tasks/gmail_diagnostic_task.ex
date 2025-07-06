defmodule AdvisorAi.Tasks.GmailDiagnosticTask do
  @moduledoc """
  Task to run Gmail API diagnostics
  """

  alias AdvisorAi.Accounts
  alias AdvisorAi.Integrations.GmailDiagnostics

  def run do
    IO.puts("🔍 Gmail API Diagnostic Tool")
    IO.puts("=" |> String.duplicate(50))

    # Get all accounts with Google tokens
    accounts = get_accounts_with_google_tokens()

    if length(accounts) == 0 do
      IO.puts("❌ No users found with connected Google accounts")
      IO.puts("\nTo fix this:")
      IO.puts("1. Start your Phoenix server: mix phx.server")
      IO.puts("2. Go to http://localhost:4000")
      IO.puts("3. Sign up/login and connect your Google account")
      IO.puts("4. Run this diagnostic again")
    else
      IO.puts("Found #{length(accounts)} user(s) with Google accounts:")

      Enum.each(accounts, fn account ->
        user = Accounts.get_user!(account.user_id)
        IO.puts("\n📧 Testing user: #{user.email}")
        IO.puts("-" |> String.duplicate(30))

        case GmailDiagnostics.diagnose_gmail_issues(account) do
          {:ok, message} ->
            IO.puts("✅ #{message}")
          {:error, reason} ->
            IO.puts("❌ #{reason}")
            IO.puts("\n🔧 Suggested fixes:")
            GmailDiagnostics.provide_fix_instructions()
        end
      end)
    end
  end

  def run_for_user(email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        IO.puts("❌ User with email #{email} not found")
      user ->
        IO.puts("🔍 Running diagnostics for #{user.email}")
        IO.puts("=" |> String.duplicate(50))

        case GmailDiagnostics.diagnose_gmail_issues(user) do
          {:ok, message} ->
            IO.puts("✅ #{message}")
          {:error, reason} ->
            IO.puts("❌ #{reason}")
            IO.puts("\n🔧 Suggested fixes:")
            GmailDiagnostics.provide_fix_instructions()
        end
    end
  end

  defp get_accounts_with_google_tokens do
    import Ecto.Query

    AdvisorAi.Accounts.Account
    |> where([a], a.provider == "google" and not is_nil(a.access_token))
    |> AdvisorAi.Repo.all()
  end
end
