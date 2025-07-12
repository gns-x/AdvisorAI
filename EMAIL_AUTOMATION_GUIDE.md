# Email Automation System Guide

## Overview

The AI assistant now includes a comprehensive email automation system that can:

1. **Monitor Gmail** for new emails every 30 seconds
2. **Detect meeting inquiries** automatically
3. **Look up calendar events** for clients asking about meetings
4. **Send automated responses** directly to clients
5. **Handle new contacts** and send welcome emails
6. **Work in deployment** without requiring local setup

## How It Works

### Email Monitoring
- The `EmailMonitorWorker` runs every 30 seconds in the background
- It checks for new emails from all users with connected Gmail accounts
- Automatically triggers appropriate automation based on email content

### Meeting Inquiry Detection
The system detects meeting inquiries by looking for keywords like:
- "meeting", "appointment", "call"
- "when", "schedule", "upcoming"
- "next", "our meeting", "the meeting"
- "what time", "when is", "do we have"

### Automated Response Process
1. **Email Received** → System detects meeting inquiry
2. **Calendar Lookup** → Searches for meetings with the sender
3. **Response Generation** → Creates appropriate response
4. **Email Sent** → Sends response directly to the client

## Testing the System

### Method 1: Send Real Email
Send an email to `hahadiou@gmail.com` with content like:
```
Subject: When is our upcoming meeting?
Body: Hi, I was wondering when our next meeting is scheduled. Could you let me know the details?
```

### Method 2: Use Test Endpoint
Use the test script provided:
```bash
./test_meeting_inquiry.sh
```

Or manually call the API:
```bash
curl -X POST "https://advisorai-production.up.railway.app/api/test/meeting-inquiry" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "hahadiou@gmail.com",
    "sender_email": "test@example.com",
    "subject": "When is our upcoming meeting?",
    "body": "Hi, I was wondering when our next meeting is scheduled."
  }'
```

### Method 3: Check App Chat
- Open the app chat interface
- Look for automation activity messages
- Check for "Meeting Inquiry" conversations

## Deployment Configuration

The system is configured to work automatically in deployment:

### Production Settings
- Email monitor runs every 30 seconds
- Checks up to 20 recent emails per user
- Automatically starts with the application
- Handles token refresh and error recovery

### Required Environment Variables
- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `GOOGLE_CLIENT_SECRET` - Google OAuth client secret
- `OPENROUTER_API_KEY` - For AI processing
- `DATABASE_URL` - Database connection
- `SECRET_KEY_BASE` - Phoenix secret key

## Troubleshooting

### No Automated Response Received
1. **Check Gmail Connection**
   - Ensure Gmail is connected in the app
   - Verify OAuth tokens are valid
   - Check if tokens need refresh

2. **Check Deployment Logs**
   - Look for "Email Monitor" log entries
   - Check for "Meeting Inquiry" activity
   - Verify no errors in the logs

3. **Test Manual Endpoint**
   - Use the test endpoint to verify functionality
   - Check if the issue is with monitoring vs. processing

### Common Issues

**Issue**: No emails being monitored
**Solution**: Check if `EmailMonitorWorker` is starting properly in deployment logs

**Issue**: Emails detected but no response sent
**Solution**: Check if Gmail send permissions are granted and tokens are valid

**Issue**: Meeting lookup not working
**Solution**: Verify Google Calendar is connected and has proper permissions

## API Endpoints

### Test Meeting Inquiry
```
POST /api/test/meeting-inquiry
{
  "user_email": "user@example.com",
  "sender_email": "client@example.com", 
  "subject": "Meeting inquiry",
  "body": "When is our meeting?"
}
```

### Process Manual Email
```
POST /api/process-email
{
  "user_email": "user@example.com",
  "sender_email": "client@example.com",
  "subject": "General inquiry",
  "body": "Hello"
}
```

## Monitoring and Logs

### Key Log Messages
- `📧 Email Monitor: Detected meeting inquiry from [email]`
- `✅ Email Monitor: Meeting lookup completed for [email]`
- `❌ Email Monitor: Meeting lookup failed: [reason]`

### Log Locations
- **Development**: Console output
- **Production**: Deployment platform logs (Railway/Render/etc.)

## Security Considerations

- All email processing happens server-side
- OAuth tokens are encrypted and stored securely
- Email content is processed but not permanently stored
- API endpoints require proper authentication

## Future Enhancements

- Webhook-based real-time email processing
- More sophisticated email content analysis
- Integration with more calendar providers
- Advanced scheduling suggestions
- Email threading and conversation tracking 