defmodule AdvisorAi.Integrations.HubSpot do
  @moduledoc """
  HubSpot integration for managing contacts and notes
  """

  alias AdvisorAi.AI.{VectorEmbedding, TogetherClient}
  alias AdvisorAi.Repo

  @hubspot_api_url "https://api.hubapi.com"
  # OpenAI client will be configured at runtime

  def search_contacts(user, query) do
    require Logger

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@hubspot_api_url}/crm/v3/objects/contacts/search"

        request_body =
          if is_binary(query) and String.trim(query) != "" do
            %{
              filterGroups: [
                %{
                  filters: [
                    %{
                      propertyName: "email",
                      operator: "CONTAINS_TOKEN",
                      value: query
                    }
                  ]
                }
              ],
              properties: ["email", "firstname", "lastname", "company", "phone", "jobtitle"],
              limit: 10,
              after: 0
            }
          else
            %{
              properties: ["email", "firstname", "lastname", "company", "phone", "jobtitle"],
              limit: 10,
              after: 0
            }
          end

        File.write(
          "/private/tmp/hubspot_debug.log",
          "[HubSpot.search_contacts] Query: #{query}\n",
          [:append]
        )

        case HTTPoison.post(url, Jason.encode!(request_body), [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            Logger.info("[HubSpot.search_contacts] Raw response: #{body}")

            File.write(
              "/private/tmp/hubspot_debug.log",
              "[HubSpot.search_contacts] Raw response: #{body}\n",
              [:append]
            )

            case Jason.decode(body) do
              {:ok, %{"results" => contacts}} ->
                Logger.info("[HubSpot.search_contacts] Contacts found: #{length(contacts)}")

                File.write(
                  "/private/tmp/hubspot_debug.log",
                  "[HubSpot.search_contacts] Contacts found: #{length(contacts)}\n",
                  [:append]
                )

                {:ok, contacts}

              {:ok, _} ->
                Logger.info("[HubSpot.search_contacts] No contacts found in response.")

                File.write(
                  "/private/tmp/hubspot_debug.log",
                  "[HubSpot.search_contacts] No contacts found in response.\n",
                  [:append]
                )

                {:ok, []}

              {:error, reason} ->
                Logger.error("[HubSpot.search_contacts] Failed to parse response: #{reason}")

                File.write(
                  "/private/tmp/hubspot_debug.log",
                  "[HubSpot.search_contacts] Failed to parse response: #{reason}\n",
                  [:append]
                )

                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: status_code, body: body}} ->
            Logger.error("[HubSpot.search_contacts] HubSpot API error: #{status_code} - #{body}")

            File.write(
              "/private/tmp/hubspot_debug.log",
              "[HubSpot.search_contacts] HubSpot API error: #{status_code} - #{body}\n",
              [:append]
            )

            {:error, "HubSpot API error: #{status_code} - #{body}"}

          {:error, reason} ->
            Logger.error("[HubSpot.search_contacts] HTTP error: #{inspect(reason)}")

            File.write(
              "/private/tmp/hubspot_debug.log",
              "[HubSpot.search_contacts] HTTP error: #{inspect(reason)}\n",
              [:append]
            )

            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        Logger.error("[HubSpot.search_contacts] Access token error: #{reason}")

        File.write(
          "/private/tmp/hubspot_debug.log",
          "[HubSpot.search_contacts] Access token error: #{reason}\n",
          [:append]
        )

        {:error, reason}
    end
  end

  def list_contacts(user, limit \\ 50) do
    require Logger

    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@hubspot_api_url}/crm/v3/objects/contacts"

        params =
          URI.encode_query(%{
            limit: limit,
            properties: "email,firstname,lastname,company,phone,jobtitle"
          })

        case HTTPoison.get("#{url}?#{params}", [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 200, body: body}} ->
            Logger.info("[HubSpot.list_contacts] Raw response: #{body}")

            File.write(
              "/private/tmp/hubspot_debug.log",
              "[HubSpot.list_contacts] Raw response: #{body}\n",
              [:append]
            )

            case Jason.decode(body) do
              {:ok, %{"results" => contacts}} ->
                Logger.info("[HubSpot.list_contacts] Contacts found: #{length(contacts)}")

                File.write(
                  "/private/tmp/hubspot_debug.log",
                  "[HubSpot.list_contacts] Contacts found: #{length(contacts)}\n",
                  [:append]
                )

                {:ok, contacts}

              {:ok, _} ->
                Logger.info("[HubSpot.list_contacts] No contacts found in response.")

                File.write(
                  "/private/tmp/hubspot_debug.log",
                  "[HubSpot.list_contacts] No contacts found in response.\n",
                  [:append]
                )

                {:ok, []}

              {:error, reason} ->
                Logger.error("[HubSpot.list_contacts] Failed to parse response: #{reason}")

                File.write(
                  "/private/tmp/hubspot_debug.log",
                  "[HubSpot.list_contacts] Failed to parse response: #{reason}\n",
                  [:append]
                )

                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: status_code, body: body}} ->
            Logger.error("[HubSpot.list_contacts] HubSpot API error: #{status_code} - #{body}")
            {:error, "HubSpot API error: #{status_code} - #{body}"}

          {:error, reason} ->
            Logger.error("[HubSpot.list_contacts] HTTP error: #{inspect(reason)}")
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        Logger.error("[HubSpot.list_contacts] Access token error: #{reason}")
        {:error, reason}
    end
  end

  def create_contact(user, contact_data) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@hubspot_api_url}/crm/v3/objects/contacts"

        contact_properties = %{
          email: contact_data["email"],
          firstname: contact_data["first_name"],
          lastname: contact_data["last_name"],
          company: contact_data["company"]
        }

        request_body = %{
          properties: contact_properties
        }

        case HTTPoison.post(url, Jason.encode!(request_body), [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]) do
          {:ok, %{status_code: 201, body: body}} ->
            case Jason.decode(body) do
              {:ok, created_contact} ->
                # Store in vector embeddings
                store_contact_embedding(user, created_contact)

                # Add note if provided
                if contact_data["notes"] do
                  add_note(user, contact_data["email"], contact_data["notes"])
                end

                # Trigger agent if needed
                AdvisorAi.AI.Agent.handle_trigger(user, "hubspot_update", %{
                  type: "contact",
                  action: "created",
                  name: "#{contact_data["first_name"]} #{contact_data["last_name"]}",
                  id: created_contact["id"]
                })

                {:ok, "Contact created successfully"}

              {:error, reason} ->
                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: 409}} ->
            # Contact already exists - this is not an error
            {:ok, "Contact already exists"}

          {:ok, %{status_code: status_code}} ->
            {:error, "HubSpot API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def add_note(user, contact_email, note_content) do
    case get_access_token(user) do
      {:ok, access_token} ->
        # First, find the contact by email
        case find_contact_by_email(user, contact_email) do
          {:ok, contact_id} ->
            url = "#{@hubspot_api_url}/crm/v3/objects/notes"

            request_body = %{
              properties: %{
                hs_note_body: note_content,
                hs_timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
              },
              associations: [
                %{
                  to: %{
                    id: contact_id
                  },
                  types: [
                    %{
                      associationCategory: "HUBSPOT_DEFINED",
                      associationTypeId: 1
                    }
                  ]
                }
              ]
            }

            case HTTPoison.post(url, Jason.encode!(request_body), [
                   {"Authorization", "Bearer #{access_token}"},
                   {"Content-Type", "application/json"}
                 ]) do
              {:ok, %{status_code: 201, body: body}} ->
                case Jason.decode(body) do
                  {:ok, created_note} ->
                    # Store in vector embeddings
                    store_note_embedding(user, created_note, contact_email)

                    # Trigger agent if needed
                    AdvisorAi.AI.Agent.handle_trigger(user, "hubspot_update", %{
                      type: "note",
                      action: "created",
                      contact_email: contact_email,
                      id: created_note["id"]
                    })

                    {:ok, "Note added successfully"}

                  {:error, reason} ->
                    {:error, "Failed to parse response: #{reason}"}
                end

              {:ok, %{status_code: 403}} ->
                {:error, "Insufficient permissions for notes. Please check your HubSpot scopes."}

              {:ok, %{status_code: status_code}} ->
                {:error, "HubSpot API error: #{status_code}"}

              {:error, reason} ->
                {:error, "HTTP error: #{reason}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_contact_notes(user, contact_email) do
    case get_access_token(user) do
      {:ok, access_token} ->
        case find_contact_by_email(user, contact_email) do
          {:ok, contact_id} ->
            url = "#{@hubspot_api_url}/crm/v3/objects/notes"

            params =
              URI.encode_query(%{
                associations: "contacts",
                after: contact_id,
                limit: 100
              })

            case HTTPoison.get("#{url}?#{params}", [
                   {"Authorization", "Bearer #{access_token}"},
                   {"Content-Type", "application/json"}
                 ]) do
              {:ok, %{status_code: 200, body: body}} ->
                case Jason.decode(body) do
                  {:ok, %{"results" => notes}} ->
                    {:ok, notes}

                  {:ok, _} ->
                    {:ok, []}

                  {:error, reason} ->
                    {:error, "Failed to parse response: #{reason}"}
                end

              {:ok, %{status_code: 403}} ->
                {:error, "Insufficient permissions for notes. Please check your HubSpot scopes."}

              {:ok, %{status_code: status_code}} ->
                {:error, "HubSpot API error: #{status_code}"}

              {:error, reason} ->
                {:error, "HTTP error: #{reason}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_contact_by_email(user, email) do
    case search_contacts(user, email) do
      {:ok, [contact | _]} ->
        {:ok, contact["id"]}

      {:ok, []} ->
        {:error, "Contact not found"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_contact_embedding(user, contact) do
    content =
      "Contact: #{contact["properties"]["firstname"]} #{contact["properties"]["lastname"]} (#{contact["properties"]["email"]}) - #{contact["properties"]["company"]}"

    case get_embedding(content) do
      {:ok, embedding} ->
        %VectorEmbedding{
          user_id: user.id,
          source: "hubspot_contact",
          content: content,
          embedding: embedding,
          metadata: %{
            email: contact["properties"]["email"],
            firstname: contact["properties"]["firstname"],
            lastname: contact["properties"]["lastname"],
            company: contact["properties"]["company"]
          }
        }
        |> VectorEmbedding.changeset(%{})
        |> Repo.insert()

      {:error, _reason} ->
        :ok
    end
  end

  defp store_note_embedding(user, note, contact_email) do
    content = "Note for #{contact_email}: #{note["properties"]["hs_note_body"]}"

    case get_embedding(content) do
      {:ok, embedding} ->
        %VectorEmbedding{
          user_id: user.id,
          source: "hubspot_note",
          content: content,
          embedding: embedding,
          metadata: %{
            contact_email: contact_email,
            note_body: note["properties"]["hs_note_body"],
            timestamp: note["properties"]["hs_timestamp"]
          }
        }
        |> VectorEmbedding.changeset(%{})
        |> Repo.insert()

      {:error, _reason} ->
        :ok
    end
  end

  defp get_embedding(text) do
    # Use local embedding server for RAG
    case AdvisorAi.AI.LocalEmbeddingClient.embeddings(input: text) do
      {:ok, %{"data" => [%{"embedding" => embedding}]}} ->
        {:ok, embedding}

      {:error, reason} ->
        {:error, "Failed to generate embedding: #{reason}"}
    end
  end

  # Only use OAuth tokens - no API key fallback
  defp get_access_token(user) do
    get_oauth_token(user)
  end

  defp get_oauth_token(user) do
    cond do
      is_nil(user.hubspot_access_token) ->
        {:error,
         "No HubSpot access token found. Please connect your HubSpot account via OAuth in the settings."}

      is_user_token_expired?(user) ->
        refresh_user_access_token(user)

      true ->
        {:ok, user.hubspot_access_token}
    end
  end

  defp is_token_expired?(account) do
    case account.token_expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp is_user_token_expired?(user) do
    case user.hubspot_token_expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp refresh_access_token(_account) do
    # Implement token refresh logic
    # This would use the refresh_token to get a new access_token
    {:error, "Token refresh not implemented"}
  end

  defp refresh_user_access_token(user) do
    require Logger

    if user.hubspot_refresh_token do
      client_id = System.get_env("HUBSPOT_CLIENT_ID")
      client_secret = System.get_env("HUBSPOT_CLIENT_SECRET")
      refresh_token = user.hubspot_refresh_token
      url = "https://api.hubapi.com/oauth/v1/token"

      body =
        URI.encode_query(%{
          grant_type: "refresh_token",
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token
        })

      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

      case HTTPoison.post(url, body, headers) do
        {:ok, %{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok,
             %{
               "access_token" => new_token,
               "expires_in" => expires_in,
               "refresh_token" => new_refresh_token
             }} ->
              expires_at = DateTime.add(DateTime.utc_now(), expires_in)
              # Update user tokens in DB
              case AdvisorAi.Accounts.update_user_hubspot_tokens(
                     user,
                     new_token,
                     new_refresh_token,
                     expires_at
                   ) do
                {:ok, _} ->
                  {:ok, new_token}

                {:error, reason} ->
                  Logger.error(
                    "[HubSpot.refresh_user_access_token] Failed to update user tokens: #{inspect(reason)}"
                  )

                  {:error, "Failed to update user tokens"}
              end

            {:ok, %{"access_token" => new_token, "expires_in" => expires_in}} ->
              expires_at = DateTime.add(DateTime.utc_now(), expires_in)

              case AdvisorAi.Accounts.update_user_hubspot_tokens(
                     user,
                     new_token,
                     refresh_token,
                     expires_at
                   ) do
                {:ok, _} ->
                  {:ok, new_token}

                {:error, reason} ->
                  Logger.error(
                    "[HubSpot.refresh_user_access_token] Failed to update user tokens: #{inspect(reason)}"
                  )

                  {:error, "Failed to update user tokens"}
              end

            {:ok, %{"error" => error}} ->
              Logger.error("[HubSpot.refresh_user_access_token] Token refresh failed: #{error}")
              {:error, "Token refresh failed: #{error}"}

            _ ->
              Logger.error(
                "[HubSpot.refresh_user_access_token] Invalid response format: #{resp_body}"
              )

              {:error, "Invalid response format"}
          end

        {:ok, %{status_code: code, body: resp_body}} ->
          Logger.error(
            "[HubSpot.refresh_user_access_token] HubSpot token refresh failed: #{code} #{resp_body}"
          )

          {:error, "HubSpot token refresh failed: #{code} #{resp_body}"}

        {:error, reason} ->
          Logger.error(
            "[HubSpot.refresh_user_access_token] HTTP error refreshing token: #{inspect(reason)}"
          )

          {:error, "HTTP error refreshing token: #{inspect(reason)}"}
      end
    else
      {:error, "No refresh token available"}
    end
  end

  # Test OAuth connection
  def test_oauth_connection(user) do
    case get_access_token(user) do
      {:ok, _token} ->
        {:ok, "OAuth connection successful"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
