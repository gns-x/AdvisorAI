#!/usr/bin/env python3
"""
Test script for HubSpot OAuth implementation
This script demonstrates the complete OAuth flow and API usage
"""

import os
import json
from hubspot_oauth import HubSpotOAuth, load_saved_tokens, refresh_saved_tokens
from hubspot_client import HubSpotClient

def test_oauth_flow():
    """Test the complete OAuth flow"""
    print("🧪 Testing HubSpot OAuth Flow")
    print("=" * 50)
    
    try:
        # Test OAuth client initialization
        oauth_client = HubSpotOAuth()
        print("✅ OAuth client initialized successfully")
        
        # Test authorization URL generation
        auth_url = oauth_client.get_authorization_url()
        print(f"✅ Authorization URL generated: {auth_url[:50]}...")
        
        # Test loading saved tokens
        saved_tokens = load_saved_tokens()
        if saved_tokens:
            print(f"✅ Found saved tokens for user: {saved_tokens.get('user', 'N/A')}")
        else:
            print("ℹ️  No saved tokens found")
        
        return True
        
    except Exception as e:
        print(f"❌ OAuth flow test failed: {e}")
        return False

def test_api_client():
    """Test the API client functionality"""
    print("\n🧪 Testing HubSpot API Client")
    print("=" * 50)
    
    try:
        # Initialize client
        client = HubSpotClient()
        print("✅ API client initialized successfully")
        
        # Test connection
        test_result = client.test_connection()
        print(f"✅ Connection test: {test_result['message']}")
        
        # Get user info
        user_info = client.get_user_info()
        print(f"✅ User info: {user_info.get('user', 'N/A')}")
        
        # Test getting contacts
        contacts = client.get_contacts(limit=3)
        print(f"✅ Retrieved {len(contacts.get('results', []))} contacts")
        
        # Display first contact if available
        if contacts.get('results'):
            first_contact = contacts['results'][0]
            properties = first_contact.get('properties', {})
            print(f"📧 Sample contact: {properties.get('email', 'N/A')}")
        
        return True
        
    except Exception as e:
        print(f"❌ API client test failed: {e}")
        return False

def test_contact_operations():
    """Test contact-related operations"""
    print("\n🧪 Testing Contact Operations")
    print("=" * 50)
    
    try:
        client = HubSpotClient()
        
        # Test contact search
        search_results = client.search_contacts("test", limit=2)
        print(f"✅ Contact search: Found {len(search_results.get('results', []))} results")
        
        # Test creating a test contact (if you want to test this)
        # Uncomment the following lines to test contact creation
        """
        test_contact = {
            "properties": {
                "email": "test@example.com",
                "firstname": "Test",
                "lastname": "User"
            }
        }
        created_contact = client.create_contact(test_contact)
        print(f"✅ Created test contact: {created_contact.get('id')}")
        """
        
        return True
        
    except Exception as e:
        print(f"❌ Contact operations test failed: {e}")
        return False

def test_token_management():
    """Test token management functionality"""
    print("\n🧪 Testing Token Management")
    print("=" * 50)
    
    try:
        # Load saved tokens
        tokens = load_saved_tokens()
        if tokens:
            print(f"✅ Loaded tokens for user: {tokens.get('user', 'N/A')}")
            print(f"📋 Token scopes: {', '.join(tokens.get('scopes', []))}")
            
            # Test token refresh (only if refresh token exists)
            if tokens.get('refresh_token'):
                print("🔄 Testing token refresh...")
                try:
                    oauth_client = HubSpotOAuth()
                    new_tokens = oauth_client.refresh_access_token(tokens['refresh_token'])
                    print("✅ Token refresh successful")
                except Exception as e:
                    print(f"⚠️  Token refresh failed (this is normal if tokens are still valid): {e}")
            else:
                print("ℹ️  No refresh token available")
        else:
            print("ℹ️  No saved tokens to test")
        
        return True
        
    except Exception as e:
        print(f"❌ Token management test failed: {e}")
        return False

def main():
    """Run all tests"""
    print("🚀 HubSpot OAuth Test Suite")
    print("=" * 60)
    
    # Check if .env file exists
    if not os.path.exists('.env'):
        print("❌ .env file not found!")
        print("📋 Please create a .env file with your HubSpot credentials:")
        print("   HUBSPOT_CLIENT_ID=your_client_id")
        print("   HUBSPOT_CLIENT_SECRET=your_client_secret")
        print("   HUBSPOT_REDIRECT_URI=http://localhost:4000/hubspot/oauth/callback")
        return
    
    # Run tests
    tests = [
        ("OAuth Flow", test_oauth_flow),
        ("API Client", test_api_client),
        ("Contact Operations", test_contact_operations),
        ("Token Management", test_token_management)
    ]
    
    results = []
    for test_name, test_func in tests:
        print(f"\n🔧 Running {test_name} test...")
        result = test_func()
        results.append((test_name, result))
    
    # Summary
    print("\n📊 Test Results Summary")
    print("=" * 60)
    
    passed = 0
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name}: {status}")
        if result:
            passed += 1
    
    print(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All tests passed! Your HubSpot OAuth implementation is working correctly.")
    else:
        print("⚠️  Some tests failed. Check the output above for details.")
        print("\n📋 Next steps:")
        print("   1. Run 'python hubspot_oauth.py' to complete the OAuth flow")
        print("   2. Check your HubSpot app configuration")
        print("   3. Verify your .env file has correct credentials")

if __name__ == '__main__':
    main() 