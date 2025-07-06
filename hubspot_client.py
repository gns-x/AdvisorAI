#!/usr/bin/env python3
"""
HubSpot API Client
This module provides a client for interacting with HubSpot APIs using OAuth tokens
"""

import os
import json
import requests
from typing import Dict, List, Optional, Any
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

class HubSpotClient:
    """HubSpot API client for making authenticated requests"""
    
    def __init__(self, access_token: Optional[str] = None):
        """
        Initialize HubSpot client
        
        Args:
            access_token: OAuth access token. If not provided, will try to load from saved tokens
        """
        self.base_url = "https://api.hubapi.com"
        self.access_token = access_token
        
        if not self.access_token:
            self.access_token = self._load_access_token()
        
        if not self.access_token:
            raise ValueError("No access token provided or found")
        
        self.headers = {
            'Authorization': f'Bearer {self.access_token}',
            'Content-Type': 'application/json'
        }
    
    def _load_access_token(self) -> Optional[str]:
        """Load access token from saved tokens file"""
        tokens_file = 'hubspot_tokens.json'
        if os.path.exists(tokens_file):
            try:
                with open(tokens_file, 'r') as f:
                    tokens = json.load(f)
                    return tokens.get('access_token')
            except Exception as e:
                print(f"Error loading tokens: {e}")
        return None
    
    def _make_request(self, method: str, endpoint: str, **kwargs) -> Dict[str, Any]:
        """Make authenticated request to HubSpot API"""
        url = f"{self.base_url}{endpoint}"
        
        # Add headers if not provided
        if 'headers' not in kwargs:
            kwargs['headers'] = self.headers
        
        response = requests.request(method, url, **kwargs)
        
        if response.status_code == 401:
            raise Exception("Access token expired or invalid. Please refresh your tokens.")
        elif response.status_code >= 400:
            raise Exception(f"API request failed: {response.status_code} - {response.text}")
        
        return response.json()
    
    def get_contacts(self, limit: int = 10, after: Optional[str] = None) -> Dict[str, Any]:
        """Get contacts from HubSpot"""
        params = {'limit': limit}
        if after:
            params['after'] = after
        
        return self._make_request('GET', '/crm/v3/objects/contacts', params=params)
    
    def search_contacts(self, query: str, limit: int = 10) -> Dict[str, Any]:
        """Search contacts by email or name"""
        search_body = {
            "filterGroups": [
                {
                    "filters": [
                        {
                            "propertyName": "email",
                            "operator": "CONTAINS_TOKEN",
                            "value": query
                        }
                    ]
                }
            ],
            "properties": ["email", "firstname", "lastname", "company"],
            "limit": limit
        }
        
        return self._make_request('POST', '/crm/v3/objects/contacts/search', json=search_body)
    
    def get_contact_by_id(self, contact_id: str) -> Dict[str, Any]:
        """Get a specific contact by ID"""
        return self._make_request('GET', f'/crm/v3/objects/contacts/{contact_id}')
    
    def create_contact(self, contact_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new contact"""
        return self._make_request('POST', '/crm/v3/objects/contacts', json=contact_data)
    
    def update_contact(self, contact_id: str, contact_data: Dict[str, Any]) -> Dict[str, Any]:
        """Update an existing contact"""
        return self._make_request('PATCH', f'/crm/v3/objects/contacts/{contact_id}', json=contact_data)
    
    def delete_contact(self, contact_id: str) -> bool:
        """Delete a contact"""
        try:
            self._make_request('DELETE', f'/crm/v3/objects/contacts/{contact_id}')
            return True
        except Exception:
            return False
    
    def get_contact_notes(self, contact_id: str, limit: int = 100) -> Dict[str, Any]:
        """Get notes associated with a contact"""
        params = {
            'associations': 'contacts',
            'after': contact_id,
            'limit': limit
        }
        
        return self._make_request('GET', '/crm/v3/objects/notes', params=params)
    
    def create_note(self, note_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new note"""
        return self._make_request('POST', '/crm/v3/objects/notes', json=note_data)
    
    def get_deals(self, limit: int = 10, after: Optional[str] = None) -> Dict[str, Any]:
        """Get deals from HubSpot"""
        params = {'limit': limit}
        if after:
            params['after'] = after
        
        return self._make_request('GET', '/crm/v3/objects/deals', params=params)
    
    def create_deal(self, deal_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new deal"""
        return self._make_request('POST', '/crm/v3/objects/deals', json=deal_data)
    
    def get_companies(self, limit: int = 10, after: Optional[str] = None) -> Dict[str, Any]:
        """Get companies from HubSpot"""
        params = {'limit': limit}
        if after:
            params['after'] = after
        
        return self._make_request('GET', '/crm/v3/objects/companies', params=params)
    
    def create_company(self, company_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new company"""
        return self._make_request('POST', '/crm/v3/objects/companies', json=company_data)
    
    def get_user_info(self) -> Dict[str, Any]:
        """Get current user information"""
        return self._make_request('GET', f'/oauth/v1/access-tokens/{self.access_token}')
    
    def test_connection(self) -> Dict[str, Any]:
        """Test the API connection"""
        try:
            # Try to get contacts as a test
            result = self.get_contacts(limit=1)
            return {'status': 'success', 'message': 'API connection successful'}
        except Exception as e:
            return {'status': 'error', 'message': str(e)}


def main():
    """Example usage of HubSpot client"""
    print("🔧 HubSpot API Client Example")
    print("=" * 50)
    
    try:
        # Initialize client
        client = HubSpotClient()
        print("✅ HubSpot client initialized")
        
        # Test connection
        print("🧪 Testing API connection...")
        test_result = client.test_connection()
        print(f"✅ {test_result['message']}")
        
        # Get user info
        print("👤 Getting user information...")
        user_info = client.get_user_info()
        print(f"✅ User: {user_info.get('user', 'N/A')}")
        
        # Get contacts
        print("📋 Getting contacts...")
        contacts = client.get_contacts(limit=5)
        print(f"✅ Found {len(contacts.get('results', []))} contacts")
        
        # Display first contact if available
        if contacts.get('results'):
            first_contact = contacts['results'][0]
            print(f"📧 First contact: {first_contact.get('properties', {}).get('email', 'N/A')}")
        
        print("\n✅ HubSpot API client test completed successfully!")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        print("\n📋 Troubleshooting:")
        print("   1. Make sure you have valid OAuth tokens")
        print("   2. Run hubspot_oauth.py to get new tokens")
        print("   3. Check that your HubSpot app has the required scopes")


if __name__ == '__main__':
    main() 