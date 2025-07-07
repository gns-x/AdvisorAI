# AdvisorAI - Financial Advisor AI Assistant

A comprehensive AI-powered financial advisor assistant built with Elixir/Phoenix, featuring advanced chat capabilities, Gmail/Calendar integration, and intelligent automation.

## 🚀 **LIVE DEMO**
**App URL**: https://advisor-ai.onrender.com  
**Repository**: https://github.com/your-username/advisor-ai

## ✅ **Challenge Requirements Met**

This app fully meets all the requirements from the $3,000 challenge:

### **Core Features Implemented:**
- ✅ **Google OAuth Login** with email read/write and calendar read/write permissions
- ✅ **ChatGPT-like Interface** with modern, responsive design
- ✅ **Gmail Integration** for reading, searching, and sending emails
- ✅ **Google Calendar Integration** for event management and scheduling
- ✅ **RAG Pipeline** using pgvector for intelligent email context
- ✅ **Universal AI Agent** that interprets natural language and performs actions
- ✅ **Tool Calling System** for flexible Gmail and Calendar operations
- ✅ **Task Memory** with database storage for ongoing workflows
- ✅ **Proactive Agent** that handles ongoing instructions and triggers

### **Example Scenarios Working:**
- ✅ "Who mentioned their kid plays baseball?" - Email search with RAG
- ✅ "Why did greg say he wanted to sell AAPL stock" - Email context analysis
- ✅ "Schedule an appointment with Sara Smith" - Multi-step workflow
- ✅ "When is my next meeting with Sara Smith?" - Calendar lookup
- ✅ Proactive email responses and calendar event creation
- ✅ Intelligent contact management via HubSpot CRM

## Features

- **AI Chat Interface**: Powered by OpenRouter with multiple model support
- **Gmail Integration**: Full email reading, searching, and sending capabilities
- **Calendar Integration**: Event creation, management, and availability checking
- **RAG Pipeline**: Retrieval Augmented Generation with local embedding server
- **Universal Agent**: AI agent that can interpret natural language and perform actions
- **Real-time Updates**: LiveView-powered real-time chat experience
- **Professional UI**: Modern, responsive design with advanced interactions

## UI Enhancement & Design System

### Recent UI Enhancements (Latest Update)

The chat interface has been completely redesigned with a professional, modern design system that includes:

#### 🎨 **Design System Implementation**
- **Unified Color Palette**: Consistent primary colors, grays, and semantic colors
- **Typography System**: Display, title, heading, body, and caption text styles
- **Spacing System**: Standardized spacing variables (xs, sm, md, lg, xl, 2xl)
- **Component Library**: Reusable components with consistent styling

#### 💬 **Enhanced Chat Interface**
- **Context Indicator**: Shows current context setting with timestamp
- **Message Styling**: 
  - User messages: Blue bubble with rounded corners
  - Bot messages: Clean, readable text with proper line height
  - System messages: Subtle gray styling
- **Message Reactions**: Interactive reaction buttons (👍 👎 💡) with hover effects
- **Smart Reply Suggestions**: Quick action buttons for common tasks
- **Auto-resize Textarea**: Dynamic input that grows with content

#### 🎯 **Interactive Features**
- **Voice Recording**: Built-in microphone support with visual feedback
- **Typing Indicators**: Real-time typing status with smooth animations
- **Context Menu**: Dropdown for selecting meeting context
- **Enhanced Input Controls**: 
  - Attachment button
  - Context selector
  - Voice recorder
  - Link/paperclip button
  - Microphone button
  - Send button with proper states

#### 📱 **Mobile Optimization**
- **Responsive Design**: Optimized for all screen sizes
- **Touch-friendly**: Proper touch targets and gestures
- **Safe Area Support**: Respects device safe areas
- **Mobile-specific Styling**: Adjusted spacing and sizing for mobile

#### ♿ **Accessibility Features**
- **Focus Management**: Proper focus indicators and keyboard navigation
- **Screen Reader Support**: Semantic HTML and ARIA labels
- **High Contrast Mode**: Support for high contrast preferences
- **Reduced Motion**: Respects user's motion preferences

#### 🎭 **Advanced Animations**
- **Smooth Transitions**: CSS transitions for all interactive elements
- **Loading Animations**: Typing indicators and loading states
- **Hover Effects**: Subtle animations on hover
- **Voice Recording**: Pulsing animation during recording

### Component Architecture

#### Meeting Card Component
```elixir
<.meeting_card
  date="May 13, 2025"
  time_range="10:00 AM - 11:00 AM"
  title="Client Portfolio Review"
  attendees={[
    %{name: "John Doe", avatar: "/images/avatar1.jpg"},
    %{name: "Jane Smith", avatar: "/images/avatar2.jpg"}
  ]}
/>
```

#### JavaScript Hooks
- **AutoResize**: Automatically resizes textarea based on content
- **VoiceRecorder**: Handles voice recording with MediaRecorder API
- **MessageReactions**: Manages message reaction interactions
- **SmartReplies**: Handles quick action button clicks
- **TypingIndicator**: Manages typing status and timeouts

### CSS Architecture

The design system uses CSS custom properties for consistency:

```css
:root {
  /* Primary Colors */
  --primary-50: #EFF6FF;
  --primary-500: #3B82F6;
  
  /* Grays */
  --gray-50: #F9FAFB;
  --gray-900: #111827;
  
  /* Spacing */
  --space-xs: 0.5rem;
  --space-lg: 1.5rem;
}
```

### LiveView Integration

All UI enhancements are fully integrated with Phoenix LiveView:
- **Real-time Updates**: Messages appear instantly
- **State Management**: Proper loading states and error handling
- **Event Handling**: Comprehensive event system for all interactions
- **Stream Management**: Efficient message streaming with proper cleanup

## Installation & Setup

### Prerequisites
- Elixir 1.15+ and Erlang/OTP 25+
- PostgreSQL 13+
- Python 3.8+ (for embedding server)
- Node.js 18+ (for assets)

### Quick Start

1. **Clone and Setup**
   ```bash
   git clone https://github.com/your-username/advisor-ai.git
   cd advisor_ai
   mix deps.get
   npm install --prefix assets
   ```

2. **Database Setup**
   ```bash
   mix ecto.setup
   ```

3. **Environment Configuration**
   ```bash
   cp .env.example .env
   # Edit .env with your API keys
   ```

4. **Start the Application**
   ```bash
   mix phx.server
   ```

5. **Start Embedding Server** (in separate terminal)
   ```bash
   python embedding_server.py
   ```

### API Keys Required
- **OpenRouter API Key**: For AI chat functionality
- **Google OAuth**: For Gmail and Calendar integration

## Architecture

### Backend (Elixir/Phoenix)
- **LiveView**: Real-time chat interface
- **AI Integration**: OpenRouter API with multiple models
- **RAG Pipeline**: Local embedding server with pgvector
- **Integrations**: Gmail, Calendar APIs

### Frontend
- **Tailwind CSS**: Utility-first styling
- **JavaScript Hooks**: Interactive features
- **Responsive Design**: Mobile-first approach

### Database
- **PostgreSQL**: Primary database
- **pgvector**: Vector similarity search
- **Migrations**: Schema management

## Development

### Running Tests
```bash
mix test
```

### Code Quality
```bash
mix format
mix credo
```

### Database Migrations
```bash
mix ecto.migrate
```

## Deployment

### Render Deployment (Recommended)
The app is configured for easy deployment on Render:

1. **Fork this repository**
2. **Connect to Render** and use the `render.yaml` configuration
3. **Set environment variables** in Render dashboard:
   - `OPENAI_API_KEY`
   - `GOOGLE_CLIENT_ID`
   - `GOOGLE_CLIENT_SECRET`

### Docker Deployment
```bash
docker-compose up -d
```

### Fly.io Deployment
```bash
fly deploy
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support, email support@advisorai.com or join our Slack channel.

---

**Built with ❤️ using Elixir, Phoenix, and AI**