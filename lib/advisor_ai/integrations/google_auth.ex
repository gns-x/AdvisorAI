defmodule AdvisorAi.Integrations.GoogleAuth do
  @moduledoc """
  Google OAuth authentication and token management.
  Handles access tokens for all Google services including Gmail, Calendar, Contacts, Drive, etc.
  """

  alias AdvisorAi.Accounts

  @doc """
  Get a valid access token for a user.
  Handles token refresh if needed.
  """
  def get_access_token(user) do
    case Accounts.get_user_google_account(user.id) do
      nil ->
        {:error, "No Google access token found. Please reconnect your Google account."}

      account ->
        case account.access_token do
          nil ->
            {:error, "No Google access token found. Please reconnect your Google account."}

          token ->
            # Check if token is expired and refresh if needed
            if is_token_expired?(account) do
              case refresh_access_token(user) do
                {:ok, new_token} -> {:ok, new_token}
                {:error, reason} -> {:error, "Token refresh failed: #{reason}"}
              end
            else
              {:ok, token}
            end
        end
    end
  end

  @doc """
  Refresh an expired access token using the refresh token.
  """
  def refresh_access_token(user) do
    case Accounts.get_user_google_account(user.id) do
      nil ->
        {:error, "No refresh token available. Please reconnect your Google account."}

      account ->
        case account.refresh_token do
          nil ->
            {:error, "No refresh token available. Please reconnect your Google account."}

          refresh_token ->
            do_refresh_token(refresh_token)
        end
    end
  end

  @doc """
  Get user's Google profile information.
  """
  def get_user_profile(user) do
    case get_access_token(user) do
      {:ok, access_token} ->
        do_get_user_profile(access_token)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if user has access to specific Google services.
  """
  def check_service_access(user, services) when is_list(services) do
    case get_access_token(user) do
      {:ok, access_token} ->
        Enum.reduce_while(services, {:ok, %{}}, fn service, {:ok, acc} ->
          case check_single_service_access(access_token, service) do
            {:ok, result} -> {:cont, {:ok, Map.put(acc, service, result)}}
            {:error, reason} -> {:halt, {:error, "#{service}: #{reason}"}}
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get comprehensive user information from all connected Google services.
  """
  def get_comprehensive_user_info(user) do
    case get_access_token(user) do
      {:ok, access_token} ->
        with {:ok, profile} <- do_get_user_profile(access_token),
             {:ok, contacts_count} <- get_contacts_count(access_token),
             {:ok, calendar_count} <- get_calendar_count(access_token),
             {:ok, drive_info} <- get_drive_info(access_token),
             {:ok, gmail_info} <- get_gmail_info(access_token) do
          {:ok, %{
            profile: profile,
            contacts_count: contacts_count,
            calendar_count: calendar_count,
            drive_info: drive_info,
            gmail_info: gmail_info
          }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp is_token_expired?(account) do
    case account.token_expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp do_refresh_token(refresh_token) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")

    url = "https://oauth2.googleapis.com/token"

    body = URI.encode_query(%{
      "client_id" => client_id,
      "client_secret" => client_secret,
      "refresh_token" => refresh_token,
      "grant_type" => "refresh_token"
    })

    case HTTPoison.post(url, body, [
           {"Content-Type", "application/x-www-form-urlencoded"}
         ]) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"access_token" => access_token, "expires_in" => expires_in}} ->
            expires_at = DateTime.add(DateTime.utc_now(), expires_in)
            # Update account in DB
            case Accounts.get_user_google_account_by_refresh_token(refresh_token) do
              nil -> {:error, "Account not found for refresh token"}
              account ->
                case Accounts.update_account_tokens(account, access_token, expires_at) do
                  {:ok, _} -> {:ok, access_token}
                  {:error, _} -> {:error, "Failed to update account tokens"}
                end
            end

          {:ok, %{"access_token" => access_token}} ->
            # Fallback for responses without expires_in
            {:ok, access_token}

          {:ok, %{"error" => error}} ->
            {:error, "Token refresh failed: #{error}"}

          _ ->
            {:error, "Invalid response format"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "Token refresh failed: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error refreshing token: #{inspect(reason)}"}
    end
  end

  defp do_get_user_profile(access_token) do
    url = "https://www.googleapis.com/oauth2/v2/userinfo"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, profile} ->
            {:ok, %{
              id: profile["id"],
              email: profile["email"],
              name: profile["name"],
              given_name: profile["given_name"],
              family_name: profile["family_name"],
              picture: profile["picture"],
              locale: profile["locale"],
              verified_email: profile["verified_email"]
            }}

          {:ok, %{"error" => error}} ->
            {:error, "Profile API error: #{inspect(error)}"}

          _ ->
            {:error, "Invalid response format"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "Profile API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error getting profile: #{inspect(reason)}"}
    end
  end

  defp check_single_service_access(access_token, service) do
    case service do
      "gmail" -> check_gmail_access(access_token)
      "calendar" -> check_calendar_access(access_token)
      "contacts" -> check_contacts_access(access_token)
      "drive" -> check_drive_access(access_token)
      _ -> {:error, "Unknown service: #{service}"}
    end
  end

  defp check_gmail_access(access_token) do
    url = "https://gmail.googleapis.com/gmail/v1/users/me/profile"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200}} ->
        {:ok, "Gmail access confirmed"}

      {:ok, %{status_code: 401}} ->
        {:error, "Gmail access denied"}

      {:ok, %{status_code: status_code}} ->
        {:error, "Gmail API error: #{status_code}"}

      {:error, reason} ->
        {:error, "HTTP error checking Gmail: #{inspect(reason)}"}
    end
  end

  defp check_calendar_access(access_token) do
    url = "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=1"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200}} ->
        {:ok, "Calendar access confirmed"}

      {:ok, %{status_code: 401}} ->
        {:error, "Calendar access denied"}

      {:ok, %{status_code: status_code}} ->
        {:error, "Calendar API error: #{status_code}"}

      {:error, reason} ->
        {:error, "HTTP error checking Calendar: #{inspect(reason)}"}
    end
  end

  defp check_contacts_access(access_token) do
    url = "https://people.googleapis.com/v1/people/me/connections?pageSize=1"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200}} ->
        {:ok, "Contacts access confirmed"}

      {:ok, %{status_code: 401}} ->
        {:error, "Contacts access denied"}

      {:ok, %{status_code: status_code}} ->
        {:error, "Contacts API error: #{status_code}"}

      {:error, reason} ->
        {:error, "HTTP error checking Contacts: #{inspect(reason)}"}
    end
  end

  defp check_drive_access(access_token) do
    url = "https://www.googleapis.com/drive/v3/files?pageSize=1"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200}} ->
        {:ok, "Drive access confirmed"}

      {:ok, %{status_code: 401}} ->
        {:error, "Drive access denied"}

      {:ok, %{status_code: status_code}} ->
        {:error, "Drive API error: #{status_code}"}

      {:error, reason} ->
        {:error, "HTTP error checking Drive: #{inspect(reason)}"}
    end
  end

  defp get_contacts_count(access_token) do
    url = "https://people.googleapis.com/v1/people/me/connections?pageSize=1"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"totalItems" => total_items}} ->
            {:ok, total_items}

          _ ->
            {:ok, "Unknown"}
        end

      _ ->
        {:ok, "Unable to retrieve"}
    end
  end

  defp get_calendar_count(access_token) do
    url = "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=1"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"items" => items}} ->
            {:ok, length(items)}

          _ ->
            {:ok, "Unknown"}
        end

      _ ->
        {:ok, "Unable to retrieve"}
    end
  end

  defp get_drive_info(access_token) do
    url = "https://www.googleapis.com/drive/v3/about?fields=storageQuota"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"storageQuota" => quota}} ->
            {:ok, %{
              total: quota["limit"],
              used: quota["usage"],
              available: quota["limit"] - quota["usage"]
            }}

          _ ->
            {:ok, "Unable to retrieve storage info"}
        end

      _ ->
        {:ok, "Unable to retrieve"}
    end
  end

  defp get_gmail_info(access_token) do
    url = "https://gmail.googleapis.com/gmail/v1/users/me/profile"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, profile} ->
            {:ok, %{
              email_address: profile["emailAddress"],
              messages_total: profile["messagesTotal"],
              threads_total: profile["threadsTotal"],
              history_id: profile["historyId"]
            }}

          _ ->
            {:ok, "Unable to retrieve Gmail info"}
        end

      _ ->
        {:ok, "Unable to retrieve"}
    end
  end
end
