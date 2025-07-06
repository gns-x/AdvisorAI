# AdvisorAI - Financial Advisor AI Assistant

A comprehensive AI-powered financial advisor assistant built with Elixir/Phoenix, featuring advanced chat capabilities, meeting integration, and financial planning tools.

## Features

- **AI Chat Interface**: Powered by OpenRouter with multiple model support
- **Meeting Integration**: Gmail and Google Calendar integration for context-aware responses
- **RAG Pipeline**: Retrieval Augmented Generation with local embedding server
- **HubSpot Integration**: CRM integration for client management
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
   git clone <repository-url>
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
- **HubSpot OAuth**: For CRM integration

## Architecture

### Backend (Elixir/Phoenix)
- **LiveView**: Real-time chat interface
- **AI Integration**: OpenRouter API with multiple models
- **RAG Pipeline**: Local embedding server with pgvector
- **Integrations**: Gmail, Calendar, HubSpot APIs

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
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Create an issue on GitHub
- Check the documentation in `/docs`
- Review the API documentation in `/docs/api`
