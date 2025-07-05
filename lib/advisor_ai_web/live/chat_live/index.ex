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

    messages = if current_conversation do
      Chat.get_conversation_with_messages!(current_conversation.id, user.id).messages
    else
      []
    end

    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:conversations, conversations)
     |> assign(:current_conversation, current_conversation)
     |> assign(:new_message, "")
     |> assign(:loading, false)
     |> stream(:messages, messages)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) != "" do
      user = socket.assigns.current_user
      conversation = socket.assigns.current_conversation

      # Create user message
      {:ok, user_message} = Chat.create_message(conversation.id, %{
        role: "user",
        content: message
      })

      # Add user message to stream
      socket = stream_insert(socket, :messages, user_message, at: -1)

      # Set loading state
      socket = assign(socket, :loading, true)

      # Process with AI agent
      Task.async(fn ->
        Agent.process_user_message(user, conversation.id, message)
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
  def handle_info({ref, {:ok, assistant_message}}, socket) do
    Process.demonitor(ref, [:flush])

    # Add assistant message to stream
    socket = stream_insert(socket, :messages, assistant_message, at: -1)

    # Update conversation title if it's the first message
    messages_count = length(socket.assigns.streams.messages.inserts)
    if messages_count == 1 do
      title = generate_conversation_title(assistant_message.content)
      Chat.update_conversation_title(socket.assigns.current_conversation, title)
    end

    {:noreply, assign(socket, :loading, false)}
  end

  @impl true
  def handle_info({ref, {:error, reason}}, socket) do
    Process.demonitor(ref, [:flush])

    # Create a more helpful error message for Ollama issues
    error_content = if String.contains?(reason, "Ollama is not running") do
      """
      I'm sorry, but Ollama is not running. To use my AI capabilities, you need to:

      1. Start Ollama: `brew services start ollama`
      2. Make sure the model is downloaded: `ollama pull llama3.2:3b`
      3. Restart the application

      For now, I can still help you with basic tasks, but I won't be able to use AI-powered features.
      """
    else
      "I apologize, but I encountered an error: #{reason}"
    end

    # Create error message
    {:ok, error_message} = Chat.create_message(socket.assigns.current_conversation.id, %{
      role: "assistant",
      content: error_content
    })

    socket = stream_insert(socket, :messages, error_message, at: -1)

    {:noreply, assign(socket, :loading, false)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, socket) do
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
end
