defmodule AdvisorAiWeb.ChatLive.Index do
  use AdvisorAiWeb, :live_view

  alias AdvisorAi.Chat
  alias AdvisorAi.Chat.Message

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
     |> assign(:messages, messages)
     |> assign(:new_message, "")
     |> assign(:loading, false)}
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
      {:ok, _user_message} = Chat.create_message(conversation.id, %{
        role: "user",
        content: message
      })

      # For now, just echo back - we'll add AI later
      {:ok, _assistant_message} = Chat.create_message(conversation.id, %{
        role: "assistant",
        content: "I received your message: #{message}. AI integration coming soon!"
      })

      # Reload messages
      updated_conversation = Chat.get_conversation_with_messages!(conversation.id, user.id)

      {:noreply,
       socket
       |> assign(:messages, updated_conversation.messages)
       |> assign(:new_message, "")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_message", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_message, value)}
  end
end
