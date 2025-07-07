# Email Automation Testing Guide

## Current Status
✅ **Automation Logic**: Working perfectly  
✅ **HubSpot Integration**: Successfully creating contacts  
✅ **Test Endpoints**: Available for manual testing  
⏳ **Gmail Integration**: Needs OAuth setup for automatic processing  

## How to Test with Real Emails

Since Gmail OAuth isn't set up yet, you can test the automation manually using the email details from real emails you receive.

### Method 1: Manual Processing (Recommended)

When you receive an email from someone not in HubSpot, use this endpoint to trigger the automation:

```bash
curl -X POST http://localhost:4000/process-email \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "hahadiou@gmail.com",
    "sender_email": "ACTUAL_SENDER_EMAIL",
    "subject": "ACTUAL_EMAIL_SUBJECT", 
    "body": "ACTUAL_EMAIL_BODY"
  }'
```

### Method 2: Test Endpoint (For Testing)

Use the test endpoint for quick testing:

```bash
curl -X POST http://localhost:4000/api/test/email-automation \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "hahadiou@gmail.com",
    "sender_email": "test@example.com",
    "subject": "Test Email",
    "body": "This is a test email body"
  }'
```

## Step-by-Step Testing Process

1. **Receive an email** from someone not in your HubSpot contacts
2. **Copy the email details**:
   - Sender email address
   - Subject line
   - Email body content
3. **Use the manual processing endpoint** with the real email data
4. **Check HubSpot** to see if the contact was created
5. **Verify the automation worked** by checking the response

## Example with Real Email

If you receive an email from `john@newcompany.com` with subject "Business Partnership" and body "Hi, I'd like to discuss a potential partnership...", use:

```bash
curl -X POST http://localhost:4000/process-email \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "hahadiou@gmail.com",
    "sender_email": "john@newcompany.com",
    "subject": "Business Partnership",
    "body": "Hi, I'\''d like to discuss a potential partnership..."
  }'
```

## Expected Results

✅ **Success Response**:
```json
{
  "status": "success",
  "message": "Email automation triggered successfully",
  "result": "Created new contact john@newcompany.com with email note",
  "user": "hahadiou@gmail.com",
  "sender": "john@newcompany.com",
  "subject": "Business Partnership"
}
```

✅ **HubSpot Result**: New contact created with email note

## Troubleshooting

- **User not found**: Make sure you're using the correct email address
- **HubSpot error**: Check that HubSpot OAuth is still valid
- **No automation triggered**: Verify your instructions are active in Settings > Instructions

## Next Steps

1. **Test with real emails** using the manual processing endpoint
2. **Set up Gmail OAuth** for automatic processing (optional)
3. **Monitor results** in HubSpot after each test

## Gmail OAuth Setup (Optional)

To enable automatic email processing, you'll need to:
1. Set up Gmail OAuth in your Google Cloud Console
2. Configure the email monitoring worker
3. Set up proper webhook endpoints

For now, the manual processing method works perfectly for testing and real use cases! 