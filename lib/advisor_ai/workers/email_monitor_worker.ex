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

  @check_interval 10_000 # Check every 10 seconds

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
    Logger.info("🔄 Email Monitor Worker: Starting email check cycle")
    check_all_users_emails()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check() do
    Process.send_after(self(), :check_emails, @check_interval)
  end

  defp check_all_users_emails() do
    # Get all users with Gmail tokens
    users = get_users_with_gmail_tokens()
    Logger.info("📧 Email Monitor Worker: Found #{length(users)} users with Gmail tokens")

    Enum.each(users, fn user ->
      Task.start(fn -> check_user_emails(user) end)
    end)
  end

  defp get_users_with_gmail_tokens() do
    # Get users who have Gmail access tokens via accounts table
    Accounts.list_users()
    |> Enum.filter(fn user ->
      case Accounts.get_user_google_account(user.id) do
        nil -> false
        account ->
          not is_nil(account.access_token) and
          not is_nil(account.token_expires_at) and
          DateTime.compare(account.token_expires_at, DateTime.utc_now()) == :gt
      end
    end)
  end

  defp check_user_emails(user) do
    Logger.info("🔍 Email Monitor Worker: Checking emails for user #{user.email}")
    try do
      # Get recent emails (last 1 hour)
      case Gmail.get_recent_emails(user, 20) do
        {:ok, emails} ->
          Logger.info("📬 Email Monitor Worker: Retrieved #{length(emails)} emails for #{user.email}")

          # Filter for emails received in the last 1 hour
          recent_emails = filter_recent_emails(emails, 60) # 1 hour in minutes
          Logger.info("🕒 Email Monitor Worker: Found #{length(recent_emails)} recent emails for #{user.email}")

          if length(recent_emails) > 0 do
            Logger.info("✅ Email Monitor Worker: Processing #{length(recent_emails)} new emails for user #{user.email}")

            # Process each new email
            Enum.each(recent_emails, fn email ->
              process_new_email(user, email)
            end)
          else
            Logger.info("⏭️ Email Monitor Worker: No recent emails found for #{user.email}")
          end

        {:error, reason} ->
          Logger.warning("❌ Email Monitor Worker: Failed to get emails for user #{user.email}: #{reason}")
      end
    rescue
      e ->
        Logger.error("💥 Email Monitor Worker: Error checking emails for user #{user.email}: #{inspect(e)}")
    end
  end

  defp filter_recent_emails(emails, minutes_ago) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -minutes_ago * 60, :second)
    Logger.info("🕐 Email Monitor Worker: Filtering emails since #{cutoff_time} (last #{minutes_ago} minutes)")

    Enum.filter(emails, fn email ->
      case email do
        %{internalDate: internal_date} when is_binary(internal_date) ->
          case Integer.parse(internal_date) do
            {timestamp, _} ->
              email_time = DateTime.from_unix!(timestamp, :millisecond)
              is_recent = DateTime.compare(email_time, cutoff_time) == :gt
              Logger.info("📅 Email Monitor Worker: Email from #{email.from} at #{email_time} - Recent: #{is_recent}")
              is_recent
            _ ->
              Logger.warning("⚠️ Email Monitor Worker: Could not parse internal date: #{internal_date}")
              false
          end
        %{date: date} when is_binary(date) ->
          # Fallback to parsing the date header
          case parse_date_header(date) do
            {:ok, email_time} ->
              is_recent = DateTime.compare(email_time, cutoff_time) == :gt
              Logger.info("📅 Email Monitor Worker: Email from #{email.from} at #{email_time} (from date header) - Recent: #{is_recent}")
              is_recent
            _ ->
              Logger.warning("⚠️ Email Monitor Worker: Could not parse date header: #{date}")
              false
          end
        _ ->
          Logger.warning("⚠️ Email Monitor Worker: Email missing both internalDate and date: #{inspect(email)}")
          false
      end
    end)
  end

  defp process_new_email(user, email) do
    Logger.info("🚀 Email Monitor Worker: Processing new email for #{user.email}")

    # Extract email data
    email_data = extract_email_data(email)
    Logger.info("📝 Email Monitor Worker: Extracted email data: #{inspect(email_data)}")

    # Trigger automation system
    case Agent.handle_trigger(user, "email_received", email_data) do
      {:ok, result} ->
        Logger.info("✅ Email Monitor Worker: Email automation triggered for #{user.email}: #{inspect(result)}")

      {:error, reason} ->
        Logger.error("❌ Email Monitor Worker: Email automation failed for #{user.email}: #{reason}")
    end
  end

    defp extract_email_data(email) do
    Logger.info("🔍 Email Monitor Worker: Raw email data: #{inspect(email, pretty: true)}")
    Logger.info("🔍 Email Monitor Worker: Email keys: #{inspect(Map.keys(email))}")
    Logger.info("🔍 Email Monitor Worker: email[:from] = #{inspect(email[:from])}")
    Logger.info("🔍 Email Monitor Worker: email[:subject] = #{inspect(email[:subject])}")

    # Try to extract from flattened structure first (direct fields)
    raw_from = email[:from] || extract_header_value(get_in(email, ["payload", "headers"]) || [], "From")
    from = extract_email_from_header(raw_from)
    subject = email[:subject] || extract_header_value(get_in(email, ["payload", "headers"]) || [], "Subject")
    body = email[:body] || extract_email_body(email)

    email_data = %{
      from: from,
      subject: subject,
      body: body,
      received_at: DateTime.utc_now(),
      message_id: email[:id]
    }

    Logger.info("📝 Email Monitor Worker: Extracted email data: #{inspect(email_data)}")
    email_data
  end

  defp extract_header_value(headers, header_name) do
    case Enum.find(headers, fn %{"name" => name} -> name == header_name end) do
      %{"value" => value} ->
        case header_name do
          "From" -> extract_email_from_header(value)
          _ -> value
        end
      _ -> "Unknown #{header_name}"
    end
  end

  defp extract_email_from_header(from_header) do
    # Extract email from "Name <email@domain.com>" or just "email@domain.com"
    case Regex.run(~r/<([^>]+)>/, from_header) do
      [_, email] -> email
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
        text_part = Enum.find(parts, fn part ->
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
    case Regex.run(~r/(\w{3}),\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-]\d{4})/, date_string) do
      [_, _day_name, day, month_name, year, hour, minute, second, offset] ->
        month_map = %{
          "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4, "May" => 5, "Jun" => 6,
          "Jul" => 7, "Aug" => 8, "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12
        }

        case Map.get(month_map, month_name) do
          nil -> :error
          month ->
            case DateTime.new(
              Date.new(String.to_integer(year), month, String.to_integer(day)),
              Time.new(String.to_integer(hour), String.to_integer(minute), String.to_integer(second))
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
