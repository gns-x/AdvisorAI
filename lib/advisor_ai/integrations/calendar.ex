defmodule AdvisorAi.Integrations.Calendar do
  @moduledoc """
  Google Calendar integration for managing events and appointments
  """

  @calendar_api_url "https://www.googleapis.com/calendar/v3"

  def create_event(user, event_data) do
    case get_access_token(user) do
      {:ok, access_token} ->
        event = %{
          summary: event_data["title"],
          description: event_data["description"],
          start: %{
            dateTime: event_data["start_time"],
            timeZone: "UTC"
          },
          end: %{
            dateTime: event_data["end_time"],
            timeZone: "UTC"
          },
          attendees: Enum.map(event_data["attendees"] || [], fn email ->
            %{email: email}
          end)
        }

        url = "#{@calendar_api_url}/calendars/primary/events"

        case HTTPoison.post(url, Jason.encode!(event), [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, created_event} ->
                # Trigger agent if needed
                AdvisorAi.AI.Agent.handle_trigger(user, "calendar_event", %{
                  action: "created",
                  title: created_event["summary"],
                  id: created_event["id"]
                })
                {:ok, "Event created successfully"}

              {:error, reason} ->
                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "Calendar API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_available_times(user, start_date, end_date) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # Get busy times
        url = "#{@calendar_api_url}/freeBusy"

        request_body = %{
          timeMin: start_date,
          timeMax: end_date,
          items: [%{id: "primary"}]
        }

        case HTTPoison.post(url, Jason.encode!(request_body), [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"calendars" => %{"primary" => %{"busy" => busy_times}}}} ->
                # Calculate available times
                available_times = calculate_available_times(start_date, end_date, busy_times)
                {:ok, available_times}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "Calendar API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_events(user, start_date, end_date) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/primary/events"
        params = URI.encode_query(%{
          timeMin: start_date,
          timeMax: end_date,
          singleEvents: true,
          orderBy: "startTime"
        })

        case HTTPoison.get("#{url}?#{params}", [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"items" => events}} ->
                {:ok, events}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "Calendar API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_event(user, event_id, updates) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/primary/events/#{event_id}"

        case HTTPoison.patch(url, Jason.encode!(updates), [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, updated_event} ->
                # Trigger agent if needed
                AdvisorAi.AI.Agent.handle_trigger(user, "calendar_event", %{
                  action: "updated",
                  title: updated_event["summary"],
                  id: updated_event["id"]
                })
                {:ok, "Event updated successfully"}

              {:error, reason} ->
                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "Calendar API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_event(user, event_id) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/primary/events/#{event_id}"

        case HTTPoison.delete(url, [
          {"Authorization", "Bearer #{access_token}"}
        ]) do
          {:ok, %{status_code: 204}} ->
            # Trigger agent if needed
            AdvisorAi.AI.Agent.handle_trigger(user, "calendar_event", %{
              action: "deleted",
              id: event_id
            })
            {:ok, "Event deleted successfully"}

          {:ok, %{status_code: status_code}} ->
            {:error, "Calendar API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_available_times(start_date, end_date, busy_times) do
    # Convert to DateTime
    {:ok, start_dt} = DateTime.from_iso8601(start_date)
    {:ok, end_dt} = DateTime.from_iso8601(end_date)

    # Convert busy times to DateTime ranges
    busy_ranges = Enum.map(busy_times, fn %{"start" => start, "end" => end_time} ->
      {:ok, start_dt} = DateTime.from_iso8601(start)
      {:ok, end_dt} = DateTime.from_iso8601(end_time)
      {start_dt, end_dt}
    end)

    # Find available 30-minute slots
    available_slots = find_available_slots(start_dt, end_dt, busy_ranges, [])

    Enum.reverse(available_slots)
  end

  defp find_available_slots(current, end_dt, busy_ranges, available_slots) do
    if DateTime.compare(current, end_dt) == :lt do
      slot_end = DateTime.add(current, 30 * 60, :second)

      if DateTime.compare(slot_end, end_dt) == :lt or DateTime.compare(slot_end, end_dt) == :eq do
        is_available = Enum.all?(busy_ranges, fn {busy_start, busy_end} ->
          DateTime.compare(current, busy_end) == :gt or DateTime.compare(current, busy_end) == :eq or
          DateTime.compare(slot_end, busy_start) == :lt or DateTime.compare(slot_end, busy_start) == :eq
        end)

        new_slots = if is_available do
          [%{
            start: DateTime.to_iso8601(current),
            end: DateTime.to_iso8601(slot_end)
          } | available_slots]
        else
          available_slots
        end

        find_available_slots(DateTime.add(current, 30 * 60, :second), end_dt, busy_ranges, new_slots)
      else
        available_slots
      end
    else
      available_slots
    end
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
