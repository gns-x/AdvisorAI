defmodule AdvisorAiWeb.HubspotOauthController do
  use AdvisorAiWeb, :controller
  alias AdvisorAi.Accounts

  plug :fetch_session

  @hubspot_client_id System.get_env("HUBSPOT_CLIENT_ID")
  @hubspot_client_secret System.get_env("HUBSPOT_CLIENT_SECRET")
  @redirect_uri System.get_env("HUBSPOT_REDIRECT_URI") || "http://localhost:4000/hubspot/oauth/callback"

  def debug(conn, _params) do
    config = %{
      client_id: @hubspot_client_id,
      client_secret: if(@hubspot_client_secret, do: "SET", else: "NOT SET"),
      redirect_uri: @redirect_uri,
      test_url: "https://app-eu1.hubspot.com/oauth/authorize?client_id=#{@hubspot_client_id}&redirect_uri=#{URI.encode(@redirect_uri)}&scope=crm.objects.contacts.write%20crm.schemas.contacts.write%20oauth%20crm.schemas.contacts.read%20crm.objects.contacts.read&response_type=code&state=test123",
      instructions: [
        "1. Go to https://developers.hubspot.com/",
        "2. Find app with ID: #{@hubspot_client_id}",
        "3. Look for 'App Status', 'Development Mode', or 'Publish' options",
        "4. Make sure OAuth is enabled",
        "5. Verify redirect URI is listed",
        "6. Check that 'oauth' scope is enabled"
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(config))
  end

  def test_api_key(conn, _params) do
    case AdvisorAi.Integrations.HubSpot.test_api_key_connection() do
      {:ok, message} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "success", message: message}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{status: "error", message: reason}))
    end
  end

  def help(conn, _params) do
    help_info = %{
      title: "HubSpot Integration Help",
      methods: [
        %{
          name: "Private App Access Token (Recommended)",
          description: "Create a private app in HubSpot to get an access token",
          steps: [
            "1. Go to https://app.hubspot.com/settings/account/private-apps",
            "2. Click 'Create private app'",
            "3. Give your app a name (e.g., 'Advisor AI Integration')",
            "4. Select scopes: crm.objects.contacts.read, crm.objects.contacts.write",
            "5. Click 'Create app'",
            "6. Copy the access token (starts with 'pat-')",
            "7. Add HUBSPOT_PRIVATE_APP_TOKEN=your_token to your .env file"
          ],
          note: "This is the modern way to integrate with HubSpot"
        },
        %{
          name: "OAuth 2.0 (Alternative)",
          description: "Use OAuth for user-specific access",
          steps: [
            "1. Go to https://developers.hubspot.com/",
            "2. Create or configure your app",
            "3. Enable OAuth 2.0",
            "4. Add redirect URI: http://localhost:4000/hubspot/oauth/callback",
            "5. Set required scopes",
            "6. Use the 'Connect with OAuth' button above"
          ],
          note: "Requires app approval and user consent"
        }
      ],
      troubleshooting: [
        "If you get 'Invalid API key' error: API keys are deprecated, use Private App Tokens instead",
        "If OAuth fails: Check your app configuration and scopes",
        "For more help: https://developers.hubspot.com/docs/api/overview"
      ]
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(help_info))
  end

  def connect(conn, _params) do
    # Generate a random state for security
    state = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

    # Store state in session for verification
    conn = put_session(conn, :hubspot_oauth_state, state)

    # Use the scopes that HubSpot confirmed work with this app
    scopes = "crm.objects.contacts.write crm.schemas.contacts.write oauth crm.schemas.contacts.read crm.objects.contacts.read"

    # Build the OAuth URL manually to ensure proper formatting
    params = %{
      client_id: @hubspot_client_id,
      redirect_uri: @redirect_uri,
      scope: scopes,
      response_type: "code",
      state: state
    }

    query_string = params
    |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode(v)}" end)
    |> Enum.join("&")

    url = "https://app.hubspot.com/oauth/authorize?#{query_string}"

    # Log for debugging
    IO.puts("HubSpot OAuth URL: #{url}")
    IO.puts("Client ID: #{@hubspot_client_id}")
    IO.puts("Redirect URI: #{@redirect_uri}")
    IO.puts("Scopes: #{scopes}")

    redirect(conn, external: url)
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    # Verify state parameter
    stored_state = get_session(conn, :hubspot_oauth_state)
    if state != stored_state do
      conn
      |> put_flash(:error, "OAuth state verification failed. Please try again.")
      |> redirect(to: "/settings/integrations")
    else
      # Exchange code for tokens
      body = URI.encode_query(%{
        grant_type: "authorization_code",
        client_id: @hubspot_client_id,
        client_secret: @hubspot_client_secret,
        redirect_uri: @redirect_uri,
        code: code
      })

      headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

      case HTTPoison.post("https://api.hubapi.com/oauth/v1/token", body, headers) do
        {:ok, %{status_code: 200, body: resp_body}} ->
          case Jason.decode(resp_body) do
            {:ok, %{"access_token" => access_token, "refresh_token" => refresh_token, "expires_in" => expires_in}} ->
              # Get current user from assigns (should be available due to require_authenticated_user)
              user = conn.assigns.current_user
              expires_at = DateTime.add(DateTime.utc_now(), expires_in) |> DateTime.truncate(:second)

              # Store tokens in DB
              case Accounts.update_user_hubspot_tokens(user, access_token, refresh_token, expires_at) do
                {:ok, _updated_user} ->
                  conn
                  |> delete_session(:hubspot_oauth_state)
                  |> put_flash(:info, "HubSpot account connected successfully!")
                  |> redirect(to: "/settings/integrations")

                {:error, _changeset} ->
                  conn
                  |> put_flash(:error, "Failed to save HubSpot tokens to database.")
                  |> redirect(to: "/settings/integrations")
              end

            {:ok, %{"error" => error}} ->
              conn
              |> put_flash(:error, "HubSpot OAuth error: #{error}")
              |> redirect(to: "/settings/integrations")

            _ ->
              conn
              |> put_flash(:error, "Unexpected response from HubSpot.")
              |> redirect(to: "/settings/integrations")
          end

        {:ok, %{status_code: code, body: resp_body}} ->
          conn
          |> put_flash(:error, "HubSpot token exchange failed: #{code} #{resp_body}")
          |> redirect(to: "/settings/integrations")

        {:error, reason} ->
          conn
          |> put_flash(:error, "HTTP error: #{inspect(reason)}")
          |> redirect(to: "/settings/integrations")
      end
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Invalid OAuth callback parameters.")
    |> redirect(to: "/settings/integrations")
  end
end
