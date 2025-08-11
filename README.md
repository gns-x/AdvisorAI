# <img src="https://raw.githubusercontent.com/gns-x/AdvisorAI/refs/heads/main/assets/static/logo.svg" alt="AdvisorAI Logo" width="48" style="vertical-align:middle;"> AdvisorAI

[![Live Demo](https://img.shields.io/badge/Live%20Demo-Online-brightgreen?style=for-the-badge)](https://advisor-ai.onrender.com)
[![Repo](https://img.shields.io/badge/GitHub-Repo-blue?style=for-the-badge)](https://github.com/gns-x/AdvisorAI)

---

> **AdvisorAI** is a next-generation AI assistant platform for financial advisors that seamlessly integrates Gmail, Google Calendar, and HubSpot CRM into a single, intelligent chat interface. It uses advanced AI to automate workflows, manage client relationships, and boost productivity with real-time automation and proactive intelligence.

---

## 🎯 What AdvisorAI Actually Does

AdvisorAI is not just another chat interface—it's a comprehensive AI-powered workflow automation system that transforms how financial advisors manage their practice. Here's what it actually does:

### 🤖 **Intelligent AI Agent with Memory**
- **Universal AI Agent**: Processes any natural language request and autonomously performs appropriate actions across Gmail, Calendar, and HubSpot
- **Tool Calling**: Uses AI to dynamically generate and execute API calls without hard-coded function mappings
- **Memory & Context**: Maintains conversation history, user patterns, and relevant context for intelligent decision-making
- **RAG (Retrieval-Augmented Generation)**: Uses pgvector embeddings to provide deep context from previous interactions

### 📧 **Advanced Email Management**
- **Smart Email Search**: Search emails using natural language queries with intelligent context understanding
- **Automated Email Composition**: AI generates professional emails based on context and templates
- **Email Threading**: Understands conversation history and maintains context across email threads
- **Proactive Email Actions**: Automatically categorize, prioritize, and suggest actions for incoming emails

### 📅 **Intelligent Calendar Management**
- **Smart Scheduling**: Automatically find available times, handle conflicts, and suggest optimal meeting slots
- **Appointment Workflows**: Complete appointment scheduling workflows including contact lookup, availability checking, and confirmation emails
- **Calendar Intelligence**: Analyzes patterns, suggests buffer times, and handles travel time considerations
- **Event Automation**: Automatically send meeting invites, reminders, and follow-up communications

### 👥 **HubSpot CRM Integration**
- **Contact Management**: Create, search, and manage contacts with intelligent data extraction
- **Relationship Intelligence**: Track client interactions, preferences, and relationship history
- **Automated Contact Creation**: Automatically create contacts from emails with intelligent data parsing
- **Note Management**: Add contextual notes and track client interactions automatically

### 🔄 **Proactive Automation & Instructions**
- **Ongoing Instructions**: Create persistent automation rules that execute automatically based on triggers
- **Smart Trigger Matching**: Only execute instructions that 100% match user requests (case-insensitive exact match)
- **Cross-Platform Workflows**: Automate complex workflows that span multiple platforms
- **Proactive Suggestions**: AI suggests next logical steps and automation opportunities

### 🧠 **Advanced AI Capabilities**
- **Multi-Model Support**: Uses OpenRouter, Together AI, and Ollama for robust AI processing
- **Intelligent Fallbacks**: Gracefully handles API failures with alternative approaches
- **Context-Aware Processing**: Considers user patterns, time of day, and relationship context
- **Edge Case Handling**: Intelligently handles ambiguous requests and missing data

---

## 🏗️ System Architecture

```mermaid
graph TB
    subgraph "Frontend Layer"
        UI[Phoenix LiveView UI]
        Chat[Real-time Chat Interface]
        Settings[Settings & Integrations]
    end
    
    subgraph "AI Layer"
        UA[Universal Agent]
        IA[Intelligent Agent]
        WG[Workflow Generator]
        AI[AI Clients<br/>OpenRouter/Together/Ollama]
    end
    
    subgraph "Integration Layer"
        Gmail[Gmail API]
        Calendar[Google Calendar API]
        HubSpot[HubSpot CRM API]
        OAuth[Google OAuth]
    end
    
    subgraph "Data Layer"
        PG[(PostgreSQL + pgvector)]
        Embeddings[Vector Embeddings]
        Instructions[Agent Instructions]
        ChatHistory[Conversation History]
    end
    
    subgraph "Background Processing"
        Workers[Background Workers]
        Tasks[Agent Tasks]
        Monitoring[Email Monitoring]
    end
    
    UI --> UA
    Chat --> UA
    UA --> AI
    IA --> AI
    WG --> AI
    
    UA --> Gmail
    UA --> Calendar
    UA --> HubSpot
    UA --> OAuth
    
    UA --> PG
    AI --> Embeddings
    UA --> Instructions
    UA --> ChatHistory
    
    UA --> Workers
    Workers --> Tasks
    Workers --> Monitoring
```

---

## 🔧 Core Components

### **Universal Agent** (`lib/advisor_ai/ai/universal_agent.ex`)
The heart of the system that processes any user request and autonomously performs appropriate actions:
- **Direct Action Processing**: Handles clear requests (like "create contact John with email john@example.com")
- **Tool Calling**: Dynamically generates and executes API calls based on natural language
- **Intelligent Fallbacks**: Tries alternative approaches when primary methods fail
- **Context Building**: Maintains comprehensive context for intelligent decision-making

### **Intelligent Agent** (`lib/advisor_ai/ai/intelligent_agent.ex`)
Provides advanced AI reasoning and workflow generation:
- **Multi-Model Support**: Uses OpenRouter, Together AI, and Ollama
- **Workflow Generation**: Creates complex multi-step workflows automatically
- **Proactive Intelligence**: Anticipates needs and suggests additional actions
- **Edge Case Handling**: Intelligently handles ambiguous or incomplete requests

### **Agent Instructions** (`lib/advisor_ai/ai/agent_instruction.ex`)
Manages persistent automation rules and triggers:
- **Instruction Storage**: Stores automation rules in PostgreSQL
- **Trigger Matching**: Matches instructions to user requests with 100% accuracy
- **Conditional Logic**: Supports complex conditions and parameters
- **Active Management**: Enables/disables instructions dynamically

### **Integration Modules**
- **Gmail Integration** (`lib/advisor_ai/integrations/gmail.ex`): Email search, composition, and automation
- **Calendar Integration** (`lib/advisor_ai/integrations/calendar.ex`): Event management and scheduling
- **HubSpot Integration** (`lib/advisor_ai/integrations/hubspot.ex`): CRM contact and note management

---

## 🚀 Key Workflows

### **1. Appointment Scheduling Workflow**
```mermaid
sequenceDiagram
    participant U as User
    participant AI as AI Agent
    participant HS as HubSpot
    participant Cal as Calendar
    participant Gmail as Gmail
    
    U->>AI: "Schedule appointment with John Smith"
    AI->>HS: Search for contact "John Smith"
    HS-->>AI: Contact found with email
    AI->>Cal: Get available times for next 2 days
    Cal-->>AI: Available slots
    AI->>Gmail: Send email with available times
    Gmail-->>AI: Email sent
    AI->>U: "I've sent John available times for scheduling"
    
    Note over Gmail: When John responds
    Gmail->>AI: Email received from John
    AI->>AI: Analyze response for chosen time
    AI->>Cal: Create calendar event
    Cal-->>AI: Event created
    AI->>HS: Add note about appointment
    AI->>Gmail: Send confirmation email
```

### **2. Contact Creation & Management**
```mermaid
sequenceDiagram
    participant U as User
    participant AI as AI Agent
    participant HS as HubSpot
    participant Gmail as Gmail
    
    U->>AI: "Create new contact John Doe with email john@example.com"
    AI->>HS: Create contact with provided data
    HS-->>AI: Contact created successfully
    AI->>AI: Check for matching instructions
    AI->>Gmail: Send welcome email (if instruction exists)
    AI->>U: "Contact created: John Doe (john@example.com)"
```

### **3. Email Automation Workflow**
```mermaid
sequenceDiagram
    participant U as User
    participant AI as AI Agent
    participant HS as HubSpot
    participant Gmail as Gmail
    
    U->>AI: "When I get an email from someone not in HubSpot, create a contact"
    AI->>AI: Store as ongoing instruction
    AI->>U: "Instruction saved for email automation"
    
    Note over Gmail: New email received
    Gmail->>AI: Email from unknown sender
    AI->>HS: Check if contact exists
    HS-->>AI: Contact not found
    AI->>HS: Create new contact automatically
    AI->>HS: Add note about email interaction
    AI->>U: "Automatically created contact for new email sender"
```

---

## 🎯 Real-World Use Cases

### **Financial Advisor Daily Operations**
- **Client Onboarding**: Automatically create contacts, schedule initial meetings, and send welcome materials
- **Meeting Management**: Handle scheduling conflicts, send reminders, and track follow-ups
- **Email Organization**: Categorize client emails, track important conversations, and maintain relationship history
- **Proactive Client Care**: Monitor client interactions and suggest follow-up actions

### **Workflow Automation Examples**
- **New Client Intake**: When a new client emails, automatically create HubSpot contact, schedule consultation, and send welcome package
- **Meeting Follow-ups**: After calendar events, automatically send meeting notes and schedule follow-up calls
- **Client Communication**: Track all client interactions and suggest appropriate follow-up actions
- **Document Management**: Link emails, meetings, and notes to create comprehensive client profiles

---

## 🛠️ Technical Stack

### **Backend**
- **Elixir/Phoenix**: High-performance, fault-tolerant web framework
- **Phoenix LiveView**: Real-time, reactive user interface
- **PostgreSQL + pgvector**: Database with vector similarity search
- **Oban**: Background job processing
- **Tesla**: HTTP client for API integrations

### **AI & Machine Learning**
- **OpenRouter**: Primary AI provider with function calling
- **Together AI**: Fallback AI provider
- **Ollama**: Local AI processing option
- **pgvector**: Vector embeddings for RAG
- **Custom AI Agents**: Specialized agents for different tasks

### **Integrations**
- **Google OAuth**: Secure authentication and API access
- **Gmail API**: Email management and automation
- **Google Calendar API**: Event scheduling and management
- **HubSpot CRM API**: Contact and relationship management

### **Frontend**
- **Phoenix LiveView**: Real-time, server-rendered UI
- **Tailwind CSS**: Utility-first CSS framework
- **Alpine.js**: Lightweight JavaScript framework
- **Heroicons**: Beautiful SVG icons

---

## 🔑 Environment Variables

```bash
# AI Providers
OPENROUTER_API_KEY=your_openrouter_key
TOGETHER_API_KEY=your_together_key

# Google OAuth
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# HubSpot
HUBSPOT_CLIENT_ID=your_hubspot_client_id
HUBSPOT_CLIENT_SECRET=your_hubspot_client_secret

# Database
DATABASE_URL=postgresql://user:pass@localhost/advisor_ai

# Application
SECRET_KEY_BASE=your_secret_key_base
```

---

## 🚀 Quick Start

### Local Development

```bash
# Clone the repository
git clone https://github.com/gns-x/AdvisorAI.git
cd AdvisorAI

# Install dependencies
mix deps.get
npm install --prefix assets

# Set up environment
cp .env.example .env
# Edit .env with your API keys

# Set up database
mix ecto.setup

# Start the server
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000) to access the application.

### 🚀 Deployment on Render

This application is configured for deployment on Render with automatic PostgreSQL database setup.

#### Quick Deploy (Recommended)

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy/schema-new?schema=https://raw.githubusercontent.com/gns-x/AdvisorAI/main/render.yaml)

#### Manual Deploy Steps

1. **Connect to Render**
   - Go to [dashboard.render.com/new](https://dashboard.render.com/new)
   - Connect your GitHub repository
   - Render will automatically detect the Phoenix app

2. **Configure Environment Variables**
   In the Render dashboard, set these environment variables:
   ```bash
   MIX_ENV=prod
   PHX_HOST=your-app-name.onrender.com
   SECRET_KEY_BASE=your-secret-key-base
   GOOGLE_CLIENT_ID=your-google-client-id
   GOOGLE_CLIENT_SECRET=your-google-client-secret
   HUBSPOT_CLIENT_ID=your-hubspot-client-id
   HUBSPOT_CLIENT_SECRET=your-hubspot-client-secret
   HUBSPOT_REDIRECT_URI=https://your-app-name.onrender.com/hubspot/oauth/callback
   OPENAI_API_KEY=your-openai-api-key
   OPENROUTER_API_KEY=your-openrouter-api-key
   WEBHOOK_URL=https://your-app-name.onrender.com/webhook/gmail
   ```

3. **Deploy**
   - Render will automatically build and deploy your app
   - Your app will be available at `https://your-app-name.onrender.com`

#### Generate Secret Key Base

```bash
mix phx.gen.secret
```

#### Update OAuth Applications

After deployment, update your OAuth applications with the new domain:

**Google OAuth:**
- Go to [Google Cloud Console](https://console.cloud.google.com/)
- Update authorized redirect URIs: `https://your-app-name.onrender.com/auth/google/callback`

**HubSpot OAuth:**
- Go to [HubSpot Developer Portal](https://developers.hubspot.com/)
- Update redirect URIs: `https://your-app-name.onrender.com/hubspot/oauth/callback`

---

## 📚 Example Prompts & Capabilities

### **Email Management**
- "Search for emails from John about investment portfolio"
- "Send a follow-up email to Sarah about our meeting last week"
- "When I get emails from new clients, automatically create HubSpot contacts"

### **Calendar & Scheduling**
- "Schedule an appointment with Mike Johnson for next Tuesday at 2pm"
- "What meetings do I have today?"
- "Find available times for a 1-hour meeting with the team"

### **Contact Management**
- "Create new contact Jane Smith with email jane@example.com"
- "Search for contacts in the technology sector"
- "Add a note to John's contact about his retirement planning interest"

### **Workflow Automation**
- "When I create a calendar event, automatically send invites to attendees"
- "When someone emails me that's not in HubSpot, add them as a contact"
- "After meetings, automatically send follow-up emails with action items"

---

## 🔒 Security & Privacy

- **OAuth 2.0**: Secure authentication with Google
- **Token Management**: Secure storage and refresh of API tokens
- **Data Encryption**: All sensitive data encrypted at rest
- **Privacy-First**: No data sharing with third parties
- **GDPR Compliant**: User data control and deletion capabilities

---

## 📈 Performance & Scalability

- **Real-time Updates**: LiveView provides instant UI updates
- **Background Processing**: Oban handles heavy tasks asynchronously
- **Vector Search**: pgvector enables fast similarity searches
- **Caching**: Intelligent caching of frequently accessed data
- **Horizontal Scaling**: Designed for multi-instance deployment

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**AdvisorAI: The intelligent, secure, and elegant AI assistant for financial professionals.**

Transform your financial advisory practice with AI-powered automation, intelligent workflows, and proactive client management.
