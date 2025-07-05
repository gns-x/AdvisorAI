defmodule AdvisorAi.Integrations.HubSpot do
  @moduledoc """
  HubSpot integration for managing contacts and notes
  """

  alias AdvisorAi.AI.{VectorEmbedding, OllamaClient}
  alias AdvisorAi.Repo

  @hubspot_api_url "https://api.hubapi.com"
  # OpenAI client will be configured at runtime

  def search_contacts(user, query) do
    case get_access_token(user) do
      {:ok, access_token} ->
        url = "#{@hubspot_api_url}/crm/v3/objects/contacts/search"

        request_body = %{
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
          properties: ["email", "firstname", "lastname", "company"],
          limit: 10
        }

        case HTTPoison.post(url, Jason.encode!(request_body), [
          {"Authorization", "Bearer #{access_token}"},
          {"Content-Type", "application/json"}
        ]) do
          {:ok, %{status_code: 200, body: body}} ->
            case Jason.decode(body) do
              {:ok, %{"results" => contacts}} ->
                {:ok, contacts}

              {:ok, _} ->
                {:ok, []}

              {:error, reason} ->
                {:error, "Failed to parse response: #{reason}"}
            end

          {:ok, %{status_code: status_code}} ->
            {:error, "HubSpot API error: #{status_code}"}

          {:error, reason} ->
            {:error, "HTTP error: #{reason}"}
        end

      {:error, reason} ->
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
            params = URI.encode_query(%{
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

  defp store_contact_embedding(_user, _contact) do
    # Temporarily disabled embeddings to fix the error
    :ok
  end

    defp store_note_embedding(_user, _note, _contact_email) do
    # Temporarily disabled embeddings to fix the error
    :ok
  end

  defp get_embedding(_text) do
    # Temporarily disabled embeddings to fix the error
    {:error, "embeddings disabled"}
  end

  defp get_access_token(user) do
    case AdvisorAi.Accounts.get_user_hubspot_account(user.id) do
      nil ->
        {:error, "No HubSpot account connected"}

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
