defmodule AdvisorAiWeb.SettingsLive.Integrations do
  use AdvisorAiWeb, :live_view

  alias AdvisorAi.Accounts
  alias AdvisorAi.Integrations.Gmail

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Get connection status from accounts table
    google_account = Accounts.get_user_google_account(user.id)
    hubspot_account = Accounts.get_user_hubspot_account(user.id)

    socket =
      assign(socket,
        user: user,
        google_connected: has_valid_google_account?(google_account),
        hubspot_connected: has_valid_hubspot_account?(hubspot_account),
        google_account: google_account,
        hubspot_account: hubspot_account,
        hubspot_api_key: System.get_env("HUBSPOT_API_KEY", ""),
        syncing_emails: false
      )

    {:ok, socket}
  end

  def handle_event("disconnect_google", _params, socket) do
    user = socket.assigns.user

    # Delete Google account from accounts table
    case socket.assigns.google_account do
      nil ->
        {:noreply, socket}
      account ->
        AdvisorAi.Repo.delete(account)
        {:noreply, assign(socket, google_connected: false, google_account: nil)}
    end
  end

  def handle_event("disconnect_hubspot", _params, socket) do
    user = socket.assigns.user
    # Clear HubSpot tokens
    {:ok, updated_user} =
      Accounts.update_user(user, %{
        hubspot_access_token: nil,
        hubspot_refresh_token: nil
      })

    {:noreply, assign(socket, user: updated_user, hubspot_connected: false)}
  end

  def handle_event("sync_emails", _params, socket) do
    user = socket.assigns.user

    if socket.assigns.google_connected do
      # Start sync in background
      Task.async(fn ->
        Gmail.sync_emails(user)
      end)

      {:noreply,
       socket
       |> assign(:syncing_emails, true)
       |> put_flash(:info, "Email sync started. This may take a few minutes.")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please connect your Google account first.")}
    end
  end

  def handle_event("update_message", _params, socket) do
    # Handle text input updates - just return the socket unchanged
    {:noreply, socket}
  end

  def handle_info({ref, {:ok, result}}, socket) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> assign(:syncing_emails, false)
     |> put_flash(:info, result)}
  end

  def handle_info({ref, {:error, reason}}, socket) do
    Process.demonitor(ref, [:flush])

    {:noreply,
     socket
     |> assign(:syncing_emails, false)
     |> put_flash(:error, "Email sync failed: #{reason}")}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  defp has_valid_google_account?(account) do
    account != nil and account.access_token != nil and account.refresh_token != nil
  end

  defp has_valid_hubspot_account?(account) do
    account != nil and account.access_token != nil and account.refresh_token != nil
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Main Content -->
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="space-y-8">

    <!-- Page Header -->
          <div class="text-center">
            <h2 class="text-3xl font-bold text-gray-900 mb-4">Integrations</h2>
            <p class="text-lg text-gray-600 max-w-2xl mx-auto">
              Connect your accounts to enable AdvisorAI to access your emails, calendar, and CRM data.
            </p>
          </div>

    <!-- OAuth Setup Notice -->
          <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor">
                  <path
                    fill-rule="evenodd"
                    d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-yellow-800">OAuth Setup Required</h3>
                <div class="mt-2 text-sm text-yellow-700">
                  <p>
                    To use OAuth integrations, you need to set up OAuth apps and configure environment variables:
                  </p>
                  <ul class="list-disc list-inside mt-1 space-y-1">
                    <li>
                      <strong>Google:</strong>
                      Create OAuth app at
                      <a href="https://console.developers.google.com" class="underline">
                        Google Cloud Console
                      </a>
                    </li>
                    <li>
                      <strong>HubSpot:</strong>
                      Create OAuth app at
                      <a href="https://developers.hubspot.com" class="underline">
                        HubSpot Developers
                      </a>
                    </li>
                    <li>
                      Set environment variables: <code class="bg-yellow-100 px-1 rounded">GOOGLE_CLIENT_ID</code>, <code class="bg-yellow-100 px-1 rounded">GOOGLE_CLIENT_SECRET</code>, <code class="bg-yellow-100 px-1 rounded">HUBSPOT_CLIENT_ID</code>,
                      <code class="bg-yellow-100 px-1 rounded">HUBSPOT_CLIENT_SECRET</code>
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </div>

    <!-- Integration Cards -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">

    <!-- Google Integration -->
            <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
              <div class="flex items-start justify-between mb-4">
                <div class="flex items-center space-x-3">
                  <div class="w-12 h-12 bg-gradient-to-r from-blue-500 to-red-500 rounded-lg flex items-center justify-center">
                    <svg class="w-6 h-6 text-white" viewBox="0 0 24 24">
                      <path
                        fill="currentColor"
                        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                      />
                      <path
                        fill="currentColor"
                        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                      />
                      <path
                        fill="currentColor"
                        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                      />
                      <path
                        fill="currentColor"
                        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                      />
                    </svg>
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-gray-900">Google</h3>
                    <p class="text-sm text-gray-500">Gmail & Calendar</p>
                  </div>
                </div>
                <div class={"w-3 h-3 rounded-full #{if @google_connected, do: "bg-green-400", else: "bg-gray-300"}"}>
                </div>
              </div>

              <div class="space-y-3 mb-6">
                <div class="flex items-center space-x-2 text-sm text-gray-600">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                    >
                    </path>
                  </svg>
                  <span>Read and send emails</span>
                </div>
                <div class="flex items-center space-x-2 text-sm text-gray-600">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                    >
                    </path>
                  </svg>
                  <span>Manage calendar events</span>
                </div>
              </div>

              <div class="space-y-3">
                <%= if @google_connected do %>
                  <div class="flex items-center justify-between">
                    <span class="text-sm text-green-600 font-medium">Connected</span>
                    <button
                      phx-click="disconnect_google"
                      class="px-4 py-2 text-sm bg-red-100 text-red-700 rounded-lg hover:bg-red-200 transition-colors"
                    >
                      Disconnect
                    </button>
                  </div>

                  <!-- Email Sync Button -->
                  <div class="pt-3 border-t border-gray-200">
                    <button
                      phx-click="sync_emails"
                      disabled={@syncing_emails}
                      class={"w-full px-4 py-2 text-sm rounded-lg transition-colors #{if @syncing_emails, do: "bg-gray-100 text-gray-500 cursor-not-allowed", else: "bg-green-100 text-green-700 hover:bg-green-200"}"}
                    >
                      <%= if @syncing_emails do %>
                        <div class="flex items-center justify-center space-x-2">
                          <div class="w-4 h-4 border-2 border-green-600 border-t-transparent rounded-full animate-spin"></div>
                          <span>Syncing emails...</span>
                        </div>
                      <% else %>
                        <div class="flex items-center justify-center space-x-2">
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                          </svg>
                          <span>Sync Recent Emails</span>
                        </div>
                      <% end %>
                    </button>
                    <p class="text-xs text-gray-500 mt-1 text-center">
                      Import your recent emails for AI analysis
                    </p>
                  </div>
                <% else %>
                  <.link
                    href={~p"/auth/google"}
                    class="w-full px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-center block font-medium"
                  >
                    Connect Google
                  </.link>
                <% end %>
              </div>
            </div>

    <!-- HubSpot Integration -->
            <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
              <div class="flex items-start justify-between mb-4">
                <div class="flex items-center space-x-3">
                  <div class="w-12 h-12 bg-gradient-to-r from-orange-500 to-red-500 rounded-lg flex items-center justify-center">
                    <svg
                      class="w-6 h-6 text-white"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                      >
                      </path>
                    </svg>
                  </div>
                  <div>
                    <h3 class="text-lg font-semibold text-gray-900">HubSpot</h3>
                    <p class="text-sm text-gray-500">CRM & Contacts</p>
                  </div>
                </div>
                <div class={"w-3 h-3 rounded-full #{if @hubspot_connected, do: "bg-green-400", else: "bg-gray-300"}"}>
                </div>
              </div>

              <div class="space-y-3 mb-6">
                <div class="flex items-center space-x-2 text-sm text-gray-600">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                    >
                    </path>
                  </svg>
                  <span>Manage contacts</span>
                </div>
                <div class="flex items-center space-x-2 text-sm text-gray-600">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                    >
                    </path>
                  </svg>
                  <span>Add notes and interactions</span>
                </div>
              </div>

              <div class="mt-6">
        <%= if @hubspot_connected do %>
                  <div class="flex items-center justify-between">
                    <span class="text-sm text-green-600 font-medium">Connected</span>
                    <button
                      phx-click="disconnect_hubspot"
                      class="px-4 py-2 text-sm bg-red-100 text-red-700 rounded-lg hover:bg-red-200 transition-colors"
                    >
                      Disconnect
                    </button>
                  </div>
        <% else %>
                  <div class="space-y-3">
                    <.link
                      href={~p"/auth/hubspot"}
                      class="w-full px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-700 transition-colors text-center block font-medium"
                    >
                      Connect HubSpot
                    </.link>

                    <!-- API Key Alternative -->
                    <div class="text-center">
                      <p class="text-xs text-gray-500 mb-2">Or use API key (for free accounts)</p>
                      <div class="text-xs text-gray-600 bg-gray-50 p-2 rounded">
                        Set <code class="bg-gray-100 px-1 rounded">HUBSPOT_API_KEY</code> environment variable
                      </div>
                    </div>
                  </div>
        <% end %>
              </div>
            </div>
          </div>

    <!-- Data Import Status -->
          <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Data Import Status</h3>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="text-center p-4 bg-gray-50 rounded-lg">
                <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center mx-auto mb-2">
                  <svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                  </svg>
                </div>
                <h4 class="text-sm font-medium text-gray-900">Emails</h4>
                <p class="text-xs text-gray-500 mt-1">
                  <%= if @google_connected, do: "Ready to sync", else: "Connect Google first" %>
                </p>
              </div>

              <div class="text-center p-4 bg-gray-50 rounded-lg">
                <div class="w-8 h-8 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-2">
                  <svg class="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                </div>
                <h4 class="text-sm font-medium text-gray-900">Calendar</h4>
                <p class="text-xs text-gray-500 mt-1">
                  <%= if @google_connected, do: "Connected", else: "Connect Google first" %>
                </p>
              </div>

              <div class="text-center p-4 bg-gray-50 rounded-lg">
                <div class="w-8 h-8 bg-orange-100 rounded-full flex items-center justify-center mx-auto mb-2">
                  <svg class="w-4 h-4 text-orange-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                  </svg>
                </div>
                <h4 class="text-sm font-medium text-gray-900">Contacts</h4>
                <p class="text-xs text-gray-500 mt-1">
                  <%= if @hubspot_connected, do: "Connected", else: "Connect HubSpot first" %>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
