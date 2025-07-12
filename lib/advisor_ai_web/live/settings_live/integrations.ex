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
        hubspot_connected: has_valid_hubspot_tokens?(user),
        google_account: google_account,
        hubspot_account: hubspot_account,
        hubspot_oauth_status: "unknown"
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

  def handle_event("refresh_hubspot_status", _params, socket) do
    # Refresh user data to get latest HubSpot tokens
    updated_user = Accounts.get_user!(socket.assigns.user.id)

    {:noreply,
     assign(socket,
       user: updated_user,
       hubspot_connected: has_valid_hubspot_tokens?(updated_user)
     )}
  end

  def handle_event("update_message", _params, socket) do
    # Handle text input updates - just return the socket unchanged
    {:noreply, socket}
  end

  def handle_event("test_hubspot_oauth", _params, socket) do
    user = socket.assigns.user

    case AdvisorAi.Integrations.HubSpot.test_oauth_connection(user) do
      {:ok, _message} ->
        {:noreply, assign(socket, hubspot_oauth_status: "working")}

      {:error, _reason} ->
        {:noreply, assign(socket, hubspot_oauth_status: "failed")}
    end
  end

  defp has_valid_google_account?(account) do
    account != nil and account.access_token != nil and account.refresh_token != nil
  end

  defp has_valid_hubspot_tokens?(user) do
    user.hubspot_access_token != nil and user.hubspot_refresh_token != nil
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-50 to-blue-50">
      <div class="max-w-4xl mx-auto px-8 py-12">
        <div class="space-y-10">
          
    <!-- Header -->
          <div class="text-center">
            <div class="w-16 h-16 mx-auto mb-6 bg-gradient-to-r from-blue-500 to-blue-600 rounded-2xl flex items-center justify-center shadow-lg">
              <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 10V3L4 14h7v7l9-11h-7z"
                >
                </path>
              </svg>
            </div>
            <h1 class="text-4xl font-bold gradient-text mb-4">Integrations</h1>
            <p class="text-lg text-slate-600 max-w-2xl mx-auto">
              Connect your accounts to access emails, calendar, and CRM data with seamless integration.
            </p>
          </div>
          
    <!-- Integration Cards -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
            
    <!-- Google -->
            <div class="bg-white/90 backdrop-blur-sm rounded-2xl border border-slate-200/50 p-8 shadow-lg hover:shadow-xl transition-all hover:scale-[1.02]">
              <div class="flex items-center justify-between mb-6">
                <div class="flex items-center space-x-4">
                  <div class="w-12 h-12 bg-white/80 backdrop-blur-sm rounded-xl flex items-center justify-center border border-slate-200/50 shadow-md">
                    <svg class="w-7 h-7" viewBox="0 0 24 24">
                      <path
                        fill="#4285F4"
                        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                      />
                      <path
                        fill="#34A853"
                        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                      />
                      <path
                        fill="#FBBC05"
                        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                      />
                      <path
                        fill="#EA4335"
                        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                      />
                    </svg>
                  </div>
                  <div>
                    <h3 class="text-xl font-semibold text-slate-900">Google</h3>
                    <p class="text-sm text-slate-500">Gmail & Calendar</p>
                  </div>
                </div>
                <div class={"w-4 h-4 rounded-full #{if @google_connected, do: "bg-green-400 shadow-lg", else: "bg-slate-300"}"}>
                </div>
              </div>

              <div class="space-y-3 mb-6 text-sm text-slate-600">
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 bg-blue-50 rounded-lg flex items-center justify-center">
                    <svg
                      class="w-4 h-4 text-blue-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                      />
                    </svg>
                  </div>
                  <span>Read and send emails</span>
                </div>
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 bg-blue-50 rounded-lg flex items-center justify-center">
                    <svg
                      class="w-4 h-4 text-blue-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                      />
                    </svg>
                  </div>
                  <span>Manage calendar events</span>
                </div>
              </div>

              <%= if @google_connected do %>
                <div class="flex items-center justify-between">
                  <span class="text-sm text-green-600 font-medium flex items-center space-x-2">
                    <div class="w-2 h-2 bg-green-400 rounded-full"></div>
                    Connected
                  </span>
                  <button
                    phx-click="disconnect_google"
                    class="px-4 py-2 text-sm bg-red-50 text-red-600 rounded-xl hover:bg-red-100 transition-all hover:scale-105"
                  >
                    Disconnect
                  </button>
                </div>
              <% else %>
                <.link
                  href={~p"/auth/google"}
                  class="w-full px-6 py-3 bg-gradient-to-r from-blue-500 to-blue-600 text-white rounded-xl hover:from-blue-600 hover:to-blue-700 text-center block font-medium transition-all hover:scale-105 shadow-lg hover:shadow-xl"
                >
                  Connect Google
                </.link>
              <% end %>
            </div>
            
    <!-- HubSpot -->
            <div class="bg-white/90 backdrop-blur-sm rounded-2xl border border-slate-200/50 p-8 shadow-lg hover:shadow-xl transition-all hover:scale-[1.02]">
              <div class="flex items-center justify-between mb-6">
                <div class="flex items-center space-x-4">
                  <div class="w-12 h-12 bg-white/80 backdrop-blur-sm rounded-xl flex items-center justify-center border border-slate-200/50 shadow-md">
                    <svg class="w-7 h-7" viewBox="0 0 24 24">
                      <path
                        fill="#FF7A59"
                        d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm0 22C6.486 22 2 17.514 2 12S6.486 2 12 2s10 4.486 10 10-4.486 10-10 10z"
                      />
                      <path
                        fill="#FF7A59"
                        d="M12 4c-4.411 0-8 3.589-8 8s3.589 8 8 8 8-3.589 8-8-3.589-8-8-8zm0 14c-3.314 0-6-2.686-6-6s2.686-6 6-6 6 2.686 6 6-2.686 6-6 6z"
                      />
                    </svg>
                  </div>
                  <div>
                    <h3 class="text-xl font-semibold text-slate-900">HubSpot</h3>
                    <p class="text-sm text-slate-500">CRM & Contacts</p>
                  </div>
                </div>
                <div class={"w-4 h-4 rounded-full #{if @hubspot_connected, do: "bg-green-400 shadow-lg", else: "bg-slate-300"}"}>
                </div>
              </div>

              <div class="space-y-3 mb-6 text-sm text-slate-600">
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 bg-orange-50 rounded-lg flex items-center justify-center">
                    <svg
                      class="w-4 h-4 text-orange-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                      />
                    </svg>
                  </div>
                  <span>Manage contacts & deals</span>
                </div>
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 bg-orange-50 rounded-lg flex items-center justify-center">
                    <svg
                      class="w-4 h-4 text-orange-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                      />
                    </svg>
                  </div>
                  <span>Track interactions</span>
                </div>
              </div>

              <%= if @hubspot_connected do %>
                <div class="flex items-center justify-between">
                  <span class="text-sm text-green-600 font-medium flex items-center space-x-2">
                    <div class="w-2 h-2 bg-green-400 rounded-full"></div>
                    Connected
                  </span>
                  <button
                    phx-click="disconnect_hubspot"
                    class="px-4 py-2 text-sm bg-red-50 text-red-600 rounded-xl hover:bg-red-100 transition-all hover:scale-105"
                  >
                    Disconnect
                  </button>
                </div>
              <% else %>
                <.link
                  href={~p"/hubspot/oauth/connect"}
                  class="w-full px-6 py-3 bg-gradient-to-r from-orange-500 to-orange-600 text-white rounded-xl hover:from-orange-600 hover:to-orange-700 text-center block font-medium transition-all hover:scale-105 shadow-lg hover:shadow-xl"
                >
                  Connect HubSpot
                </.link>
              <% end %>
            </div>
          </div>
          
    <!-- Status Section -->
          <div class="bg-white/90 backdrop-blur-sm rounded-2xl border border-slate-200/50 p-8 shadow-lg">
            <h3 class="text-xl font-semibold text-slate-900 mb-6">Connection Status</h3>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div class="flex items-center space-x-4">
                <div class={"w-3 h-3 rounded-full #{if @google_connected, do: "bg-green-400", else: "bg-slate-300"}"}>
                </div>
                <span class="text-sm text-slate-600">
                  Google: {if @google_connected, do: "Connected", else: "Not connected"}
                </span>
              </div>
              <div class="flex items-center space-x-4">
                <div class={"w-3 h-3 rounded-full #{if @hubspot_connected, do: "bg-green-400", else: "bg-slate-300"}"}>
                </div>
                <span class="text-sm text-slate-600">
                  HubSpot: {if @hubspot_connected, do: "Connected", else: "Not connected"}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
