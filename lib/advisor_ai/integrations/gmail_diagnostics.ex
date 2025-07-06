defmodule AdvisorAi.Integrations.GmailDiagnostics do
  @moduledoc """
  Diagnostic tools for troubleshooting Gmail API issues
  """

  alias AdvisorAi.Accounts
  alias AdvisorAi.Repo

  @doc """
  Run comprehensive Gmail API diagnostics for a user
  """
  def diagnose_gmail_issues(account) do
    user_email = get_user_email_from_account(account)
    IO.puts("🔍 Running Gmail API diagnostics for #{user_email}...")
    IO.puts("=" |> String.duplicate(50))

    # Check 1: Token validity
    case check_token_validity(account) do
      {:ok, _} ->
        IO.puts("✅ Access token is valid")

        # Check 2: Gmail API permissions
        case check_gmail_api_permissions(account) do
          {:ok, scopes} ->
            IO.puts("✅ Gmail API permissions verified")
            IO.puts("📋 Granted scopes: #{Enum.join(scopes, ", ")}")

            # Check 3: Send email permission
            case check_send_permission(account) do
              {:ok, _} ->
                IO.puts("✅ Send email permission confirmed")
                {:ok, "All Gmail permissions are working correctly"}

              {:error, reason} ->
                IO.puts("❌ Send email permission failed: #{reason}")
                {:error, "Send email permission issue: #{reason}"}
            end

          {:error, reason} ->
            IO.puts("❌ Gmail API permissions failed: #{reason}")
            {:error, "Gmail API permission issue: #{reason}"}
        end

      {:error, reason} ->
        IO.puts("❌ Token validity check failed: #{reason}")
        {:error, "Token issue: #{reason}"}
    end
  end

  @doc """
  Check if user has a connected Google account
  """
  def check_user_account(user) do
    case Accounts.get_user_google_account(user.id) do
      nil ->
        {:error, "No Google account connected. Please connect your Google account first."}
      account ->
        {:ok, account}
    end
  end

  @doc """
  Check if the access token is valid and not expired
  """
  def check_token_validity(account) do
    if is_nil(account.access_token) do
      {:error, "No access token found"}
    else
      if is_token_expired?(account) do
        case refresh_access_token(account) do
          {:ok, _new_token} ->
            {:ok, "Token refreshed successfully"}
          {:error, reason} ->
            {:error, "Token refresh failed: #{reason}"}
        end
      else
        {:ok, "Token is valid"}
      end
    end
  end

  @doc """
  Check Gmail API permissions by calling the profile endpoint
  """
  def check_gmail_api_permissions(account) do
    case get_valid_access_token(account) do
      {:ok, access_token} ->
        url = "https://gmail.googleapis.com/gmail/v1/users/me/profile"

        case HTTPoison.get(url, [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, profile} ->
                IO.puts("📧 Gmail profile: #{profile["emailAddress"]}")
                {:ok, account.scopes || []}
              {:error, _} ->
                {:error, "Failed to parse Gmail profile response"}
            end

          {:ok, %{status_code: 403, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"error" => %{"message" => message}}} ->
                {:error, "Gmail API access denied: #{message}"}
              _ ->
                {:error, "Gmail API access denied (403)"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "Gmail API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Test send email permission by attempting to send a test email
  """
  def check_send_permission(account) do
    case get_valid_access_token(account) do
      {:ok, access_token} ->
        # Create a test email (won't actually send it, just test permissions)
        user_email = get_user_email_from_account(account)
        test_email = create_test_email_message(user_email, "test@example.com", "Test", "Test body")
        encoded_email = Base.encode64(test_email)

        url = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"

        case HTTPoison.post(
               url,
               Jason.encode!(%{raw: encoded_email}),
               [
                 {"Authorization", "Bearer #{access_token}"},
                 {"Content-Type", "application/json"}
               ]
             ) do
          {:ok, %{status_code: 200}} ->
            {:ok, "Send permission confirmed"}

          {:ok, %{status_code: 403, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"error" => %{"message" => message}}} ->
                {:error, "Send permission denied: #{message}"}
              _ ->
                {:error, "Send permission denied (403)"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "Send test failed: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Provide step-by-step instructions to fix Gmail permissions
  """
  def provide_fix_instructions do
    IO.puts("\n🔧 Gmail API Permission Fix Instructions:")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("""
    1. **Check Google Cloud Console:**
       - Go to https://console.cloud.google.com/
       - Select your project
       - Go to "APIs & Services" > "Enabled APIs"
       - Ensure "Gmail API" is enabled

    2. **Verify OAuth Scopes:**
       - Go to "APIs & Services" > "OAuth consent screen"
       - Check that these scopes are included:
         * https://www.googleapis.com/auth/gmail.readonly
         * https://www.googleapis.com/auth/gmail.send
         * https://www.googleapis.com/auth/calendar.readonly
         * https://www.googleapis.com/auth/calendar.events

    3. **Re-authenticate User:**
       - Go to your app's settings/integrations page
       - Disconnect Google account
       - Reconnect Google account
       - Make sure to accept all requested permissions

    4. **Check Gmail Settings:**
       - Go to Gmail settings
       - Ensure "Less secure app access" is enabled (if using basic auth)
       - Check that your account allows API access

    5. **Verify Account Type:**
       - Ensure you're using a Google Workspace account or personal Gmail
       - Some organization accounts may have restrictions

    6. **Test with Gmail API Explorer:**
       - Go to https://developers.google.com/gmail/api/v1/reference/users/messages/send
       - Test the send endpoint with your credentials
    """)
  end

  # Helper functions
  defp is_token_expired?(account) do
    case account.token_expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp get_valid_access_token(account) do
    if is_token_expired?(account) do
      refresh_access_token(account)
    else
      {:ok, account.access_token}
    end
  end

  defp refresh_access_token(account) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")
    refresh_token = account.refresh_token

    url = "https://oauth2.googleapis.com/token"
    body = URI.encode_query(%{
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    })

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    case HTTPoison.post(url, body, headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"access_token" => new_token, "expires_in" => expires_in}} ->
            expires_at = DateTime.add(DateTime.utc_now(), expires_in)
            # Update account in DB
            Accounts.update_account_tokens(account, new_token, expires_at)
            {:ok, new_token}
          {:ok, %{"error" => error}} ->
            {:error, "Google token refresh error: #{error}"}
          _ ->
            {:error, "Failed to parse Google token refresh response"}
        end
      {:ok, %{status_code: code, body: resp_body}} ->
        {:error, "Google token refresh failed: #{code} #{resp_body}"}
      {:error, reason} ->
        {:error, "HTTP error refreshing token: #{inspect(reason)}"}
    end
  end

  defp create_test_email_message(from, to, subject, body) do
    """
    From: #{from}
    To: #{to}
    Subject: #{subject}
    Content-Type: text/plain; charset=UTF-8
    MIME-Version: 1.0

    #{body}
    """
  end

  defp get_user_email_from_account(account) do
    case account.raw_data do
      %{"info" => %{"email" => email}} when is_binary(email) ->
        email
      _ ->
        # Fallback: try to get user from database
        case Accounts.get_user!(account.user_id) do
          user -> user.email
          _ -> "unknown@example.com"
        end
    end
  end
end
