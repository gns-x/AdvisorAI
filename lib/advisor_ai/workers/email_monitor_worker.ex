defmodule AdvisorAi.Workers.EmailMonitorWorker do
  @moduledoc """
  Worker that monitors Gmail for new emails and triggers automation.
  This provides an alternative to webhooks for email automation.
  """

  use GenServer
  require Logger
  alias AdvisorAi.Accounts
  alias AdvisorAi.Integrations.Gmail
  alias AdvisorAi.AI.Agent
  alias AdvisorAi.AI.UniversalAgent
  alias AdvisorAi.Chat

  # Check every 30 seconds
  @check_interval 30_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("Email Monitor Worker started")
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_emails, state) do
    check_all_users_emails()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check() do
    Process.send_after(self(), :check_emails, @check_interval)
  end

  defp check_all_users_emails() do
    users = get_users_with_gmail_tokens()

    Enum.each(users, fn user ->
      Task.start(fn -> check_user_emails(user) end)
    end)
  end

  defp get_users_with_gmail_tokens() do
    # Get users who have Gmail access tokens via accounts table
    Accounts.list_users()
    |> Enum.filter(fn user ->
      case Accounts.get_user_google_account(user.id) do
        nil ->
          false

        account ->
          not is_nil(account.access_token) and
            not is_nil(account.token_expires_at) and
            DateTime.compare(account.token_expires_at, DateTime.utc_now()) == :gt
      end
    end)
  end

  defp check_user_emails(user) do
    try do
      case Gmail.get_recent_emails(user, 20) do
        {:ok, emails} ->
          recent_emails = filter_recent_emails(emails, 60)

          if length(recent_emails) > 0 do
            Enum.each(recent_emails, fn email ->
              process_new_email(user, email)
            end)
          end

        {:error, reason} ->
          Logger.warning(
            "Email Monitor Worker: Failed to get emails for user #{user.email}: #{reason}"
          )
      end
    rescue
      e ->
        Logger.error(
          "Email Monitor Worker: Error checking emails for user #{user.email}: #{inspect(e)}"
        )
    end
  end

  defp filter_recent_emails(emails, minutes_ago) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -minutes_ago * 60, :second)

    Enum.filter(emails, fn email ->
      case email do
        %{internalDate: internal_date} when is_binary(internal_date) ->
          case Integer.parse(internal_date) do
            {timestamp, _} ->
              email_time = DateTime.from_unix!(timestamp, :millisecond)
              DateTime.compare(email_time, cutoff_time) == :gt

            _ ->
              false
          end

        %{date: date} when is_binary(date) ->
          case parse_date_header(date) do
            {:ok, email_time} ->
              DateTime.compare(email_time, cutoff_time) == :gt

            _ ->
              false
          end

        _ ->
          false
      end
    end)
  end

  defp process_new_email(user, email) do
    email_data = extract_email_data(email)

    # Check if this is a meeting inquiry email
    if is_meeting_inquiry_email?(email_data) do
      Logger.info("📧 Email Monitor: Detected meeting inquiry from #{email_data.from}")
      handle_meeting_inquiry_email(user, email_data)
    else
      # Use the standard agent trigger for other emails
      case Agent.handle_trigger(user, "email_received", email_data) do
        {:ok, _result} ->
          Logger.info("✅ Email Monitor: Standard automation triggered for #{user.email}")
          :ok

        {:error, reason} ->
          Logger.error("❌ Email Monitor: Email automation failed for #{user.email}: #{reason}")
      end
    end
  end

  defp is_meeting_inquiry_email?(email_data) do
    subject = String.downcase(email_data.subject || "")
    body = String.downcase(email_data.body || "")

    meeting_keywords = [
      "meeting", "appointment", "call", "when", "schedule", "upcoming",
      "next", "our meeting", "the meeting", "what time", "when is",
      "do we have", "are we meeting", "meeting time", "appointment time"
    ]

    Enum.any?(meeting_keywords, fn keyword ->
      String.contains?(subject, keyword) or String.contains?(body, keyword)
    end)
  end

  defp handle_meeting_inquiry_email(user, email_data) do
    # Create a conversation for the proactive response
    case Chat.create_conversation(user.id, %{
           title: "Meeting Inquiry - #{email_data.subject}"
         }) do
      {:ok, conversation} ->
        # First, look up calendar events for this person
        case lookup_calendar_events_for_person(user, email_data.from) do
          {:ok, events} ->
            # Send email with meeting details
            send_meeting_response_email(user, email_data.from, events)

          {:error, reason} ->
            # Send email saying we couldn't check
            send_error_response_email(user, email_data.from, reason)
        end

      {:error, reason} ->
        Logger.error("❌ Email Monitor: Failed to create conversation: #{reason}")
        {:error, "Failed to create conversation: #{reason}"}
    end
  end

  defp lookup_calendar_events_for_person(user, email_address) do
    # Search for calendar events that include this email address
    case AdvisorAi.Integrations.Calendar.list_events(user, [
           q: email_address,
           time_min: DateTime.utc_now() |> DateTime.to_iso8601(),
           max_results: 10
         ]) do
      {:ok, events} ->
        # Filter events that actually include this person as an attendee
        relevant_events = Enum.filter(events, fn event ->
          attendees = get_in(event, ["attendees"]) || []
          Enum.any?(attendees, fn attendee ->
            attendee_email = get_in(attendee, ["email"])
            String.downcase(attendee_email || "") == String.downcase(email_address)
          end)
        end)

        {:ok, relevant_events}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_meeting_response_email(user, recipient_email, events) do
    if length(events) > 0 do
      # Format meeting details
      meeting_details = Enum.map_join(events, "\n", fn event ->
        summary = event["summary"] || "Meeting"
        start_time = get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"])
        end_time = get_in(event, ["end", "dateTime"]) || get_in(event, ["end", "date"])

        "• #{summary} on #{start_time}"
      end)

      subject = "Re: Your upcoming meetings"
      body = """
      Hi there,

      I found your upcoming meetings:

      #{meeting_details}

      Let me know if you need anything else!

      Best regards,
      #{user.name || "Hamza"}
      """

      case AdvisorAi.Integrations.Gmail.send_email(user, recipient_email, subject, body) do
        {:ok, _} ->
          Logger.info("✅ Email Monitor: Sent meeting details to #{recipient_email}")
          {:ok, "Meeting response sent"}

        {:error, reason} ->
          Logger.error("❌ Email Monitor: Failed to send meeting response: #{reason}")
          {:error, "Failed to send email: #{reason}"}
      end
    else
      # No meetings found
      subject = "Re: Your upcoming meetings"
      body = """
      Hi there,

      I checked our calendar and I don't see any upcoming meetings scheduled with you. Would you like me to help you schedule one?

      Best regards,
      #{user.name || "Hamza"}
      """

      case AdvisorAi.Integrations.Gmail.send_email(user, recipient_email, subject, body) do
        {:ok, _} ->
          Logger.info("✅ Email Monitor: Sent no-meetings response to #{recipient_email}")
          {:ok, "No meetings response sent"}

        {:error, reason} ->
          Logger.error("❌ Email Monitor: Failed to send no-meetings response: #{reason}")
          {:error, "Failed to send email: #{reason}"}
      end
    end
  end

  defp send_error_response_email(user, recipient_email, error) do
    subject = "Re: Your upcoming meetings"
    body = """
    Hi there,

    I'm having trouble checking our calendar right now. Please try again later or contact me directly.

    Best regards,
    #{user.name || "Hamza"}
    """

    case AdvisorAi.Integrations.Gmail.send_email(user, recipient_email, subject, body) do
      {:ok, _} ->
        Logger.info("✅ Email Monitor: Sent error response to #{recipient_email}")
        {:ok, "Error response sent"}

      {:error, reason} ->
        Logger.error("❌ Email Monitor: Failed to send error response: #{reason}")
        {:error, "Failed to send email: #{reason}"}
    end
  end

  defp build_meeting_lookup_prompt(email_data) do
    """
    A client has emailed asking about an upcoming meeting. You MUST look up their calendar events and send them a specific response.

    **Email Details:**
    From: #{email_data.from}
    Subject: #{email_data.subject}
    Body: #{email_data.body}

    **STEP-BY-STEP INSTRUCTIONS (follow exactly):**

    STEP 1: Search for calendar events
    - Use universal_action with action="list_events" and query="#{email_data.from}"
    - This will find any calendar events that include #{email_data.from} as an attendee
    - Wait for the results before proceeding

    STEP 2: Send email response based on results
    - If events are found: Send email with specific meeting details (date, time, title)
    - If no events found: Send email saying "I don't see any upcoming meetings scheduled with you"
    - Use universal_action with action="send_email", to="#{email_data.from}"

    **EXAMPLE EMAIL RESPONSES:**

    If meetings found:
    "Hi Mark,

    I found your upcoming meeting: [Meeting Title] on [Date] at [Time].

    Let me know if you need anything else!

    Best regards,
    Hamza"

    If no meetings found:
    "Hi Mark,

    I checked our calendar and I don't see any upcoming meetings scheduled with you. Would you like me to help you schedule one?

    Best regards,
    Hamza"

    **CRITICAL**:
    - DO NOT send generic "I will get back to you" messages
    - DO NOT say "I am currently checking" - actually check and provide results
    - You MUST call list_events first, then send_email with the specific results
    - Always include actual meeting details or clearly state no meetings found
    """
  end

  defp extract_email_data(email) do
    raw_from =
      email[:from] || extract_header_value(get_in(email, ["payload", "headers"]) || [], "From")

    from = extract_email_from_header(raw_from)

    subject =
      email[:subject] ||
        extract_header_value(get_in(email, ["payload", "headers"]) || [], "Subject")

    body = email[:body] || extract_email_body(email)

    %{
      from: from,
      subject: subject,
      body: body,
      received_at: DateTime.utc_now() |> DateTime.truncate(:second),
      message_id: email[:id]
    }
  end

  defp extract_header_value(headers, header_name) do
    case Enum.find(headers, fn %{"name" => name} -> name == header_name end) do
      %{"value" => value} ->
        case header_name do
          "From" -> extract_email_from_header(value)
          _ -> value
        end

      _ ->
        "Unknown #{header_name}"
    end
  end

  defp extract_email_from_header(from_header) do
    # Extract email from "Name <email@domain.com>" or just "email@domain.com"
    case Regex.run(~r/<([^>]+)>/, from_header) do
      [_, email] ->
        email

      _ ->
        # Try to find email pattern in the header
        case Regex.run(~r/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/, from_header) do
          [_, email] -> email
          _ -> from_header
        end
    end
  end

  defp extract_email_body(email) do
    case email do
      %{"payload" => %{"body" => %{"data" => data}}} when is_binary(data) ->
        case Base.decode64(data, padding: false) do
          {:ok, decoded} -> decoded
          _ -> "Unable to decode email body"
        end

      %{"payload" => %{"parts" => parts}} when is_list(parts) ->
        # Handle multipart messages
        text_part =
          Enum.find(parts, fn part ->
            get_in(part, ["mimeType"]) == "text/plain"
          end)

        case text_part do
          %{"body" => %{"data" => data}} when is_binary(data) ->
            case Base.decode64(data, padding: false) do
              {:ok, decoded} -> decoded
              _ -> "Unable to decode email body"
            end

          _ ->
            "No text content found"
        end

      _ ->
        "No body content available"
    end
  end

  defp parse_date_header(date_string) do
    # Try to parse common email date formats
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      _ ->
        # Try parsing RFC 2822 format (e.g., "Mon, 7 Jul 2025 01:58:38 +0100")
        case parse_rfc2822_date(date_string) do
          {:ok, datetime} -> {:ok, datetime}
          _ -> :error
        end
    end
  end

  defp parse_rfc2822_date(date_string) do
    # Simple RFC 2822 date parser
    # Format: "Mon, 7 Jul 2025 01:58:38 +0100"
    case Regex.run(
           ~r/(\w{3}),\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-]\d{4})/,
           date_string
         ) do
      [_, _day_name, day, month_name, year, hour, minute, second, offset] ->
        month_map = %{
          "Jan" => 1,
          "Feb" => 2,
          "Mar" => 3,
          "Apr" => 4,
          "May" => 5,
          "Jun" => 6,
          "Jul" => 7,
          "Aug" => 8,
          "Sep" => 9,
          "Oct" => 10,
          "Nov" => 11,
          "Dec" => 12
        }

        case Map.get(month_map, month_name) do
          nil ->
            :error

          month ->
            case DateTime.new(
                   Date.new(String.to_integer(year), month, String.to_integer(day)),
                   Time.new(
                     String.to_integer(hour),
                     String.to_integer(minute),
                     String.to_integer(second)
                   )
                 ) do
              {:ok, datetime} -> {:ok, datetime}
              _ -> :error
            end
        end

      _ ->
        :error
    end
  end

  defp parse_offset(offset_string) do
    # Parse offset like "+0100" or "-0500"
    case Regex.run(~r/([+-])(\d{2})(\d{2})/, offset_string) do
      [_, sign, hours, minutes] ->
        total_minutes = String.to_integer(hours) * 60 + String.to_integer(minutes)

        case sign do
          "+" -> total_minutes
          "-" -> -total_minutes
        end

      _ ->
        0
    end
  end
end
