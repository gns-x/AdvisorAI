defmodule AdvisorAi.Integrations.Calendar do
  @moduledoc """
  Google Calendar integration for managing events and appointments
  """

  @calendar_api_url "https://www.googleapis.com/calendar/v3"

  def create_event(user, event_data) do
    # Fallback: auto-generate a title if missing or blank
    title =
      case String.trim(to_string(event_data["title"] || "")) do
        "" ->
          contact =
            case event_data["attendees"] do
              [first | _] ->
                if String.contains?(first, "@"), do: first, else: "Attendee"

              _ ->
                "Attendee"
            end

          time = event_data["start_time"] || "(No time)"
          "Meeting with #{contact} on #{time}"

        t ->
          t
      end

    event = %{
      summary: title,
      description: event_data["description"],
      start: %{
        dateTime: event_data["start_time"],
        timeZone: "UTC"
      },
      end: %{
        dateTime: event_data["end_time"],
        timeZone: "UTC"
      },
      attendees:
        Enum.map(event_data["attendees"] || [], fn email ->
          %{email: email}
        end)
    }

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/primary/events"

        case HTTPoison.post(url, Jason.encode!(event), [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, created_event} ->
                # Trigger agent if needed
                AdvisorAi.AI.Agent.handle_trigger(user, "calendar_event_created", %{
                  action: "created",
                  title: created_event["summary"],
                  id: created_event["id"]
                })

                {:ok, created_event}

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

        params =
          URI.encode_query(%{
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

  def get_event(user, event_id) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/primary/events/#{event_id}"

        case HTTPoison.get(url, [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, event} ->
                {:ok, event}

              {:error, reason} ->
                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: 404}} ->
            {:error, "Event not found"}

          {:ok, %{status_code: status_code}} ->
            {:error, "Calendar API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_availability(user, date, duration_minutes) do
    # Parse the date and create a time range for the day
    case DateTime.from_iso8601("#{date}T00:00:00Z") do
      {:ok, start_of_day, _} ->
        end_of_day = DateTime.add(start_of_day, 24 * 60 * 60, :second)

        case get_available_times(
               user,
               DateTime.to_iso8601(start_of_day),
               DateTime.to_iso8601(end_of_day)
             ) do
          {:ok, available_times} ->
            # Filter times that have enough duration
            suitable_times =
              Enum.filter(available_times, fn slot ->
                case {slot["start"], slot["end"]} do
                  {start_str, end_str} when is_binary(start_str) and is_binary(end_str) ->
                    case {DateTime.from_iso8601(start_str), DateTime.from_iso8601(end_str)} do
                      {{:ok, start_time, _}, {:ok, end_time, _}} ->
                        duration = DateTime.diff(end_time, start_time, :minute)
                        duration >= duration_minutes

                      _ ->
                        false
                    end

                  _ ->
                    false
                end
              end)

            {:ok, suitable_times}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, "Invalid date format: #{reason}"}
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
                AdvisorAi.AI.Agent.handle_trigger(user, "calendar_event_updated", %{
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

  def delete_event(user, event_id, calendar_id \\ "primary") do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/#{calendar_id}/events/#{event_id}"

        case HTTPoison.delete(url, [
               {"Authorization", "Bearer #{access_token}"}
             ]) do
          {:ok, %{status_code: 204}} ->
            # Trigger agent if needed
            AdvisorAi.AI.Agent.handle_trigger(user, "calendar_event_deleted", %{
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

  @doc """
  List calendar events with flexible parameters.
  """
  def list_events(user, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    time_min = Keyword.get(opts, :time_min)
    time_max = Keyword.get(opts, :time_max)
    max_results = Keyword.get(opts, :max_results, 10)
    q = Keyword.get(opts, :q)

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/#{calendar_id}/events"

        params = %{
          maxResults: max_results,
          singleEvents: true,
          orderBy: "startTime"
        }

        params = if time_min, do: Map.put(params, :timeMin, time_min), else: params
        params = if time_max, do: Map.put(params, :timeMax, time_max), else: params
        params = if q, do: Map.put(params, :q, q), else: params

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
              {:ok, %{"items" => events}} ->
                {:ok, events}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse events: #{reason}"}
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

  @doc """
  Update a calendar event with full event data.
  """
  def update_event(user, event_id, event_data, calendar_id \\ "primary") do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/calendars/#{calendar_id}/events/#{event_id}"

        event = %{
          summary: event_data["summary"],
          description: event_data["description"],
          start: %{
            dateTime: event_data["start_time"],
            timeZone: "UTC"
          },
          end: %{
            dateTime: event_data["end_time"],
            timeZone: "UTC"
          },
          attendees:
            Enum.map(event_data["attendees"] || [], fn email ->
              %{email: email}
            end)
        }

        case HTTPoison.put(url, Jason.encode!(event), [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, updated_event} ->
                {:ok, updated_event}

              {:error, reason} ->
                {:error, "Failed to parse updated event: #{reason}"}
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

  @doc """
  List available calendars.
  """
  def list_calendars(user) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@calendar_api_url}/users/me/calendarList"

        case HTTPoison.get(url, [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"items" => calendars}} ->
                {:ok, calendars}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse calendars: #{reason}"}
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

  defp calculate_available_times(start_date, end_date, busy_times) do
    # Convert to DateTime
    {:ok, start_dt, _} = DateTime.from_iso8601(start_date)
    {:ok, end_dt, _} = DateTime.from_iso8601(end_date)

    # Convert busy times to DateTime ranges
    busy_ranges =
      busy_times
      |> Enum.filter(fn %{"start" => start, "end" => end_time} ->
        is_binary(start) and is_binary(end_time)
      end)
      |> Enum.map(fn %{"start" => start, "end" => end_time} ->
        case {DateTime.from_iso8601(start), DateTime.from_iso8601(end_time)} do
          {{:ok, start_dt, _}, {:ok, end_dt, _}} ->
            {start_dt, end_dt}

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Find available 30-minute slots
    available_slots = find_available_slots(start_dt, end_dt, busy_ranges, [])

    Enum.reverse(available_slots)
  end

  defp find_available_slots(current, end_dt, busy_ranges, available_slots) do
    if DateTime.compare(current, end_dt) == :lt do
      slot_end = DateTime.add(current, 30 * 60, :second)

      if DateTime.compare(slot_end, end_dt) == :lt or DateTime.compare(slot_end, end_dt) == :eq do
        # Check if this slot overlaps with any busy time
        is_available =
          Enum.all?(busy_ranges, fn {busy_start, busy_end} ->
            # Slot is available if it doesn't overlap with this busy time
            # Slot ends before busy time starts OR slot starts after busy time ends
            DateTime.compare(slot_end, busy_start) == :lt or
              DateTime.compare(current, busy_end) == :gt
          end)

        new_slots =
          if is_available do
            [
              %{
                start: DateTime.to_iso8601(current),
                end: DateTime.to_iso8601(slot_end)
              }
              | available_slots
            ]
          else
            available_slots
          end

        find_available_slots(
          DateTime.add(current, 30 * 60, :second),
          end_dt,
          busy_ranges,
          new_slots
        )
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
        {:error, "You need to connect your Google account in settings before I can access your Calendar."}

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

  def strftime(datetime, format) do
    Calendar.strftime(datetime, format)
  end
end
