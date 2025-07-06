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
    <div class="min-h-screen bg-gray-50">
      <!-- Main Content -->
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="space-y-8">
          
    <!-- Page Header -->
          <div class="text-center">
            <h2 class="text-3xl font-bold text-gray-900 mb-4">Ongoing Instructions</h2>
            <p class="text-lg text-gray-600 max-w-2xl mx-auto">
              Set up instructions for your AI assistant to follow automatically. These will be applied when relevant events occur.
            </p>
          </div>
          
    <!-- Add New Instruction -->
          <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Add New Instruction</h3>

            <form phx-submit="save_instruction" class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Instruction
                </label>
                <textarea
                  name="instruction"
                  rows="3"
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
                  placeholder="e.g., When someone emails me that is not in HubSpot, please create a contact in HubSpot with a note about the email."
                  required
                ></textarea>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  Triggers
                </label>
                <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                  <label class="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      name="triggers[]"
                      value="email_received"
                      class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span class="text-sm text-gray-700">Email Received</span>
                  </label>
                  <label class="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      name="triggers[]"
                      value="calendar_event"
                      class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span class="text-sm text-gray-700">Calendar Event</span>
                  </label>
                  <label class="flex items-center space-x-2">
                    <input
                      type="checkbox"
                      name="triggers[]"
                      value="hubspot_contact"
                      class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span class="text-sm text-gray-700">HubSpot Contact</span>
                  </label>
                </div>
              </div>

              <div class="flex items-center space-x-2">
                <input
                  type="checkbox"
                  name="active"
                  value="true"
                  checked
                  class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                />
                <span class="text-sm text-gray-700">Active</span>
              </div>

              <button
                type="submit"
                class="w-full px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium"
              >
                Save Instruction
              </button>
            </form>
          </div>
          
    <!-- Existing Instructions -->
          <div class="bg-white rounded-xl shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Your Instructions</h3>

            <div class="space-y-4">
              <%= for instruction <- @instructions do %>
                <div class="border border-gray-200 rounded-lg p-4">
                  <div class="flex items-start justify-between">
                    <div class="flex-1">
                      <div class="flex items-center space-x-2 mb-2">
                        <span class={"px-2 py-1 text-xs font-medium rounded-full #{if instruction.is_active, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                          {if instruction.is_active, do: "Active", else: "Inactive"}
                        </span>
                        <div class="flex space-x-1">
                          <%= if instruction.trigger_type do %>
                            <span class="px-2 py-1 text-xs bg-blue-100 text-blue-800 rounded-full">
                              {String.replace(instruction.trigger_type, "_", " ")
                              |> String.capitalize()}
                            </span>
                          <% end %>
                        </div>
                      </div>
                      <p class="text-gray-900">{instruction.instruction}</p>
                    </div>

                    <div class="flex items-center space-x-2 ml-4">
                      <button
                        phx-click="toggle_instruction"
                        phx-value-id={instruction.id}
                        class={"px-3 py-1 text-sm rounded-md transition-colors #{if instruction.is_active, do: "bg-gray-100 text-gray-700 hover:bg-gray-200", else: "bg-green-100 text-green-700 hover:bg-green-200"}"}
                      >
                        {if instruction.is_active, do: "Disable", else: "Enable"}
                      </button>
                      <button
                        phx-click="delete_instruction"
                        phx-value-id={instruction.id}
                        class="px-3 py-1 text-sm bg-red-100 text-red-700 rounded-md hover:bg-red-200 transition-colors"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @instructions == [] do %>
                <div class="text-center py-8">
                  <div class="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
                    <svg
                      class="w-8 h-8 text-gray-400"
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
                  <h3 class="text-lg font-medium text-gray-900 mb-2">No instructions yet</h3>
                  <p class="text-gray-500">Create your first instruction to get started.</p>
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
