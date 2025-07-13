defmodule AdvisorAi.Integrations.Gmail do
  @moduledoc """
  Gmail integration for reading and sending emails, syncing emails, and intelligent email features.
  """

  alias AdvisorAi.AI.{VectorEmbedding, GroqClient}
  alias AdvisorAi.Repo
  alias AdvisorAi.Accounts

  import Ecto.Query
  require Logger

  @gmail_api_url "https://gmail.googleapis.com/gmail/v1/users/me"
  # OpenAI client will be configured at runtime

  def search_emails(user, query) do
    if is_nil(query) or query == "" do
      {:error, "Search query cannot be empty"}
    else
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
                  emails =
                    Enum.map(messages, fn %{"id" => id} ->
                      get_email_details(user, id)
                    end)
                    |> Enum.filter(fn
                      {:ok, _email} -> true
                      {:error, _} -> false
                    end)
                    |> Enum.map(fn {:ok, email} -> email end)

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
  end

  def get_recent_emails(user, max_results \\ 10) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@gmail_api_url}/messages?maxResults=#{max_results}"

        case HTTPoison.get(url, [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"messages" => messages}} ->
                # Get full email details for each message
                emails =
                  Enum.map(messages, fn %{"id" => id} ->
                    get_email_details(user, id)
                  end)
                  |> Enum.filter(fn
                    {:ok, _email} -> true
                    {:error, _} -> false
                  end)
                  |> Enum.map(fn {:ok, email} -> email end)

                {:ok, emails}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse recent emails: #{reason}"}
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
  Delete a Gmail message (moves to trash).
  """
  def delete_message(user, message_id) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@gmail_api_url}/messages/#{message_id}/trash"

        case HTTPoison.post(url, "", [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200}} ->
            {:ok, "Message moved to trash"}

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
  Modify Gmail message labels (mark as read/unread, add/remove labels).
  """
  def modify_message(user, message_id, add_label_ids \\ [], remove_label_ids \\ []) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@gmail_api_url}/messages/#{message_id}/modify"

        request_body = %{
          addLabelIds: add_label_ids,
          removeLabelIds: remove_label_ids
        }

        case HTTPoison.post(url, Jason.encode!(request_body), [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200}} ->
            {:ok, "Message labels updated"}

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
  Create a draft email.
  """
  def create_draft(user, to, subject, body) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # Create email message
        email_content = create_email_message(user.email, to, subject, body)
        encoded_email = Base.encode64(email_content)

        url = "#{@gmail_api_url}/drafts"

        request_body = %{
          message: %{
            raw: encoded_email
          }
        }

        case HTTPoison.post(url, Jason.encode!(request_body), [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200}} ->
            {:ok, "Draft created successfully"}

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
  Get Gmail profile information.
  """
  def get_profile(user) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@gmail_api_url}/profile"

        case HTTPoison.get(url, [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, profile} ->
                {:ok, profile}

              {:error, reason} ->
                {:error, "Failed to parse profile: #{reason}"}
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
        # First, check if we have the right permissions
        case check_gmail_permissions(user, access_token) do
          {:ok, _} ->
            # Create email message
            email_content = create_email_message(user.email, to, subject, body)
            encoded_email = Base.encode64(email_content)

            url = "#{@gmail_api_url}/messages/send"

            case HTTPoison.post(
                   url,
                   Jason.encode!(%{
                     raw: encoded_email
                   }),
                   [
                     {"Authorization", "Bearer #{access_token}"},
                     {"Content-Type", "application/json"}
                   ]
                 ) do
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

              {:ok, %{status_code: 403, body: body}} ->
                case Jason.decode(body) do
                  {:ok, %{"error" => %{"message" => message}}} ->
                    {:error,
                     "Gmail permission denied: #{message}. Please check your Gmail API permissions and ensure you have 'gmail.send' scope."}

                  _ ->
                    {:error,
                     "Gmail permission denied (403). Please check your Gmail API permissions."}
                end

              {:ok, %{status_code: status_code, body: body}} ->
                require Logger
                Logger.error("Gmail API error #{status_code}: #{body}")
                {:error, "Failed to send email: #{status_code} - #{body}"}

              {:error, reason} ->
                {:error, "HTTP error: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Gmail permissions check failed: #{reason}"}
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

  def sync_emails_intelligent(user, opts \\ []) do
    # Sync more emails
    max_results = Keyword.get(opts, :max_results, 1000)
    query = Keyword.get(opts, :query, "")

    Logger.info("Starting intelligent email sync for user #{user.email}")

    case get_access_token(user) do
      {:ok, access_token} ->
        sync_emails_with_token(user, access_token, max_results, query)

      {:error, reason} ->
        Logger.error("Failed to get access token for email sync: #{reason}")
        {:error, reason}
    end
  end

  def find_contact_by_name(user, name) do
    # Try HubSpot first
    case AdvisorAi.Integrations.HubSpot.search_contacts(user, name) do
      {:ok, [hubspot_contact | _]} ->
        {:ok,
         %{
           name:
             "#{hubspot_contact["properties"]["firstname"]} #{hubspot_contact["properties"]["lastname"]}",
           email: hubspot_contact["properties"]["email"],
           phone: hubspot_contact["properties"]["phone"],
           company: hubspot_contact["properties"]["company"],
           title: hubspot_contact["properties"]["jobtitle"],
           source: "hubspot"
         }}

      {:ok, []} ->
        # Fallback to Gmail search
        case search_emails_by_contact_name(user, name) do
          {:ok, email_data} ->
            {:ok,
             %{
               name: name,
               email: extract_email_from_gmail_data(email_data),
               phone: nil,
               company: nil,
               title: nil,
               source: "gmail_search"
             }}

          {:error, _reason} ->
            {:error, "Contact '#{name}' not found in HubSpot or Gmail"}
        end

      {:error, hubspot_reason} ->
        # If HubSpot fails, try Gmail
        case search_emails_by_contact_name(user, name) do
          {:ok, email_data} ->
            {:ok,
             %{
               name: name,
               email: extract_email_from_gmail_data(email_data),
               phone: nil,
               company: nil,
               title: nil,
               source: "gmail_search"
             }}

          {:error, gmail_reason} ->
            {:error,
             "Could not find contact '#{name}'. HubSpot error: #{hubspot_reason}, Gmail error: #{gmail_reason}"}
        end
    end
  end

  defp search_emails_by_contact_name(user, name) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # Search Gmail for emails from/to this person
        query = "from:#{name} OR to:#{name}"
        url = "#{@gmail_api_url}/messages?q=#{URI.encode(query)}&maxResults=1"

        case HTTPoison.get(url, [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"messages" => [message | _]}} ->
                case get_email_details_with_token(user, message["id"], access_token) do
                  email_data when is_map(email_data) ->
                    {:ok, email_data}

                  {:error, reason} ->
                    {:error, "Failed to get email details: #{reason}"}
                end

              {:ok, _} ->
                {:error, "No emails found for #{name}"}

              {:error, reason} ->
                {:error, "Failed to parse Gmail response: #{reason}"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "Gmail API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  defp extract_email_from_gmail_data(email_data) do
    # Extract email from Gmail data
    case email_data do
      %{from: from} when is_binary(from) ->
        # Extract email from "Name <email@domain.com>" format
        case Regex.run(~r/<([^>]+)>/, from) do
          [_, email] -> email
          nil -> from
        end

      _ ->
        "unknown@example.com"
    end
  end

  def search_emails_intelligent(user, query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 100)

    case get_access_token(user) do
      {:ok, access_token} ->
        search_emails_with_context(user, access_token, query, max_results)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  def compose_smart_email(user, recipient_name, subject, context, opts \\ []) do
    # First, find the recipient by name
    case find_contact_by_name(user, recipient_name) do
      {:ok, contact} ->
        # Generate intelligent email content based on context
        email_content = generate_smart_email_content(subject, context, contact)

        # Send the email
        send_email(user, contact.email, subject, email_content)

      {:error, reason} ->
        {:error, "Could not find contact '#{recipient_name}': #{reason}"}
    end
  end

  def send_meeting_reminder(user, recipient_name, meeting_details, opts \\ []) do
    reminder_time = Keyword.get(opts, :reminder_time, "1 hour before")

    case find_contact_by_name(user, recipient_name) do
      {:ok, contact} ->
        subject = "Meeting Reminder: #{meeting_details.title}"
        body = generate_meeting_reminder_content(meeting_details, contact, reminder_time)

        send_email(user, contact.email, subject, body)

      {:error, reason} ->
        {:error, "Could not find contact '#{recipient_name}': #{reason}"}
    end
  end

  def get_email_details(user, message_id) do
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
        # Skip emails sent by the user/app itself
        if String.downcase(email_data.from || "") == String.downcase(user.email || "") do
          Logger.info("Skipping email sent by self: #{email_data.from}")
          :ok
          # NEW: Also skip sending a meeting response to the user's own email address
        else
          # Check if already processed
          already_processed =
            AdvisorAi.Repo.get_by(
              AdvisorAi.Integrations.ProcessedEmail,
              user_id: user.id,
              message_id: message_id
            )

          if already_processed do
            Logger.info("Skipping already processed email #{message_id}")
            :ok
          else
            Logger.info(
              "Processing email: id=#{message_id}, from=#{email_data.from}, subject=#{email_data.subject}"
            )

            # Try to store in vector embeddings (but don't fail if it doesn't work)
            case store_email_embedding(user, email_data) do
              {:ok, _} ->
                Logger.info("✅ Email embedding stored successfully")

              {:error, reason} ->
                Logger.warning("⚠️ Email embedding failed, continuing without it: #{reason}")

              _ ->
                Logger.warning("⚠️ Email embedding failed, continuing without it")
            end

            # Improved meeting inquiry response
            if is_meeting_inquiry?(email_data) do
              # Only send a response if the sender is NOT the connected user's own email
              if String.downcase(email_data.from || "") != String.downcase(user.email || "") do
                meetings = AdvisorAi.Integrations.Calendar.get_upcoming_meetings(user)
                response = format_meeting_response(meetings, user)
                send_email(user, email_data.from, "Your Upcoming Meetings", response)
              else
                Logger.info(
                  "Not sending meeting response to own connected email: #{email_data.from}"
                )
              end
            end

            AdvisorAi.AI.Agent.handle_trigger(user, "email_received", email_data)

            # Mark as processed LAST
            %AdvisorAi.Integrations.ProcessedEmail{}
            |> AdvisorAi.Integrations.ProcessedEmail.changeset(%{
              user_id: user.id,
              message_id: message_id
            })
            |> AdvisorAi.Repo.insert()
          end
        end

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

    {:ok,
     %{
       id: email_data["id"],
       internalDate: email_data["internalDate"],
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
        safe_decode64(data)

      %{"parts" => parts} ->
        # Handle multipart emails
        Enum.find_value(parts, "", fn part ->
          case part do
            %{"mimeType" => "text/plain", "body" => %{"data" => data}} ->
              safe_decode64(data)

            %{"mimeType" => "text/html", "body" => %{"data" => data}} ->
              # Convert HTML to text (simplified)
              safe_decode64(data)
              |> String.replace(~r/<[^>]*>/, "")

            _ ->
              nil
          end
        end)

      _ ->
        ""
    end
  end

  defp safe_decode64(data) do
    # Handle URL-safe Base64 (replace - and _ with + and /)
    cleaned_data =
      data
      |> String.replace("-", "+")
      |> String.replace("_", "/")
      # Remove whitespace
      |> String.replace(~r/\s+/, "")

    case Base.decode64(cleaned_data) do
      {:ok, decoded} ->
        decoded

      :error ->
        require Logger
        Logger.warning("Failed to decode Base64 email data")
        # Return empty string instead of crashing
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

  defp store_email_embedding(user, email_data) do
    content = "#{email_data.from} to #{email_data.to}: #{email_data.subject}\n#{email_data.body}"

    case get_embedding(content) do
      {:ok, embedding} ->
        if is_list(embedding) and
             (length(embedding) == 1536 or length(embedding) == 768 or length(embedding) == 1024 or
                length(embedding) == 384) do
          case %VectorEmbedding{
                 user_id: user.id,
                 source: "email",
                 content: content,
                 embedding: embedding,
                 metadata: %{
                   from: email_data.from,
                   to: email_data.to,
                   subject: email_data.subject,
                   date: Map.get(email_data, :date, DateTime.utc_now()),
                   type: email_data.type
                 }
               }
               |> VectorEmbedding.changeset(%{})
               |> Repo.insert() do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> {:error, reason}
          end
        else
          require Logger

          Logger.error(
            "Embedding dimension mismatch: got #{length(embedding)}, expected 1536, 768, 1024, or 384. Skipping save."
          )

          {:error, "Embedding dimension mismatch"}
        end

      {:error, reason} ->
        require Logger
        Logger.error("Failed to store email embedding: #{inspect(reason)}")
        {:error, reason}

      other ->
        require Logger
        Logger.error("Unexpected embedding result: #{inspect(other)}")
        {:error, "Unexpected embedding result"}
    end
  end

  defp get_embedding(text) do
    # Use Groq for embeddings (ultra-fast and reliable)
    case AdvisorAi.AI.GroqClient.embeddings(input: text) do
      {:ok, %{"data" => [%{"embedding" => embedding}]}} ->
        {:ok, embedding}

      {:error, reason} ->
        require Logger
        Logger.warning("Groq embedding failed: #{inspect(reason)}")
        {:error, "Failed to generate embedding: #{inspect(reason)}"}
    end
  end

  defp get_access_token(user) do
    case AdvisorAi.Accounts.get_user_google_account(user.id) do
      nil ->
        {:error,
         "You need to connect your Google account in settings before I can access your Gmail."}

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

  defp refresh_access_token(account) do
    client_id = System.get_env("GOOGLE_CLIENT_ID")
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET")
    refresh_token = account.refresh_token

    url = "https://oauth2.googleapis.com/token"

    body =
      URI.encode_query(%{
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
            AdvisorAi.Accounts.update_account_tokens(account, new_token, expires_at)
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

  defp check_gmail_permissions(user, access_token) do
    # Test if we can access Gmail API with the current token
    test_url = "#{@gmail_api_url}/profile"

    case HTTPoison.get(test_url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200}} ->
        {:ok, "Gmail permissions verified"}

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
        {:error, "HTTP error checking permissions: #{reason}"}
    end
  end

  # Private functions for intelligent features

  defp sync_emails_with_token(user, access_token, max_results, query) do
    url = "#{@gmail_api_url}/messages"

    params = %{
      maxResults: max_results,
      q: query
    }

    case HTTPoison.get(
           url,
           [
             {"Authorization", "Bearer #{access_token}"},
             {"Content-Type", "application/json"}
           ],
           params: params
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"messages" => messages}} ->
            sync_messages_to_database(user, messages, access_token)
            {:ok, "Synced #{length(messages)} emails"}

          {:ok, %{"error" => error}} ->
            {:error, "Gmail API error: #{inspect(error)}"}

          _ ->
            {:error, "Failed to parse Gmail API response"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "Gmail API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error syncing emails: #{inspect(reason)}"}
    end
  end

  defp sync_messages_to_database(user, messages, access_token) do
    Enum.each(messages, fn %{"id" => message_id} ->
      case get_email_details_with_token(user, message_id, access_token) do
        email_data when is_map(email_data) ->
          store_email_embedding(user, email_data)

        {:error, reason} ->
          Logger.warning("Failed to sync message #{message_id}: #{reason}")
      end
    end)
  end

  defp get_email_details_with_token(user, message_id, access_token) do
    url = "#{@gmail_api_url}/messages/#{message_id}"

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, message_data} ->
            extract_email_data(message_data)

          {:error, reason} ->
            {:error, "Failed to parse message: #{reason}"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "Gmail API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error getting message: #{inspect(reason)}"}
    end
  end

  defp search_emails_with_context(user, access_token, query, max_results) do
    url = "#{@gmail_api_url}/messages"

    params = %{
      maxResults: max_results,
      q: query
    }

    case HTTPoison.get(
           url,
           [
             {"Authorization", "Bearer #{access_token}"},
             {"Content-Type", "application/json"}
           ],
           params: params
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"messages" => messages}} ->
            get_emails_with_context(messages, access_token)

          {:ok, %{"error" => error}} ->
            {:error, "Gmail API error: #{inspect(error)}"}

          _ ->
            {:error, "Failed to parse Gmail API response"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "Gmail API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error searching emails: #{inspect(reason)}"}
    end
  end

  defp get_emails_with_context(messages, access_token) do
    emails_with_context =
      Enum.map(messages, fn %{"id" => message_id} ->
        case get_email_details_with_token(nil, message_id, access_token) do
          email_data when is_map(email_data) ->
            email_data

          {:error, _} ->
            nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    {:ok, emails_with_context}
  end

  defp generate_smart_email_content(subject, context, contact) do
    # Use AI to generate intelligent email content
    prompt = """
    Generate a professional email with the following details:
    - Subject: #{subject}
    - Recipient: #{contact.name} (#{contact.email})
    - Context: #{context}

    Please write a well-structured, professional email that is:
    1. Appropriate for the context
    2. Personalized to the recipient
    3. Clear and concise
    4. Professional in tone
    """

    case AdvisorAi.AI.GroqClient.chat_completion([
           %{role: "user", content: prompt}
         ]) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        content

      _ ->
        # Fallback to simple template
        """
        Hi #{contact.name},

        #{context}

        Best regards,
        """
    end
  end

  defp extract_email_data(message_data) do
    # Extract email data from Gmail API response
    headers = get_in(message_data, ["payload", "headers"]) || []

    from = get_header_value(headers, "From") || "unknown@example.com"
    to = get_header_value(headers, "To") || "unknown@example.com"
    subject = get_header_value(headers, "Subject") || "No Subject"
    date = get_header_value(headers, "Date")

    # Parse date if available
    parsed_date =
      case date do
        nil ->
          DateTime.utc_now()

        date_str ->
          case DateTime.from_iso8601(date_str) do
            {:ok, dt, _} -> dt
            _ -> DateTime.utc_now()
          end
      end

    body = extract_email_body(get_in(message_data, ["payload"]) || %{})

    %{
      from: from,
      to: to,
      subject: subject,
      body: body,
      date: parsed_date,
      type: "received"
    }
  end

  defp generate_meeting_reminder_content(meeting_details, contact, reminder_time) do
    """
    Hi #{contact.name},

    This is a friendly reminder about our upcoming meeting:

    **Meeting Details:**
    - Title: #{meeting_details.title}
    - Date: #{meeting_details.date}
    - Time: #{meeting_details.time}
    - Duration: #{meeting_details.duration || "1 hour"}

    **Agenda:**
    #{meeting_details.agenda || "To be discussed during the meeting"}

    Please let me know if you need to reschedule or if you have any questions.

    Looking forward to our meeting!

    Best regards,
    """
  end

  def compose_draft(user, to, subject, body) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # Create email message
        email_content = create_email_message(user.email, to, subject, body)
        encoded_email = Base.encode64(email_content)

        url = "#{@gmail_api_url}/drafts"

        case HTTPoison.post(
               url,
               Jason.encode!(%{
                 message: %{
                   raw: encoded_email
                 }
               }),
               [
                 {"Authorization", "Bearer #{access_token}"},
                 {"Content-Type", "application/json"}
               ]
             ) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, draft_data} ->
                {:ok, "Draft created successfully with ID: #{get_in(draft_data, ["id"])}"}

              {:error, _} ->
                {:ok, "Draft created successfully"}
            end

          {:ok, %{status_code: 403, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"error" => %{"message" => message}}} ->
                {:error,
                 "Gmail permission denied: #{message}. Please check your Gmail API permissions and ensure you have 'gmail.compose' scope."}

              _ ->
                {:error,
                 "Gmail permission denied (403). Please check your Gmail API permissions."}
            end

          {:ok, %{status_code: status_code, body: body}} ->
            require Logger
            Logger.error("Gmail API error #{status_code}: #{body}")
            {:error, "Failed to create draft: #{status_code} - #{body}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Set up Gmail push notifications to trigger webhooks when new emails arrive.
  This enables automatic email processing for the automation system.
  """
  def setup_push_notifications(user, webhook_url) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # First, stop any existing watch
        stop_watch(user)

        # Set up new watch
        url = "#{@gmail_api_url}/watch"

        request_body = %{
          topicName: "projects/#{get_project_id()}/topics/gmail-notifications",
          labelIds: ["INBOX"],
          labelFilterAction: "include"
        }

        case HTTPoison.post(url, Jason.encode!(request_body), [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"historyId" => history_id, "expiration" => expiration}} ->
                Logger.info(
                  "Gmail push notifications set up successfully. History ID: #{history_id}, Expires: #{expiration}"
                )

                {:ok, %{history_id: history_id, expiration: expiration}}

              {:ok, response} ->
                Logger.info("Gmail watch response: #{inspect(response)}")
                {:ok, response}

              {:error, reason} ->
                {:error, "Failed to parse watch response: #{reason}"}
            end

          {:ok, %{status_code: 401}} ->
            {:error, "Gmail API authentication failed. Please reconnect your Gmail account."}

          {:ok, %{status_code: status_code, body: body}} ->
            Logger.error("Gmail API error #{status_code}: #{body}")
            {:error, "Gmail API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stop Gmail push notifications.
  """
  def stop_watch(user) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@gmail_api_url}/stop"

        case HTTPoison.post(url, "", [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200}} ->
            Logger.info("Gmail watch stopped successfully")
            {:ok, "Watch stopped"}

          {:ok, %{status_code: status_code}} ->
            Logger.warn("Failed to stop Gmail watch: #{status_code}")
            {:error, "Failed to stop watch: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get Gmail history to process new emails since last check.
  This is used when webhooks are received to get the actual email data.
  """
  def get_history(user, start_history_id) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url =
          "#{@gmail_api_url}/history?startHistoryId=#{start_history_id}&historyTypes=messageAdded"

        case HTTPoison.get(url, [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"history" => history}} ->
                # Process new messages
                new_messages =
                  history
                  |> Enum.flat_map(fn %{"messagesAdded" => messages_added} ->
                    Enum.map(messages_added, fn %{"message" => %{"id" => id}} ->
                      get_email_details(user, id)
                    end)
                  end)
                  |> Enum.filter(fn
                    {:ok, _email} -> true
                    {:error, _} -> false
                  end)
                  |> Enum.map(fn {:ok, email} -> email end)

                {:ok, new_messages}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse history: #{reason}"}
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

  # Get Google Cloud project ID from environment or config
  defp get_project_id() do
    Application.get_env(:advisor_ai, :google_project_id, "advisor-ai-project")
  end

  # Helper to detect meeting inquiry
  defp is_meeting_inquiry?(email_data) do
    subject = String.downcase(email_data.subject || "")
    body = String.downcase(email_data.body || "")

    Enum.any?([subject, body], fn text ->
      String.contains?(text, "meeting") or String.contains?(text, "calendar") or
        String.contains?(text, "appointment")
    end)
  end

  # Helper to format a professional meeting response
  defp format_meeting_response([], user) do
    "Hi,\n\nYou currently have no upcoming meetings scheduled.\n\nIf you need to book a meeting, just let me know!\n\nBest regards,\n#{user.name || user.email}"
  end

  defp format_meeting_response(meetings, user) do
    meeting_lines =
      meetings
      |> Enum.map(fn m ->
        "• #{m.title} with #{m.attendees |> Enum.join(", ")} on #{format_datetime(m.start_time)} to #{format_datetime(m.end_time)}"
      end)
      |> Enum.join("\n")

    "Hi,\n\nHere are your upcoming meetings:\n\n#{meeting_lines}\n\nIf you need to reschedule or have any questions, feel free to reply.\n\nBest regards,\n#{user.name || user.email}"
  end

  defp format_datetime(nil), do: "(unknown time)"

  defp format_datetime(dt) do
    dt
    |> DateTime.to_string()
    |> String.replace("T", " at ")
    |> String.replace(~r/\+\d{2}:\d{2}$/, "")
  end
end
