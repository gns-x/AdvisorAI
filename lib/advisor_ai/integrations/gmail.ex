defmodule AdvisorAi.Integrations.Gmail do
  @moduledoc """
  Gmail integration for reading and sending emails
  """

  alias AdvisorAi.AI.{VectorEmbedding, OllamaClient}
  alias AdvisorAi.Repo

  @gmail_api_url "https://gmail.googleapis.com/gmail/v1/users/me"
  # OpenAI client will be configured at runtime

  def search_emails(user, query) do
    case get_access_token(user) do
      {:ok, access_token} ->
        search_url = "#{@gmail_api_url}/messages?q=#{URI.encode(query)}"

        case HTTPoison.get(search_url, [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"messages" => messages}} ->
                # Get full email details for each message
                emails = Enum.map(messages, fn %{"id" => id} ->
                  get_email_details(user, id)
                end)
                {:ok, emails}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse search results: #{reason}"}
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

  def send_email(user, to, subject, body) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # Create email message
        email_content = create_email_message(user.email, to, subject, body)
        encoded_email = Base.encode64(email_content)

        url = "#{@gmail_api_url}/messages/send"

        case HTTPoison.post(url, Jason.encode!(%{
          raw: encoded_email
        }), [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200}} ->
            # Store email in vector embeddings for future reference
            store_email_embedding(user, %{
              from: user.email,
              to: to,
              subject: subject,
              body: body,
              type: "sent"
            })
            {:ok, "Email sent successfully"}

          {:ok, %{status_code: status_code}} ->
            {:error, "Failed to send email: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def sync_emails(user) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # Get recent emails
        url = "#{@gmail_api_url}/messages?maxResults=50"

        case HTTPoison.get(url, [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"messages" => messages}} ->
                # Process each email
                Enum.each(messages, fn %{"id" => id} ->
                  process_email(user, id)
                end)
                {:ok, "Synced #{length(messages)} emails"}

              {:ok, _} ->
                {:ok, "No emails to sync"}

              {:error, reason} ->
                {:error, "Failed to parse emails: #{reason}"}
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

  defp get_email_details(user, message_id) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@gmail_api_url}/messages/#{message_id}"

        case HTTPoison.get(url, [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, email_data} ->
                parse_email_data(email_data)

              {:error, reason} ->
                {:error, "Failed to parse email: #{reason}"}
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

  defp process_email(user, message_id) do
    case get_email_details(user, message_id) do
      {:ok, email_data} ->
        # Store in vector embeddings
        store_email_embedding(user, email_data)

        # Trigger agent if needed
        AdvisorAi.AI.Agent.handle_trigger(user, "email_received", email_data)

      {:error, _reason} ->
        :ok
    end
  end

  defp parse_email_data(email_data) do
    headers = email_data["payload"]["headers"] || []

    from = get_header_value(headers, "From")
    to = get_header_value(headers, "To")
    subject = get_header_value(headers, "Subject")
    date = get_header_value(headers, "Date")

    body = extract_email_body(email_data["payload"])

    {:ok, %{
      id: email_data["id"],
      from: from,
      to: to,
      subject: subject,
      date: date,
      body: body,
      type: "received"
    }}
  end

  defp get_header_value(headers, name) do
    case Enum.find(headers, fn header -> header["name"] == name end) do
      nil -> nil
      header -> header["value"]
    end
  end

  defp extract_email_body(payload) do
    case payload do
      %{"body" => %{"data" => data}} when is_binary(data) ->
        Base.decode64!(data)

      %{"parts" => parts} ->
        # Handle multipart emails
        Enum.find_value(parts, "", fn part ->
          case part do
            %{"mimeType" => "text/plain", "body" => %{"data" => data}} ->
              Base.decode64!(data)

            %{"mimeType" => "text/html", "body" => %{"data" => data}} ->
              # Convert HTML to text (simplified)
              Base.decode64!(data)
              |> String.replace(~r/<[^>]*>/, "")

            _ ->
              nil
          end
        end)

      _ ->
        ""
    end
  end

  defp create_email_message(user_email, to, subject, body) do
    """
    From: #{user_email}
    To: #{to}
    Subject: #{subject}
    Content-Type: text/plain; charset=UTF-8
    MIME-Version: 1.0

    #{body}
    """
  end

  defp store_email_embedding(_user, _email_data) do
    # Temporarily disabled embeddings to fix the error
    :ok
  end

    defp get_embedding(_text) do
    # Temporarily disabled embeddings to fix the error
    {:error, "embeddings disabled"}
  end

  defp get_access_token(user) do
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil ->
        {:error, "No Google account connected"}

      account ->
        if is_token_expired?(account) do
          refresh_access_token(account)
        else
          {:ok, account.access_token}
        end
    end
  end

  defp is_token_expired?(account) do
    case account.token_expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp refresh_access_token(_account) do
    # Implement token refresh logic
    # This would use the refresh_token to get a new access_token
    {:error, "Token refresh not implemented"}
  end
end
