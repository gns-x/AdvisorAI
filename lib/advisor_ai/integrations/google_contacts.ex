defmodule AdvisorAi.Integrations.GoogleContacts do
  @moduledoc """
  Google Contacts integration for comprehensive contact management.
  Provides access to Google People API for contact search, creation, and management.
  """

  alias AdvisorAi.Accounts
  alias AdvisorAi.Integrations.GoogleAuth

  @people_api_url "https://people.googleapis.com/v1"

  @doc """
  Search for contacts by name, email, or phone number.
  Returns detailed contact information including all available fields.
  """
  def search_contacts(user, query, opts \\ []) do
    case GoogleAuth.get_access_token(user) do
      {:ok, access_token} ->
        do_search_contacts(access_token, query, opts)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  @doc """
  Get all contacts for a user with full details.
  """
  def get_all_contacts(user, opts \\ []) do
    case GoogleAuth.get_access_token(user) do
      {:ok, access_token} ->
        do_get_all_contacts(access_token, opts)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  @doc """
  Get a specific contact by resource name.
  """
  def get_contact(user, resource_name) do
    case GoogleAuth.get_access_token(user) do
      {:ok, access_token} ->
        do_get_contact(access_token, resource_name)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  @doc """
  Create a new contact with comprehensive information.
  """
  def create_contact(user, contact_data) do
    case GoogleAuth.get_access_token(user) do
      {:ok, access_token} ->
        do_create_contact(access_token, contact_data)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  @doc """
  Update an existing contact.
  """
  def update_contact(user, resource_name, contact_data) do
    case GoogleAuth.get_access_token(user) do
      {:ok, access_token} ->
        do_update_contact(access_token, resource_name, contact_data)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  @doc """
  Delete a contact.
  """
  def delete_contact(user, resource_name) do
    case GoogleAuth.get_access_token(user) do
      {:ok, access_token} ->
        do_delete_contact(access_token, resource_name)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  @doc """
  Get user's own profile information.
  """
  def get_user_profile(user) do
    case GoogleAuth.get_access_token(user) do
      {:ok, access_token} ->
        do_get_user_profile(access_token)

      {:error, reason} ->
        {:error, "Failed to get access token: #{reason}"}
    end
  end

  # Private functions

  defp do_search_contacts(access_token, query, opts) do
    page_size = Keyword.get(opts, :page_size, 20)
    url = "#{@people_api_url}/people/me/connections"

    params = %{
      query: query,
      pageSize: page_size,
      personFields: "names,emailAddresses,phoneNumbers,addresses,organizations,birthdays,photos,urls,userDefined,biographies,coverPhotos,interests,locales,memberships,metadata,relations,skills,ageRanges,ageRange,clientData,externalIds,fileAses,imClients,interests,locales,memberships,metadata,names,nicknames,occupations,organizations,phoneNumbers,photos,relations,residences,skills,sipAddresses,urls,userDefined"
    }

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ], params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"connections" => connections}} ->
            {:ok, Enum.map(connections, &format_contact/1)}

          {:ok, %{"error" => error}} ->
            {:error, "People API error: #{inspect(error)}"}

          _ ->
            {:ok, []}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "People API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error searching contacts: #{inspect(reason)}"}
    end
  end

  defp do_get_all_contacts(access_token, opts) do
    page_size = Keyword.get(opts, :page_size, 100)
    url = "#{@people_api_url}/people/me/connections"

    params = %{
      pageSize: page_size,
      personFields: "names,emailAddresses,phoneNumbers,addresses,organizations,birthdays,photos,urls,userDefined,biographies,coverPhotos,interests,locales,memberships,metadata,relations,skills,ageRanges,ageRange,clientData,externalIds,fileAses,imClients,interests,locales,memberships,metadata,names,nicknames,occupations,organizations,phoneNumbers,photos,relations,residences,skills,sipAddresses,urls,userDefined"
    }

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ], params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"connections" => connections}} ->
            {:ok, Enum.map(connections, &format_contact/1)}

          {:ok, %{"error" => error}} ->
            {:error, "People API error: #{inspect(error)}"}

          _ ->
            {:ok, []}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "People API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error getting contacts: #{inspect(reason)}"}
    end
  end

  defp do_get_contact(access_token, resource_name) do
    url = "#{@people_api_url}/#{resource_name}"

    params = %{
      personFields: "names,emailAddresses,phoneNumbers,addresses,organizations,birthdays,photos,urls,userDefined,biographies,coverPhotos,interests,locales,memberships,metadata,relations,skills,ageRanges,ageRange,clientData,externalIds,fileAses,imClients,interests,locales,memberships,metadata,names,nicknames,occupations,organizations,phoneNumbers,photos,relations,residences,skills,sipAddresses,urls,userDefined"
    }

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ], params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, contact} ->
            {:ok, format_contact(contact)}

          {:ok, %{"error" => error}} ->
            {:error, "People API error: #{inspect(error)}"}

          _ ->
            {:error, "Invalid response format"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "People API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error getting contact: #{inspect(reason)}"}
    end
  end

  defp do_create_contact(access_token, contact_data) do
    url = "#{@people_api_url}/people:createContact"

    body = Jason.encode!(contact_data)

    case HTTPoison.post(url, body, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, contact} ->
            {:ok, format_contact(contact)}

          {:ok, %{"error" => error}} ->
            {:error, "People API error: #{inspect(error)}"}

          _ ->
            {:error, "Invalid response format"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "People API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error creating contact: #{inspect(reason)}"}
    end
  end

  defp do_update_contact(access_token, resource_name, contact_data) do
    url = "#{@people_api_url}/#{resource_name}:updateContact"

    body = Jason.encode!(contact_data)

    case HTTPoison.patch(url, body, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, contact} ->
            {:ok, format_contact(contact)}

          {:ok, %{"error" => error}} ->
            {:error, "People API error: #{inspect(error)}"}

          _ ->
            {:error, "Invalid response format"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "People API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error updating contact: #{inspect(reason)}"}
    end
  end

  defp do_delete_contact(access_token, resource_name) do
    url = "#{@people_api_url}/#{resource_name}:deleteContact"

    case HTTPoison.delete(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %{status_code: 204}} ->
        {:ok, "Contact deleted successfully"}

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "People API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error deleting contact: #{inspect(reason)}"}
    end
  end

  defp do_get_user_profile(access_token) do
    url = "#{@people_api_url}/people/me"

    params = %{
      personFields: "names,emailAddresses,phoneNumbers,addresses,organizations,birthdays,photos,urls,userDefined,biographies,coverPhotos,interests,locales,memberships,metadata,relations,skills,ageRanges,ageRange,clientData,externalIds,fileAses,imClients,interests,locales,memberships,metadata,names,nicknames,occupations,organizations,phoneNumbers,photos,relations,residences,skills,sipAddresses,urls,userDefined"
    }

    case HTTPoison.get(url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ], params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, profile} ->
            {:ok, format_contact(profile)}

          {:ok, %{"error" => error}} ->
            {:error, "People API error: #{inspect(error)}"}

          _ ->
            {:error, "Invalid response format"}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "People API error: #{status_code} #{body}"}

      {:error, reason} ->
        {:error, "HTTP error getting profile: #{inspect(reason)}"}
    end
  end

  defp format_contact(contact) do
    %{
      resource_name: contact["resourceName"],
      etag: contact["etag"],
      names: extract_names(contact["names"]),
      email_addresses: extract_email_addresses(contact["emailAddresses"]),
      phone_numbers: extract_phone_numbers(contact["phoneNumbers"]),
      addresses: extract_addresses(contact["addresses"]),
      organizations: extract_organizations(contact["organizations"]),
      birthdays: extract_birthdays(contact["birthdays"]),
      photos: extract_photos(contact["photos"]),
      urls: extract_urls(contact["urls"]),
      user_defined: extract_user_defined(contact["userDefined"]),
      biographies: extract_biographies(contact["biographies"]),
      interests: extract_interests(contact["interests"]),
      locales: extract_locales(contact["locales"]),
      memberships: extract_memberships(contact["memberships"]),
      relations: extract_relations(contact["relations"]),
      skills: extract_skills(contact["skills"]),
      age_ranges: extract_age_ranges(contact["ageRanges"]),
      external_ids: extract_external_ids(contact["externalIds"]),
      im_clients: extract_im_clients(contact["imClients"]),
      nicknames: extract_nicknames(contact["nicknames"]),
      occupations: extract_occupations(contact["occupations"]),
      residences: extract_residences(contact["residences"]),
      sip_addresses: extract_sip_addresses(contact["sipAddresses"]),
      metadata: contact["metadata"],
      client_data: contact["clientData"]
    }
  end

  # Helper functions to extract and format contact data
  defp extract_names(names) when is_list(names) do
    Enum.map(names, fn name ->
      %{
        metadata: name["metadata"],
        display_name: name["displayName"],
        family_name: name["familyName"],
        given_name: name["givenName"],
        middle_name: name["middleName"],
        honorific_prefix: name["honorificPrefix"],
        honorific_suffix: name["honorificSuffix"],
        phonetic_family_name: name["phoneticFamilyName"],
        phonetic_given_name: name["phoneticGivenName"],
        phonetic_middle_name: name["phoneticMiddleName"],
        phonetic_honorific_prefix: name["phoneticHonorificPrefix"],
        phonetic_honorific_suffix: name["phoneticHonorificSuffix"]
      }
    end)
  end

  defp extract_names(_), do: []

  defp extract_email_addresses(emails) when is_list(emails) do
    Enum.map(emails, fn email ->
      %{
        metadata: email["metadata"],
        value: email["value"],
        type: email["type"],
        formatted_type: email["formattedType"],
        display_name: email["displayName"]
      }
    end)
  end

  defp extract_email_addresses(_), do: []

  defp extract_phone_numbers(phones) when is_list(phones) do
    Enum.map(phones, fn phone ->
      %{
        metadata: phone["metadata"],
        value: phone["value"],
        type: phone["type"],
        formatted_type: phone["formattedType"],
        canonical_form: phone["canonicalForm"]
      }
    end)
  end

  defp extract_phone_numbers(_), do: []

  defp extract_addresses(addresses) when is_list(addresses) do
    Enum.map(addresses, fn address ->
      %{
        metadata: address["metadata"],
        type: address["type"],
        formatted_type: address["formattedType"],
        formatted_value: address["formattedValue"],
        po_box: address["poBox"],
        street_address: address["streetAddress"],
        extended_address: address["extendedAddress"],
        city: address["city"],
        region: address["region"],
        postal_code: address["postalCode"],
        country: address["country"],
        country_code: address["countryCode"]
      }
    end)
  end

  defp extract_addresses(_), do: []

  defp extract_organizations(orgs) when is_list(orgs) do
    Enum.map(orgs, fn org ->
      %{
        metadata: org["metadata"],
        type: org["type"],
        formatted_type: org["formattedType"],
        name: org["name"],
        title: org["title"],
        job_description: org["jobDescription"],
        symbol: org["symbol"],
        domain: org["domain"],
        location: org["location"],
        department: org["department"],
        cost_center: org["costCenter"],
        current: org["current"]
      }
    end)
  end

  defp extract_organizations(_), do: []

  defp extract_birthdays(birthdays) when is_list(birthdays) do
    Enum.map(birthdays, fn birthday ->
      %{
        metadata: birthday["metadata"],
        date: birthday["date"],
        text: birthday["text"]
      }
    end)
  end

  defp extract_birthdays(_), do: []

  defp extract_photos(photos) when is_list(photos) do
    Enum.map(photos, fn photo ->
      %{
        metadata: photo["metadata"],
        url: photo["url"],
        default: photo["default"]
      }
    end)
  end

  defp extract_photos(_), do: []

  defp extract_urls(urls) when is_list(urls) do
    Enum.map(urls, fn url ->
      %{
        metadata: url["metadata"],
        value: url["value"],
        type: url["type"],
        formatted_type: url["formattedType"]
      }
    end)
  end

  defp extract_urls(_), do: []

  defp extract_user_defined(user_defined) when is_list(user_defined) do
    Enum.map(user_defined, fn ud ->
      %{
        metadata: ud["metadata"],
        key: ud["key"],
        value: ud["value"]
      }
    end)
  end

  defp extract_user_defined(_), do: []

  defp extract_biographies(bios) when is_list(bios) do
    Enum.map(bios, fn bio ->
      %{
        metadata: bio["metadata"],
        value: bio["value"],
        content_type: bio["contentType"]
      }
    end)
  end

  defp extract_biographies(_), do: []

  defp extract_interests(interests) when is_list(interests) do
    Enum.map(interests, fn interest ->
      %{
        metadata: interest["metadata"],
        value: interest["value"]
      }
    end)
  end

  defp extract_interests(_), do: []

  defp extract_locales(locales) when is_list(locales) do
    Enum.map(locales, fn locale ->
      %{
        metadata: locale["metadata"],
        value: locale["value"]
      }
    end)
  end

  defp extract_locales(_), do: []

  defp extract_memberships(memberships) when is_list(memberships) do
    Enum.map(memberships, fn membership ->
      %{
        metadata: membership["metadata"],
        contact_group_membership: membership["contactGroupMembership"],
        domain_membership: membership["domainMembership"]
      }
    end)
  end

  defp extract_memberships(_), do: []

  defp extract_relations(relations) when is_list(relations) do
    Enum.map(relations, fn relation ->
      %{
        metadata: relation["metadata"],
        person: relation["person"],
        type: relation["type"],
        formatted_type: relation["formattedType"]
      }
    end)
  end

  defp extract_relations(_), do: []

  defp extract_skills(skills) when is_list(skills) do
    Enum.map(skills, fn skill ->
      %{
        metadata: skill["metadata"],
        value: skill["value"]
      }
    end)
  end

  defp extract_skills(_), do: []

  defp extract_age_ranges(age_ranges) when is_list(age_ranges) do
    Enum.map(age_ranges, fn age_range ->
      %{
        metadata: age_range["metadata"],
        age_range: age_range["ageRange"]
      }
    end)
  end

  defp extract_age_ranges(_), do: []

  defp extract_external_ids(external_ids) when is_list(external_ids) do
    Enum.map(external_ids, fn external_id ->
      %{
        metadata: external_id["metadata"],
        type: external_id["type"],
        value: external_id["value"]
      }
    end)
  end

  defp extract_external_ids(_), do: []

  defp extract_im_clients(im_clients) when is_list(im_clients) do
    Enum.map(im_clients, fn im_client ->
      %{
        metadata: im_client["metadata"],
        type: im_client["type"],
        formatted_type: im_client["formattedType"],
        protocol: im_client["protocol"],
        username: im_client["username"]
      }
    end)
  end

  defp extract_im_clients(_), do: []

  defp extract_nicknames(nicknames) when is_list(nicknames) do
    Enum.map(nicknames, fn nickname ->
      %{
        metadata: nickname["metadata"],
        value: nickname["value"],
        type: nickname["type"]
      }
    end)
  end

  defp extract_nicknames(_), do: []

  defp extract_occupations(occupations) when is_list(occupations) do
    Enum.map(occupations, fn occupation ->
      %{
        metadata: occupation["metadata"],
        value: occupation["value"]
      }
    end)
  end

  defp extract_occupations(_), do: []

  defp extract_residences(residences) when is_list(residences) do
    Enum.map(residences, fn residence ->
      %{
        metadata: residence["metadata"],
        value: residence["value"],
        current: residence["current"]
      }
    end)
  end

  defp extract_residences(_), do: []

  defp extract_sip_addresses(sip_addresses) when is_list(sip_addresses) do
    Enum.map(sip_addresses, fn sip_address ->
      %{
        metadata: sip_address["metadata"],
        value: sip_address["value"],
        type: sip_address["type"],
        formatted_type: sip_address["formattedType"]
      }
    end)
  end

  defp extract_sip_addresses(_), do: []
end
