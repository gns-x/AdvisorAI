# Gmail Webhook Setup Guide

## Overview
To enable automatic email processing with HubSpot contact creation, you need to set up Gmail to send webhook notifications when new emails arrive.

## Option 1: Gmail API Push Notifications (Recommended)

### Step 1: Enable Gmail API
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Enable the Gmail API if not already enabled

### Step 2: Set up OAuth 2.0
1. Go to "APIs & Services" > "Credentials"
2. Create or configure OAuth 2.0 Client ID
3. Add your domain to authorized redirect URIs

### Step 3: Configure Push Notifications
1. Use the Gmail API to set up push notifications
2. Set the webhook URL to: `https://your-domain.com/api/webhooks/gmail`
3. Configure the topic for new email notifications

### Step 4: Test the Setup
Use the test endpoint to verify everything works:
```bash
curl -X POST http://localhost:4000/api/test/email-automation \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "your-email@gmail.com",
    "sender_email": "test@example.com", 
    "subject": "Test Email",
    "body": "This is a test email body"
  }'
```

## Option 2: Manual Testing (Current Setup)

For now, you can test the automation manually using the test endpoint:

### Test with a new contact:
```bash
curl -X POST http://localhost:4000/api/test/email-automation \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "hahadiou@gmail.com",
    "sender_email": "newclient@company.com",
    "subject": "Business Inquiry",
    "body": "Hi, I would like to discuss a potential partnership."
  }'
```

### Test with existing contact:
```bash
curl -X POST http://localhost:4000/api/test/email-automation \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "hahadiou@gmail.com",
    "sender_email": "newcontact@testcompany.com",
    "subject": "Follow up",
    "body": "Thanks for the information."
  }'
```

## Current Status
✅ **Automation Logic**: Working  
✅ **HubSpot Integration**: Working  
✅ **Contact Creation**: Working  
✅ **Test Endpoint**: Working  
⏳ **Gmail Webhook**: Needs setup

## Next Steps
1. Set up Gmail API push notifications
2. Configure webhook URL in Gmail
3. Test with real emails
4. Monitor automation logs

## Troubleshooting
- Check application logs for webhook processing
- Verify HubSpot OAuth tokens are valid
- Ensure email instructions are active in Settings > Instructions 