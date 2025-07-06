#!/usr/bin/env python3
"""
HubSpot OAuth2 Implementation in Python
This script handles HubSpot OAuth2 authentication using credentials from .env file
"""

import os
import json
import requests
import secrets
import webbrowser
from urllib.parse import urlencode, parse_qs, urlparse
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import time
from typing import Optional, Dict, Any
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

class HubSpotOAuth:
    """HubSpot OAuth2 client implementation"""
    
    def __init__(self):
        # Load credentials from .env file
        self.client_id = os.getenv('HUBSPOT_CLIENT_ID')
        self.client_secret = os.getenv('HUBSPOT_CLIENT_SECRET')
        self.redirect_uri = os.getenv('HUBSPOT_REDIRECT_URI', 'http://localhost:4000/hubspot/oauth/callback')
        
        # HubSpot OAuth endpoints
        self.authorize_url = 'https://app.hubspot.com/oauth/authorize'
        self.token_url = 'https://api.hubapi.com/oauth/v1/token'
        self.user_info_url = 'https://api.hubapi.com/oauth/v1/access-tokens'
        
        # Default scopes for HubSpot
        self.default_scopes = [
            'crm.objects.contacts.read',
            'crm.objects.contacts.write',
            'crm.schemas.contacts.read',
            'crm.schemas.contacts.write',
            'oauth'
        ]
        
        # Validate required credentials
        if not self.client_id or not self.client_secret:
            raise ValueError(
                "Missing HubSpot credentials in .env file. "
                "Please set HUBSPOT_CLIENT_ID and HUBSPOT_CLIENT_SECRET"
            )
    
    def get_authorization_url(self, scopes: Optional[list] = None, state: Optional[str] = None) -> str:
        """Generate the authorization URL for HubSpot OAuth"""
        if scopes is None:
            scopes = self.default_scopes
        
        if state is None:
            state = secrets.token_urlsafe(16)
        
        params = {
            'client_id': self.client_id,
            'redirect_uri': self.redirect_uri,
            'scope': ' '.join(scopes),
            'response_type': 'code',
            'state': state
        }
        
        return f"{self.authorize_url}?{urlencode(params)}"
    
    def exchange_code_for_token(self, authorization_code: str) -> Dict[str, Any]:
        """Exchange authorization code for access token"""
        data = {
            'grant_type': 'authorization_code',
            'client_id': self.client_id,
            'client_secret': self.client_secret,
            'redirect_uri': self.redirect_uri,
            'code': authorization_code
        }
        
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded'
        }
        
        response = requests.post(self.token_url, data=data, headers=headers)
        
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Token exchange failed: {response.status_code} - {response.text}")
    
    def refresh_access_token(self, refresh_token: str) -> Dict[str, Any]:
        """Refresh an expired access token"""
        data = {
            'grant_type': 'refresh_token',
            'client_id': self.client_id,
            'client_secret': self.client_secret,
            'refresh_token': refresh_token
        }
        
        headers = {
            'Content-Type': 'application/x-www-form-urlencoded'
        }
        
        response = requests.post(self.token_url, data=data, headers=headers)
        
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Token refresh failed: {response.status_code} - {response.text}")
    
    def get_user_info(self, access_token: str) -> Dict[str, Any]:
        """Get user information using the access token"""
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        response = requests.get(f"{self.user_info_url}/{access_token}", headers=headers)
        
        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"Failed to get user info: {response.status_code} - {response.text}")
    
    def test_api_connection(self, access_token: str) -> Dict[str, Any]:
        """Test the API connection by making a simple request"""
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        }
        
        # Test with contacts endpoint
        test_url = 'https://api.hubapi.com/crm/v3/objects/contacts'
        response = requests.get(test_url, headers=headers)
        
        if response.status_code == 200:
            return {'status': 'success', 'message': 'API connection successful'}
        else:
            return {'status': 'error', 'message': f'API connection failed: {response.status_code}'}


class OAuthCallbackHandler(BaseHTTPRequestHandler):
    """HTTP server to handle OAuth callback"""
    
    def __init__(self, *args, **kwargs):
        self.auth_code = None
        self.state = None
        self.error = None
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        """Handle GET request for OAuth callback"""
        parsed_url = urlparse(self.path)
        query_params = parse_qs(parsed_url.query)
        
        if 'code' in query_params:
            self.auth_code = query_params['code'][0]
            self.state = query_params.get('state', [None])[0]
            
            # Send success response
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            response = """
            <html>
            <head><title>OAuth Success</title></head>
            <body>
                <h1>Authentication Successful!</h1>
                <p>You can close this window now.</p>
                <script>window.close();</script>
            </body>
            </html>
            """
            self.wfile.write(response.encode())
            
        elif 'error' in query_params:
            self.error = query_params['error'][0]
            
            # Send error response
            self.send_response(400)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            response = f"""
            <html>
            <head><title>OAuth Error</title></head>
            <body>
                <h1>Authentication Failed</h1>
                <p>Error: {self.error}</p>
                <p>You can close this window now.</p>
                <script>window.close();</script>
            </body>
            </html>
            """
            self.wfile.write(response.encode())
        
        # Signal that we received the callback
        self.server.auth_code = self.auth_code
        self.server.state = self.state
        self.server.error = self.error


def start_callback_server(port: int = 4000) -> HTTPServer:
    """Start the callback server"""
    server = HTTPServer(('localhost', port), OAuthCallbackHandler)
    server.auth_code = None
    server.state = None
    server.error = None
    
    # Start server in a separate thread
    server_thread = threading.Thread(target=server.serve_forever)
    server_thread.daemon = True
    server_thread.start()
    
    return server


def interactive_oauth_flow() -> Dict[str, Any]:
    """Run interactive OAuth flow"""
    print("🚀 Starting HubSpot OAuth Flow")
    print("=" * 50)
    
    # Initialize OAuth client
    try:
        oauth_client = HubSpotOAuth()
        print("✅ OAuth client initialized successfully")
    except ValueError as e:
        print(f"❌ {e}")
        return None
    
    # Generate authorization URL
    auth_url = oauth_client.get_authorization_url()
    print(f"🔗 Authorization URL: {auth_url}")
    
    # Start callback server
    print("🌐 Starting callback server...")
    server = start_callback_server()
    
    # Open browser for authorization
    print("🌍 Opening browser for authorization...")
    webbrowser.open(auth_url)
    
    # Wait for callback
    print("⏳ Waiting for authorization callback...")
    while server.auth_code is None and server.error is None:
        time.sleep(1)
    
    # Stop server
    server.shutdown()
    
    if server.error:
        print(f"❌ OAuth error: {server.error}")
        return None
    
    if server.auth_code:
        print("✅ Authorization code received")
        
        try:
            # Exchange code for token
            print("🔄 Exchanging code for token...")
            token_data = oauth_client.exchange_code_for_token(server.auth_code)
            
            print("✅ Token exchange successful")
            print(f"📋 Access Token: {token_data.get('access_token', 'N/A')[:20]}...")
            print(f"📋 Refresh Token: {token_data.get('refresh_token', 'N/A')[:20]}...")
            print(f"📋 Expires In: {token_data.get('expires_in', 'N/A')} seconds")
            
            # Get user info
            print("👤 Getting user information...")
            user_info = oauth_client.get_user_info(token_data['access_token'])
            print(f"✅ User: {user_info.get('user', 'N/A')}")
            
            # Test API connection
            print("🧪 Testing API connection...")
            api_test = oauth_client.test_api_connection(token_data['access_token'])
            print(f"✅ API Test: {api_test['message']}")
            
            # Save tokens to file
            tokens_file = 'hubspot_tokens.json'
            with open(tokens_file, 'w') as f:
                json.dump({
                    'access_token': token_data['access_token'],
                    'refresh_token': token_data.get('refresh_token'),
                    'expires_in': token_data.get('expires_in'),
                    'user': user_info.get('user'),
                    'scopes': token_data.get('scope', '').split(' ')
                }, f, indent=2)
            
            print(f"💾 Tokens saved to {tokens_file}")
            
            return {
                'access_token': token_data['access_token'],
                'refresh_token': token_data.get('refresh_token'),
                'expires_in': token_data.get('expires_in'),
                'user_info': user_info,
                'api_test': api_test
            }
            
        except Exception as e:
            print(f"❌ Error during token exchange: {e}")
            return None
    
    return None


def load_saved_tokens() -> Optional[Dict[str, Any]]:
    """Load saved tokens from file"""
    tokens_file = 'hubspot_tokens.json'
    if os.path.exists(tokens_file):
        try:
            with open(tokens_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"❌ Error loading tokens: {e}")
    return None


def refresh_saved_tokens() -> Optional[Dict[str, Any]]:
    """Refresh saved tokens"""
    tokens = load_saved_tokens()
    if not tokens or 'refresh_token' not in tokens:
        print("❌ No refresh token available")
        return None
    
    try:
        oauth_client = HubSpotOAuth()
        new_tokens = oauth_client.refresh_access_token(tokens['refresh_token'])
        
        # Update saved tokens
        tokens.update(new_tokens)
        with open('hubspot_tokens.json', 'w') as f:
            json.dump(tokens, f, indent=2)
        
        print("✅ Tokens refreshed successfully")
        return tokens
        
    except Exception as e:
        print(f"❌ Error refreshing tokens: {e}")
        return None


def main():
    """Main function"""
    print("🔧 HubSpot OAuth Python Client")
    print("=" * 50)
    
    # Check if we have saved tokens
    saved_tokens = load_saved_tokens()
    
    if saved_tokens:
        print("📋 Found saved tokens")
        print(f"👤 User: {saved_tokens.get('user', 'N/A')}")
        
        # Test if tokens are still valid
        try:
            oauth_client = HubSpotOAuth()
            api_test = oauth_client.test_api_connection(saved_tokens['access_token'])
            
            if api_test['status'] == 'success':
                print("✅ Saved tokens are still valid")
                print("📋 Available actions:")
                print("1. Use existing tokens")
                print("2. Refresh tokens")
                print("3. Start new OAuth flow")
                
                choice = input("\nEnter your choice (1-3): ").strip()
                
                if choice == '1':
                    print("✅ Using existing tokens")
                    return saved_tokens
                elif choice == '2':
                    return refresh_saved_tokens()
                elif choice == '3':
                    print("🔄 Starting new OAuth flow...")
                else:
                    print("❌ Invalid choice")
                    return None
            else:
                print("❌ Saved tokens are invalid, starting new OAuth flow...")
                
        except Exception as e:
            print(f"❌ Error testing saved tokens: {e}")
            print("🔄 Starting new OAuth flow...")
    
    # Start new OAuth flow
    return interactive_oauth_flow()


if __name__ == '__main__':
    # Check if required packages are installed
    try:
        import requests
        import dotenv
    except ImportError:
        print("📦 Installing required packages...")
        os.system('pip install requests python-dotenv')
        print("✅ Packages installed. Please run the script again.")
        exit(0)
    
    # Run OAuth flow
    result = main()
    
    if result:
        print("\n✅ OAuth flow completed successfully!")
        print("📋 Summary:")
        print(f"   - User: {result.get('user_info', {}).get('user', 'N/A')}")
        print(f"   - API Status: {result.get('api_test', {}).get('message', 'N/A')}")
        print(f"   - Tokens saved to: hubspot_tokens.json")
    else:
        print("\n❌ OAuth flow failed!")
        print("📋 Troubleshooting:")
        print("   1. Check your .env file has HUBSPOT_CLIENT_ID and HUBSPOT_CLIENT_SECRET")
        print("   2. Verify your HubSpot app is configured correctly")
        print("   3. Ensure redirect URI matches your app settings")
        print("   4. Check that required scopes are enabled in your HubSpot app") 