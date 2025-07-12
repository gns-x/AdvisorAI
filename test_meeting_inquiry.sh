#!/bin/bash

# Test script for meeting inquiry automation
# Replace YOUR_DEPLOYMENT_URL with your actual deployment URL

DEPLOYMENT_URL="https://advisorai-production.up.railway.app"
USER_EMAIL="hahadiou@gmail.com"
SENDER_EMAIL="test@example.com"

echo "🧪 Testing Meeting Inquiry Automation"
echo "====================================="
echo "Deployment URL: $DEPLOYMENT_URL"
echo "User Email: $USER_EMAIL"
echo "Sender Email: $SENDER_EMAIL"
echo ""

# Test 1: Meeting inquiry with meeting-related keywords
echo "📧 Test 1: Meeting inquiry email"
curl -X POST "$DEPLOYMENT_URL/api/test/meeting-inquiry" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "'$USER_EMAIL'",
    "sender_email": "'$SENDER_EMAIL'",
    "subject": "When is our upcoming meeting?",
    "body": "Hi, I was wondering when our next meeting is scheduled. Could you let me know the details?"
  }' | jq '.'

echo ""
echo "⏳ Waiting 5 seconds..."
sleep 5

# Test 2: General email (should trigger standard automation)
echo ""
echo "📧 Test 2: General email (standard automation)"
curl -X POST "$DEPLOYMENT_URL/api/process-email" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "'$USER_EMAIL'",
    "sender_email": "'$SENDER_EMAIL'",
    "subject": "General inquiry",
    "body": "Hi, I have a general question about your services."
  }' | jq '.'

echo ""
echo "✅ Test completed!"
echo ""
echo "📋 Next steps:"
echo "1. Check your Gmail sent folder for automated responses"
echo "2. Check the app chat for automation activity"
echo "3. If no response, check the deployment logs for errors"
echo ""
echo "🔧 To check logs:"
echo "   - Go to your deployment platform (Railway/Render/etc.)"
echo "   - Check the application logs for any errors"
echo "   - Look for 'Email Monitor' or 'Meeting Inquiry' log entries" 