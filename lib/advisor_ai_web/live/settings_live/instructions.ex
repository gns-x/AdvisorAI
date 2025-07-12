defmodule AdvisorAiWeb.SettingsLive.Instructions do
  use AdvisorAiWeb, :live_view

  alias AdvisorAi.AI.AgentInstruction

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    instructions = AgentInstruction.list_by_user(user.id)

    socket =
      assign(socket,
        instructions: instructions,
        new_instruction: %{instruction: "", triggers: [], active: true}
      )

    {:ok, socket}
  end

  # Handles regular LiveView form submits (map)
  def handle_event("save_instruction", %{"instruction" => _} = params, socket) do
    user = socket.assigns.current_user

    # Convert triggers array to trigger_type (take first one for now)
    params =
      case params do
        %{"triggers" => triggers} when is_list(triggers) and length(triggers) > 0 ->
          Map.put(params, "trigger_type", List.first(triggers))

        _ ->
          params
      end

    case AgentInstruction.create(Map.put(params, "user_id", user.id)) do
      {:ok, _instruction} ->
        instructions = AgentInstruction.list_by_user(user.id)
        socket = assign(socket, instructions: instructions)

        {:noreply,
         socket
         |> put_flash(:info, "Instruction saved successfully!")
         |> push_navigate(to: ~p"/settings/instructions")}

      {:error, changeset} ->
        {:noreply, assign(socket, new_instruction: changeset)}
    end
  end

  # Handles JS push events or custom submits (string)
  def handle_event("save_instruction", %{"value" => value}, socket) do
    params = URI.decode_query(value)
    user = socket.assigns.current_user

    # Convert triggers array to trigger_type (take first one for now)
    params =
      case params do
        %{"triggers" => triggers} when is_list(triggers) and length(triggers) > 0 ->
          Map.put(params, "trigger_type", List.first(triggers))

        _ ->
          params
      end

    case AgentInstruction.create(Map.put(params, "user_id", user.id)) do
      {:ok, _instruction} ->
        instructions = AgentInstruction.list_by_user(user.id)
        socket = assign(socket, instructions: instructions)

        {:noreply,
         socket
         |> put_flash(:info, "Instruction saved successfully!")
         |> push_navigate(to: ~p"/settings/instructions")}

      {:error, changeset} ->
        {:noreply, assign(socket, new_instruction: changeset)}
    end
  end

  def handle_event("toggle_instruction", %{"id" => id}, socket) do
    instruction = AgentInstruction.get!(id)

    {:ok, updated_instruction} =
      AgentInstruction.update(instruction, %{is_active: !instruction.is_active})

    instructions =
      Enum.map(socket.assigns.instructions, fn i ->
        if i.id == id, do: updated_instruction, else: i
      end)

    {:noreply, assign(socket, instructions: instructions)}
  end

  def handle_event("delete_instruction", %{"id" => id}, socket) do
    instruction = AgentInstruction.get!(id)
    {:ok, _} = AgentInstruction.delete(instruction)

    instructions = Enum.reject(socket.assigns.instructions, fn i -> i.id == id end)

    {:noreply,
     socket
     |> assign(instructions: instructions)
     |> put_flash(:info, "Instruction deleted successfully!")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-50 to-blue-50">
      <!-- Main Content -->
      <div class="max-w-4xl mx-auto px-8 py-12">
        <div class="space-y-10">
          
    <!-- Page Header -->
          <div class="text-center">
            <div class="w-16 h-16 mx-auto mb-6 bg-gradient-to-r from-purple-500 to-purple-600 rounded-2xl flex items-center justify-center shadow-lg">
              <svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
                >
                </path>
              </svg>
            </div>
            <h2 class="text-4xl font-bold gradient-text mb-4">Ongoing Instructions</h2>
            <p class="text-lg text-slate-600 max-w-2xl mx-auto">
              Set up instructions for your AI assistant to follow automatically. These will be applied when relevant events occur.
            </p>
          </div>
          
    <!-- Add New Instruction -->
          <div class="bg-white/90 backdrop-blur-sm rounded-2xl border border-slate-200/50 p-8 shadow-lg">
            <h3 class="text-xl font-semibold text-slate-900 mb-6">Add New Instruction</h3>

            <form phx-submit="save_instruction" class="space-y-6">
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-3">
                  Instruction
                </label>
                <textarea
                  name="instruction"
                  rows="4"
                  class="w-full px-6 py-4 border border-slate-200/50 rounded-xl focus:ring-2 focus:ring-purple-500 focus:border-transparent resize-none bg-white/80 backdrop-blur-sm transition-all"
                  placeholder="e.g., When someone emails me that is not in HubSpot, please create a contact in HubSpot with a note about the email."
                  required
                ></textarea>
              </div>

              <div>
                <label class="block text-sm font-medium text-slate-700 mb-3">
                  Triggers
                </label>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <label class="flex items-center space-x-3 p-4 bg-white/60 backdrop-blur-sm rounded-xl border border-slate-200/50 hover:bg-white/80 transition-all cursor-pointer">
                    <input
                      type="checkbox"
                      name="triggers[]"
                      value="email_received"
                      class="rounded border-slate-300 text-purple-600 focus:ring-purple-500"
                    />
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
                        >
                        </path>
                      </svg>
                    </div>
                    <span class="text-sm text-slate-700 font-medium">Email Received</span>
                  </label>
                  <label class="flex items-center space-x-3 p-4 bg-white/60 backdrop-blur-sm rounded-xl border border-slate-200/50 hover:bg-white/80 transition-all cursor-pointer">
                    <input
                      type="checkbox"
                      name="triggers[]"
                      value="calendar_event"
                      class="rounded border-slate-300 text-purple-600 focus:ring-purple-500"
                    />
                    <div class="w-8 h-8 bg-green-50 rounded-lg flex items-center justify-center">
                      <svg
                        class="w-4 h-4 text-green-600"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                        >
                        </path>
                      </svg>
                    </div>
                    <span class="text-sm text-slate-700 font-medium">Calendar Event</span>
                  </label>
                  <label class="flex items-center space-x-3 p-4 bg-white/60 backdrop-blur-sm rounded-xl border border-slate-200/50 hover:bg-white/80 transition-all cursor-pointer">
                    <input
                      type="checkbox"
                      name="triggers[]"
                      value="hubspot_contact"
                      class="rounded border-slate-300 text-purple-600 focus:ring-purple-500"
                    />
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
                        >
                        </path>
                      </svg>
                    </div>
                    <span class="text-sm text-slate-700 font-medium">HubSpot Contact</span>
                  </label>
                </div>
              </div>

              <div class="flex items-center space-x-3 p-4 bg-white/60 backdrop-blur-sm rounded-xl border border-slate-200/50">
                <input
                  type="checkbox"
                  name="active"
                  value="true"
                  checked
                  class="rounded border-slate-300 text-purple-600 focus:ring-purple-500"
                />
                <span class="text-sm text-slate-700 font-medium">Active</span>
              </div>

              <button
                type="submit"
                class="w-full px-8 py-4 bg-gradient-to-r from-purple-500 to-purple-600 text-white rounded-xl hover:from-purple-600 hover:to-purple-700 transition-all font-medium shadow-lg hover:shadow-xl hover:scale-[1.02]"
              >
                Save Instruction
              </button>
            </form>
          </div>
          
    <!-- Existing Instructions -->
          <div class="bg-white/90 backdrop-blur-sm rounded-2xl border border-slate-200/50 p-8 shadow-lg">
            <h3 class="text-xl font-semibold text-slate-900 mb-6">Your Instructions</h3>

            <div class="space-y-6">
              <%= for instruction <- @instructions do %>
                <div class="bg-white/80 backdrop-blur-sm border border-slate-200/50 rounded-xl p-6 hover:shadow-lg transition-all hover:scale-[1.01]">
                  <div class="flex items-start justify-between">
                    <div class="flex-1">
                      <div class="flex items-center space-x-3 mb-3">
                        <div class="w-8 h-8 bg-purple-50 rounded-lg flex items-center justify-center">
                          <svg
                            class="w-4 h-4 text-purple-600"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
                            >
                            </path>
                          </svg>
                        </div>
                        <h4 class="text-lg font-semibold text-slate-900">
                          {instruction.instruction}
                        </h4>
                      </div>

                      <div class="flex items-center space-x-4 text-sm text-slate-600 mb-4">
                        <span class="flex items-center space-x-2">
                          <div class="w-2 h-2 bg-purple-400 rounded-full"></div>
                          <span>Trigger: {instruction.trigger_type}</span>
                        </span>
                        <span class="flex items-center space-x-2">
                          <div class={"w-2 h-2 rounded-full #{if instruction.is_active, do: "bg-green-400", else: "bg-slate-300"}"}>
                          </div>
                          <span>{if instruction.is_active, do: "Active", else: "Inactive"}</span>
                        </span>
                      </div>

                      <div class="flex items-center space-x-3">
                        <button
                          phx-click="toggle_instruction"
                          phx-value-id={instruction.id}
                          class={"px-4 py-2 text-sm rounded-xl transition-all hover:scale-105 #{if instruction.is_active, do: "bg-green-50 text-green-600 hover:bg-green-100", else: "bg-slate-50 text-slate-600 hover:bg-slate-100"}"}
                        >
                          {if instruction.is_active, do: "Deactivate", else: "Activate"}
                        </button>
                        <button
                          phx-click="delete_instruction"
                          phx-value-id={instruction.id}
                          class="px-4 py-2 text-sm bg-red-50 text-red-600 rounded-xl hover:bg-red-100 transition-all hover:scale-105"
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if length(@instructions) == 0 do %>
                <div class="text-center py-12">
                  <div class="w-16 h-16 mx-auto mb-4 bg-slate-100 rounded-2xl flex items-center justify-center">
                    <svg
                      class="w-8 h-8 text-slate-400"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
                      >
                      </path>
                    </svg>
                  </div>
                  <h3 class="text-lg font-semibold text-slate-900 mb-2">No Instructions Yet</h3>
                  <p class="text-slate-600">Create your first instruction above to get started.</p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
