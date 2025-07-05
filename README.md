# AdvisorAI - AI-Powered Financial Advisor Assistant

A comprehensive AI agent for financial advisors that integrates with Gmail, Google Calendar, and HubSpot CRM. Built with Phoenix LiveView, Elixir, and OpenAI.

## Features

### 🤖 AI Agent Capabilities
- **RAG (Retrieval Augmented Generation)**: Search through emails and CRM data using vector embeddings
- **Tool Calling**: Execute actions like sending emails, scheduling meetings, and updating CRM
- **Task Memory**: Remember ongoing tasks and follow up appropriately
- **Proactive Behavior**: Automatically respond to triggers from integrations

### 🔗 Integrations
- **Gmail**: Read and send emails, search through email history
- **Google Calendar**: Schedule appointments, check availability, manage events
- **HubSpot CRM**: Create contacts, add notes, search client information

### 💬 Chat Interface
- Modern, responsive design similar to ChatGPT
- Real-time messaging with LiveView
- Conversation management
- Tool usage indicators

## Prerequisites

- Elixir 1.14+
- Erlang/OTP 25+
- PostgreSQL 12+
- Node.js 18+ (for assets)

## Setup

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd advisor_ai
mix deps.get
cd assets && npm install && cd ..
```

### 2. Database Setup

```bash
# Create and migrate database
mix ecto.create
mix ecto.migrate

# Optional: Seed with sample data
mix run priv/repo/seeds.exs
```

### 3. Environment Configuration

#### Required: OpenAI API Key Setup

**This is required for the AI agent to function!**

1. Get your OpenAI API key from [https://platform.openai.com/account/api-keys](https://platform.openai.com/account/api-keys)
2. Run the setup script (recommended):
```bash
./setup_openai.sh
```

Or manually set the environment variable:
```bash
export OPENAI_API_KEY="your_actual_openai_api_key_here"
```

3. To make this permanent, add it to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):
```bash
echo 'export OPENAI_API_KEY="your_actual_openai_api_key_here"' >> ~/.zshrc
source ~/.zshrc
```

#### Optional: Create a `.env` file

For development, you can create a `.env` file in the root directory:

```bash
# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_HOST=localhost
POSTGRES_DB=advisor_ai_dev

# Phoenix
SECRET_KEY_BASE=your-secret-key-base-here-replace-in-production
PORT=4000

# Google OAuth
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret

# HubSpot OAuth
HUBSPOT_CLIENT_ID=your-hubspot-client-id
HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret
HUBSPOT_REDIRECT_URI=http://localhost:4000/auth/hubspot/callback

# OpenAI (REQUIRED)
OPENAI_API_KEY=your-openai-api-key
```

### 4. OAuth Setup

#### Google OAuth
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable Gmail API and Google Calendar API
4. Create OAuth 2.0 credentials
5. Add `webshookeng@gmail.com` as a test user
6. Set redirect URI to `http://localhost:4000/auth/google/callback`

#### HubSpot OAuth
1. Go to [HubSpot Developer Portal](https://developers.hubspot.com/)
2. Create a new app
3. Configure OAuth settings
4. Set redirect URI to `http://localhost:4000/auth/hubspot/callback`

### 5. Build Assets

```bash
mix assets.deploy
```

### 6. Start the Server

```bash
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) to see the application.

## Usage

### 1. Sign In
- Click "Sign in with Google" to authenticate
- Grant permissions for Gmail and Calendar access

### 2. Connect HubSpot
- Navigate to Settings > Integrations
- Connect your HubSpot account

### 3. Start Chatting
- Ask questions about clients: "Who mentioned their kid plays baseball?"
- Schedule appointments: "Schedule an appointment with Sara Smith"
- Send emails: "Send a follow-up email to John about the investment proposal"
- Manage CRM: "Create a contact for the new client from yesterday's email"

### 4. Set Up Ongoing Instructions
- "When someone emails me that is not in HubSpot, please create a contact"
- "When I create a contact in HubSpot, send them a welcome email"
- "When I add an event in my calendar, send an email to attendees"

## Architecture

### Core Components

- **AI Agent** (`lib/advisor_ai/ai/agent.ex`): Main AI processing logic
- **Vector Embeddings** (`lib/advisor_ai/ai/vector_embedding.ex`): RAG functionality
- **Integrations**: Gmail, Calendar, and HubSpot modules
- **Chat System**: LiveView-based real-time chat interface
- **Task Management**: Background job processing with Oban

### Database Schema

- **Users**: User accounts and authentication
- **Accounts**: OAuth provider connections
- **Conversations**: Chat conversations
- **Messages**: Individual chat messages
- **Vector Embeddings**: RAG data storage
- **Agent Tasks**: Background task management
- **Agent Instructions**: Ongoing instruction storage

## Development

### Running Tests

```bash
mix test
```

### Code Quality

```bash
mix credo
mix dialyzer
```

### Database Reset

```bash
mix ecto.reset
```

## Deployment

### Environment Variables

Ensure all required environment variables are set in production:

- Database credentials
- OAuth client secrets
- OpenAI API key
- Phoenix secret key base

### Database Setup

```bash
# Run migrations
mix ecto.migrate

# Optional: seed data
mix run priv/repo/seeds.exs
```

### Assets

```bash
mix assets.deploy
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For support, please open an issue in the GitHub repository or contact the development team.
