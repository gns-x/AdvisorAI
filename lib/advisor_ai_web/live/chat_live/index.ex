defmodule AdvisorAiWeb.ChatLive.Index do
  use AdvisorAiWeb, :live_view

  alias AdvisorAi.Chat
  alias AdvisorAi.AI.Agent

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    conversations = Chat.list_user_conversations(user.id)

    # Get or create a current conversation
    {:ok, current_conversation} = Chat.get_or_create_current_conversation(user.id)

    messages =
      if current_conversation do
        Chat.get_conversation_with_messages!(current_conversation.id, user.id).messages
      else
        []
      end

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, current_conversation)
      |> assign(:new_message, "")
      |> assign(:loading, false)
      |> assign(:view_mode, "chat")
      |> assign(:context_menu_open, false)
      |> assign(:last_update, DateTime.utc_now())

    # Initialize the stream with existing messages
    socket = stream(socket, :messages, messages, reset: true)

    # Schedule periodic token check (every 5 minutes)
    if connected?(socket) do
      Process.send_after(self(), :check_token_expiration, 5 * 60 * 1000)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  # Helper to insert a system message (step log) into the chat stream
  defp insert_system_message(socket, content) do
    conversation = socket.assigns.current_conversation

    {:ok, system_message} =
      AdvisorAi.Chat.create_message(conversation.id, %{
        role: "system",
        content: content
      })

    stream_insert(socket, :messages, system_message, at: -1)
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" do
      user = socket.assigns.current_user
      conversation = socket.assigns.current_conversation

      # Create user message
      {:ok, user_message} =
        Chat.create_message(conversation.id, %{
          role: "user",
          content: message
        })

      # Add user message to stream
      socket = stream_insert(socket, :messages, user_message, at: -1)

      # Set loading state
      socket = assign(socket, :loading, true)
      IO.puts("DEBUG: Loading state set to true")

      # Process with AI agent, streaming step logs
      task =
        Task.async(fn ->
          # Example: simulate step-by-step logging (replace with real steps in production)
          send(self(), {:system_step, "Step 1: Checking HubSpot contacts..."})
          Process.sleep(500)
          send(self(), {:system_step, "Step 2: Creating new contact if not found..."})
          Process.sleep(500)
          send(self(), {:system_step, "Step 3: Adding note about the email..."})
          Process.sleep(500)
          result = Agent.process_user_message(user, conversation.id, message)
          IO.puts("DEBUG: Agent result: #{inspect(result)}")
          result
        end)

      {:noreply,
       socket
       |> assign(:new_message, "")
       |> assign(:loading, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_message", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_message, value)}
  end

  @impl true
  def handle_event("handle_keydown", %{"key" => "Enter", "shiftKey" => false}, socket) do
    if String.trim(socket.assigns.new_message) != "" do
      handle_event("send_message", %{"message" => socket.assigns.new_message}, socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("handle_keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_context_menu", _params, socket) do
    {:noreply, assign(socket, :context_menu_open, !socket.assigns.context_menu_open)}
  end

  @impl true
  def handle_event("show_chat", _params, socket) do
    {:noreply, assign(socket, :view_mode, "chat")}
  end

  @impl true
  def handle_event("show_history", _params, socket) do
    {:noreply, assign(socket, :view_mode, "history")}
  end

  @impl true
  def handle_event("quick_action", %{"action" => action}, socket) do
    message =
      case action do
        "who_kid_baseball" ->
          "Who mentioned their kid plays baseball?"
        "why_greg_sell_aapl" ->
          "Why did Greg say he wanted to sell AAPL stock?"
        "schedule_appointment_sara" ->
          "Schedule an appointment with Sara Smith"
        _ ->
          "How can you help me with my financial needs?"
      end

    # Trigger the send_message event with the quick action message
    handle_event("send_message", %{"message" => message}, socket)
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    user = socket.assigns.current_user
    {:ok, new_conversation} = Chat.create_conversation(user.id, %{title: "New Conversation"})

    {:noreply,
     socket
     |> assign(:current_conversation, new_conversation)
     |> stream(:messages, [], reset: true)
     |> assign(:conversations, [new_conversation | socket.assigns.conversations])}
  end

  @impl true
  def handle_event("continue_conversation", %{"id" => conversation_id}, socket) do
    user = socket.assigns.current_user
    conversation = Chat.get_conversation!(conversation_id, user.id)
    messages = Chat.get_conversation_with_messages!(conversation.id, user.id).messages

    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> assign(:view_mode, "chat")
     |> stream(:messages, messages, reset: true)}
  end

  @impl true
  def handle_event("select_conversation", %{"id" => conversation_id}, socket) do
    user = socket.assigns.current_user
    conversation = Chat.get_conversation!(conversation_id, user.id)
    messages = Chat.get_conversation_with_messages!(conversation.id, user.id).messages

    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> stream(:messages, messages, reset: true)}
  end

  @impl true
  def handle_event("delete_conversation", %{"id" => conversation_id}, socket) do
    user = socket.assigns.current_user

    # Get the conversation to delete
    conversation = Chat.get_conversation!(conversation_id, user.id)

    # Check if this is the current conversation
    is_current =
      socket.assigns.current_conversation &&
        socket.assigns.current_conversation.id == conversation_id

    case Chat.delete_conversation(conversation) do
      {:ok, _} ->
        # Remove from conversations list
        updated_conversations =
          Enum.reject(socket.assigns.conversations, fn conv -> conv.id == conversation_id end)

        socket = assign(socket, :conversations, updated_conversations)

        # If this was the current conversation, create a new one
        if is_current do
          {:ok, new_conversation} =
            Chat.create_conversation(user.id, %{title: "New Conversation"})

          {:noreply,
           socket
           |> assign(:current_conversation, new_conversation)
           |> stream(:messages, [], reset: true)}
        else
          {:noreply, socket}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_all_conversations", _params, socket) do
    user = socket.assigns.current_user

    # Delete all conversations for the user
    Enum.each(socket.assigns.conversations, fn conversation ->
      Chat.delete_conversation(conversation)
    end)

    # Create a new conversation
    {:ok, new_conversation} = Chat.create_conversation(user.id, %{title: "New Conversation"})

    {:noreply,
     socket
     |> assign(:conversations, [])
     |> assign(:current_conversation, new_conversation)
     |> stream(:messages, [], reset: true)
     |> put_flash(:info, "All conversations have been cleared.")}
  end

  @impl true
  def handle_event("typing_start", _params, socket) do
    # Broadcast typing status to other users in the same conversation
    # This would typically be implemented with PubSub
    {:noreply, socket}
  end

  @impl true
  def handle_event("typing_stop", _params, socket) do
    # Stop typing indicator
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "add_reaction",
        %{"message_id" => _message_id, "reaction" => _reaction},
        socket
      ) do
    # Store reaction in database (you would implement this)
    # For now, just acknowledge the event
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_context", %{"context" => context}, socket) do
    # Update context setting
    {:noreply, assign(socket, :current_context, context)}
  end

  @impl true
  def handle_info({ref, {:ok, assistant_message}}, socket) do
    IO.puts("DEBUG: LiveView received agent result: #{inspect(assistant_message)}")
    Process.demonitor(ref, [:flush])

    # Add assistant message to stream
    socket = stream_insert(socket, :messages, assistant_message, at: -1)

    # Update conversation title if it's the first message
    messages_count = length(socket.assigns.streams.messages.inserts)

    if messages_count == 1 do
      title = generate_conversation_title(assistant_message.content)
      Chat.update_conversation_title(socket.assigns.current_conversation, title)
    end

    socket = assign(socket, :loading, false)
    IO.puts("DEBUG: Loading state set to false (success)")
    IO.puts("DEBUG: Socket assigns after update: #{inspect(socket.assigns.loading)}")

    # Force a re-render by updating a timestamp
    socket = assign(socket, :last_update, DateTime.utc_now())

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, socket) do
    IO.puts("DEBUG: LiveView received agent error: #{inspect(reason)}")
    Process.demonitor(ref, [:flush])

    # Create a more helpful error message for OpenRouter issues
    error_content =
      if String.contains?(reason, "OPENROUTER_API_KEY") do
        """
        I'm sorry, but OpenRouter is not configured. To use my AI capabilities, you need to:

        1. Get a free API key from https://openrouter.ai/
        2. Edit .env file and replace 'your_api_key_here' with your actual key
        3. Restart the application

        For now, I can still help you with basic tasks, but I won't be able to use AI-powered features.
        """
      else
        "I apologize, but I encountered an error: #{reason}"
      end

    # Create error message
    {:ok, error_message} =
      Chat.create_message(socket.assigns.current_conversation.id, %{
        role: "assistant",
        content: error_content
      })

    socket = stream_insert(socket, :messages, error_message, at: -1)

    socket = assign(socket, :loading, false)
    IO.puts("DEBUG: Loading state set to false (error)")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:system_step, step_content}, socket) do
    socket = insert_system_message(socket, step_content)
    {:noreply, socket}
  end

  defp generate_conversation_title(content) do
    # Extract first few words as title
    content
    |> String.split(" ")
    |> Enum.take(5)
    |> Enum.join(" ")
    |> String.slice(0, 50)
  end

  @impl true
  def handle_info(:check_token_expiration, socket) do
    user = socket.assigns.current_user

    if has_expired_oauth_tokens?(user) do
      # Clear user tokens
      clear_user_oauth_tokens(user)

      # Redirect to login with message
      socket =
        socket
        |> put_flash(:error, "Your session has expired. Please log in again.")
        |> redirect(to: ~p"/")

      {:noreply, socket}
    else
      # Schedule next check (every 5 minutes)
      Process.send_after(self(), :check_token_expiration, 5 * 60 * 1000)
      {:noreply, socket}
    end
  end

  defp has_expired_oauth_tokens?(user) do
    # Check Google token expiration
    google_expired =
      case user.google_token_expires_at do
        nil -> false
        expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
      end

    # Check HubSpot token expiration
    hubspot_expired =
      case user.hubspot_token_expires_at do
        nil -> false
        expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
      end

    # If user has any OAuth tokens and they're expired, return true
    (user.google_access_token && google_expired) ||
      (user.hubspot_access_token && hubspot_expired)
  end

  defp clear_user_oauth_tokens(user) do
    # Clear OAuth tokens from user record
    user_params = %{
      google_access_token: nil,
      google_refresh_token: nil,
      google_token_expires_at: nil,
      google_scopes: [],
      hubspot_access_token: nil,
      hubspot_refresh_token: nil,
      hubspot_token_expires_at: nil
    }

    AdvisorAi.Accounts.update_user(user, user_params)
  end
end
