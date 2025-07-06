#!/usr/bin/env python3
"""
Gmail API OAuth2 Test Script for Google Cloud Shell
This script helps test Gmail API permissions with OAuth2
"""

import os
import json
import requests
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

# Gmail API scopes
SCOPES = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/calendar.readonly',
    'https://www.googleapis.com/auth/calendar.events'
]

def test_gmail_api():
    """Test Gmail API with OAuth2"""
    print("🔧 Gmail API OAuth2 Test")
    print("=" * 50)
    
    creds = None
    
    # Check if token file exists
    if os.path.exists('token.json'):
        print("📋 Loading existing token...")
        creds = Credentials.from_authorized_user_file('token.json', SCOPES)
    
    # If no valid credentials, let user log in
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            print("🔄 Refreshing token...")
            creds.refresh(Request())
        else:
            print("🔐 No valid credentials found. Please authenticate...")
            print("📋 You need to:")
            print("1. Go to Google Cloud Console > APIs & Services > Credentials")
            print("2. Create OAuth 2.0 Client ID")
            print("3. Download the client configuration file")
            print("4. Save it as 'credentials.json' in this directory")
            
            if not os.path.exists('credentials.json'):
                print("\n❌ credentials.json not found!")
                print("Please download your OAuth 2.0 client configuration file")
                print("and save it as 'credentials.json' in this directory.")
                return False
            
            flow = InstalledAppFlow.from_client_secrets_file('credentials.json', SCOPES)
            creds = flow.run_local_server(port=0)
        
        # Save credentials for next run
        with open('token.json', 'w') as token:
            token.write(creds.to_json())
    
    try:
        # Build Gmail service
        service = build('gmail', 'v1', credentials=creds)
        
        # Test 1: Get user profile
        print("\n🧪 Test 1: Getting Gmail profile...")
        profile = service.users().getProfile(userId='me').execute()
        print(f"✅ Gmail profile: {profile['emailAddress']}")
        
        # Test 2: List messages (read permission)
        print("\n🧪 Test 2: Testing read permission...")
        messages = service.users().messages().list(userId='me', maxResults=1).execute()
        print(f"✅ Read permission: Found {len(messages.get('messages', []))} messages")
        
        # Test 3: Test send permission (create draft instead of sending)
        print("\n🧪 Test 3: Testing send permission...")
        test_message = {
            'raw': 'RnJvbTogdGVzdEBleGFtcGxlLmNvbQpUbzogdGVzdEBleGFtcGxlLmNvbQpTdWJqZWN0OiBUZXN0CkNvbnRlbnQtVHlwZTogdGV4dC9wbGFpbjsgY2hhcnNldD1VVEYtOAoKVGVzdCBtZXNzYWdl'
        }
        
        try:
            # Try to create a draft (tests send permission without actually sending)
            draft = service.users().drafts().create(userId='me', body={'message': test_message}).execute()
            print("✅ Send permission: Can create drafts")
            
            # Clean up - delete the draft
            service.users().drafts().delete(userId='me', id=draft['id']).execute()
            print("✅ Draft cleaned up")
            
        except HttpError as error:
            if error.resp.status == 403:
                print("❌ Send permission denied: Insufficient authentication scopes")
                print("🔧 You need to re-authenticate with the gmail.send scope")
            else:
                print(f"❌ Send test failed: {error}")
        
        # Test 4: Check granted scopes
        print("\n🧪 Test 4: Checking granted scopes...")
        token_info = creds.token_info
        if token_info and 'scope' in token_info:
            granted_scopes = token_info['scope'].split(' ')
            print(f"📋 Granted scopes: {len(granted_scopes)}")
            for scope in granted_scopes:
                print(f"   - {scope}")
        else:
            print("⚠️  Could not retrieve scope information")
        
        print("\n✅ Gmail API tests completed!")
        return True
        
    except HttpError as error:
        print(f"❌ Gmail API error: {error}")
        return False

def test_oauth2_playground():
    """Instructions for OAuth2 Playground testing"""
    print("\n🔧 Alternative: OAuth2 Playground Testing")
    print("=" * 50)
    print("1. Go to: https://developers.google.com/oauthplayground/")
    print("2. Click the settings icon (⚙️) in the top right")
    print("3. Check 'Use your own OAuth credentials'")
    print("4. Enter your OAuth 2.0 Client ID and Client Secret")
    print("5. Close settings")
    print("6. Select 'Gmail API v1' from the left panel")
    print("7. Select these scopes:")
    print("   - https://www.googleapis.com/auth/gmail.readonly")
    print("   - https://www.googleapis.com/auth/gmail.send")
    print("8. Click 'Authorize APIs'")
    print("9. Sign in with your Google account")
    print("10. Click 'Exchange authorization code for tokens'")
    print("11. Test the endpoints:")
    print("    - GET https://gmail.googleapis.com/gmail/v1/users/me/profile")
    print("    - POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send")

if __name__ == '__main__':
    print("🚀 Starting Gmail API OAuth2 Test...")
    
    # Install required packages if not available
    try:
        import google.auth
        import googleapiclient
    except ImportError:
        print("📦 Installing required packages...")
        os.system('pip install --user google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client')
        print("✅ Packages installed. Please run the script again.")
        exit(0)
    
    # Run tests
    success = test_gmail_api()
    
    if not success:
        test_oauth2_playground()
    
    print("\n📋 Summary:")
    print("- If all tests pass: Your OAuth2 setup is correct")
    print("- If send permission fails: Re-authenticate with proper scopes")
    print("- If you can't authenticate: Check your OAuth2 client configuration") 