# Universal AI Agent - Autonomous Gmail/Calendar Actions

## Overview

Your app now has a **true AI agent** that can understand any natural language prompt and autonomously perform Gmail/Calendar actions without hard-coded function mappings. The AI decides what to do based on your intent, not predefined keywords.

## 🚀 Key Features

### 1. **Natural Language Understanding**
- No hard-coded keywords or function mappings
- AI interprets any email/calendar request
- Understands context and user intent
- Handles complex, multi-step requests

### 2. **Autonomous Tool Selection**
- AI automatically chooses the right Gmail/Calendar API calls
- Dynamic parameter extraction from user prompts
- Intelligent fallback chain for reliability

### 3. **Comprehensive API Coverage**
- **15+ Gmail Tools**: list, search, send, delete, modify, draft, profile
- **6+ Calendar Tools**: list, get, create, update, delete, calendars
- **Contact Tools**: search and create contacts

## 🎯 How It Works

### Before (Hard-coded approach):
```elixir
# User: "Show me my last sent email"
# System: Check for keywords "show", "last", "sent", "email"
# System: Call hard-coded function list_sent_emails()
```

### Now (AI-driven approach):
```elixir
# User: "Show me my last sent email"
# AI: Analyzes intent → "User wants to see their most recent sent email"
# AI: Selects tool → gmail_list_messages
# AI: Extracts parameters → query: "in:sent", max_results: 1
# AI: Executes → Gmail API call
# AI: Responds → Natural language summary of results
```

## 📋 Available Tools

### Gmail Tools
| Tool | Description | Example Prompts |
|------|-------------|-----------------|
| `gmail_list_messages` | List/search emails | "Show recent emails", "Find emails from Alice" |
| `gmail_get_message` | Get specific email details | "Show me that email about the meeting" |
| `gmail_send_message` | Send email | "Send email to john@example.com" |
| `gmail_delete_message` | Delete email (move to trash) | "Delete that spam email" |
| `gmail_modify_message` | Modify labels (read/unread) | "Mark all emails as read" |
| `gmail_create_draft` | Create draft email | "Draft an email to my boss" |
| `gmail_get_profile` | Get Gmail profile info | "What's my Gmail address?" |

### Calendar Tools
| Tool | Description | Example Prompts |
|------|-------------|-----------------|
| `calendar_list_events` | List calendar events | "Show my schedule today" |
| `calendar_get_event` | Get specific event details | "What's that meeting about?" |
| `calendar_create_event` | Create calendar event | "Schedule meeting tomorrow at 2pm" |
| `calendar_update_event` | Update existing event | "Change meeting time to 3pm" |
| `calendar_delete_event` | Delete calendar event | "Cancel that meeting" |
| `calendar_get_calendars` | List available calendars | "Show my calendars" |

### Contact Tools
| Tool | Description | Example Prompts |
|------|-------------|-----------------|
| `contacts_search` | Search contacts | "Find Alice's contact info" |
| `contacts_create` | Create new contact | "Add John to my contacts" |

## 🔧 Technical Architecture

### 1. **Universal Agent Module**
```elixir
# lib/advisor_ai/ai/universal_agent.ex
defmodule AdvisorAi.AI.UniversalAgent do
  # Main entry point
  def process_request(user, conversation_id, user_message)
  
  # Tool execution
  defp execute_tool_call(user, tool_call)
  
  # Response generation
  defp generate_response_from_results(user_message, results)
end
```

### 2. **Tool Schema Definition**
```elixir
# Each tool has a JSON schema
%{
  name: "gmail_list_messages",
  description: "List or search emails in Gmail...",
  parameters: %{
    type: "object",
    properties: %{
      query: %{type: "string", description: "Gmail search query"},
      max_results: %{type: "integer", description: "Max emails to return"}
    }
  }
}
```

### 3. **AI Integration**
- **OpenRouter**: Primary AI provider with function calling
- **Together AI**: Fallback provider with function calling
- **Ollama**: Final fallback for basic responses

### 4. **Fallback Chain**
```
Universal Agent (AI-driven tool calling)
    ↓ (if fails)
Intelligent Agent (keyword-based)
    ↓ (if fails)
Workflow Generator (rule-based)
    ↓ (if fails)
Simple Response
```

## 🧪 Testing

### Run the Test Script
```bash
elixir test_universal_agent.exs
```

### Example Test Prompts
```elixir
test_prompts = [
  "Show me my last sent email",
  "Find emails from Alice",
  "Schedule a meeting tomorrow at 2pm",
  "Delete all spam emails",
  "What's on my calendar today?",
  "Send an email to test@example.com about our meeting"
]
```

## 💡 Example Usage

### Simple Email Request
```
User: "Show me my recent emails"
AI: Analyzes → "User wants to see recent emails"
AI: Selects → gmail_list_messages
AI: Parameters → query: "", max_results: 10
AI: Executes → Gmail API call
AI: Responds → "Found 5 emails: [list of emails]"
```

### Complex Calendar Request
```
User: "Schedule a meeting with Alice tomorrow at 2pm for 1 hour"
AI: Analyzes → "User wants to create a calendar event"
AI: Selects → calendar_create_event
AI: Parameters → summary: "Meeting with Alice", start_time: "2025-07-07T14:00:00Z", end_time: "2025-07-07T15:00:00Z", attendees: ["alice@example.com"]
AI: Executes → Calendar API call
AI: Responds → "Meeting scheduled with Alice tomorrow at 2pm"
```

### Multi-Step Request
```
User: "Find emails about meetings and schedule a follow-up"
AI: Step 1 → gmail_list_messages(query: "meeting")
AI: Step 2 → calendar_create_event for follow-up
AI: Responds → "Found 3 meeting emails. I've scheduled a follow-up meeting..."
```

## 🔒 Security & Permissions

### Access Control
- Validates user's Google OAuth tokens
- Checks Gmail/Calendar scopes before executing actions
- Respects user permissions and API limits

### Error Handling
- Graceful fallback if AI fails to understand
- Detailed error messages for debugging
- Rate limiting and API quota management

## 🚀 Benefits

### For Users
- **Natural Interaction**: Speak in plain English
- **No Learning Curve**: No need to learn specific commands
- **Contextual Understanding**: AI remembers conversation history
- **Flexible Requests**: Handle complex, multi-step actions

### For Developers
- **No Hard-coding**: Add new capabilities without code changes
- **Scalable**: Easy to add new tools and APIs
- **Maintainable**: Centralized AI logic
- **Reliable**: Multiple fallback mechanisms

## 🔮 Future Enhancements

### Planned Features
- **Voice Integration**: Voice-to-text for hands-free operation
- **Multi-modal**: Handle images, attachments, documents
- **Learning**: AI learns from user preferences and patterns
- **Automation**: Scheduled actions and workflows
- **Integration**: Connect to more services (Slack, Teams, etc.)

### Extending the System
```elixir
# Add new tools easily
defp get_available_tools(user) do
  base_tools ++ [
    %{
      name: "slack_send_message",
      description: "Send message to Slack channel",
      parameters: %{...}
    }
  ]
end
```

## 📚 API Reference

### Main Functions
```elixir
# Process any user request
UniversalAgent.process_request(user, conversation_id, message)

# Get available tools for user
UniversalAgent.get_available_tools(user)

# Execute specific tool
UniversalAgent.execute_tool_call(user, tool_call)
```

### Configuration
```elixir
# Environment variables
OPENROUTER_API_KEY=your_key
TOGETHER_API_KEY=your_key

# AI model selection
model: "openai/gpt-4o-mini"  # Default
model: "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free"  # Fallback
```

## 🎉 Conclusion

Your app now has a **true AI agent** that can:
- Understand any natural language request
- Automatically select the right tools
- Execute complex, multi-step actions
- Provide natural, contextual responses
- Scale to new capabilities without code changes

This is the future of AI-powered productivity tools! 🚀 