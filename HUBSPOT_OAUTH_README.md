# HubSpot OAuth Implementation in Python

This implementation provides a complete HubSpot OAuth2 flow in Python with credentials stored in a `.env` file.

## Files Overview

- `hubspot_oauth.py` - Main OAuth implementation with interactive flow
- `hubspot_client.py` - HubSpot API client for making authenticated requests
- `env.example` - Template for environment variables
- `requirements.txt` - Python dependencies (updated)

## Setup Instructions

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Create HubSpot App

1. Go to [HubSpot Developers](https://developers.hubspot.com/)
2. Create a new app or use an existing one
3. Enable OAuth 2.0 in your app settings
4. Add the redirect URI: `http://localhost:4000/hubspot/oauth/callback`
5. Note down your Client ID and Client Secret

### 3. Configure Environment Variables

Copy the example environment file and fill in your credentials:

```bash
cp env.example .env
```

Edit `.env` and add your HubSpot credentials:

```env
HUBSPOT_CLIENT_ID=your_hubspot_client_id_here
HUBSPOT_CLIENT_SECRET=your_hubspot_client_secret_here
HUBSPOT_REDIRECT_URI=http://localhost:4000/hubspot/oauth/callback
```

### 4. Run OAuth Flow

```bash
python hubspot_oauth.py
```

This will:
- Open your browser for authorization
- Start a local server to handle the callback
- Exchange the authorization code for tokens
- Save tokens to `hubspot_tokens.json`
- Test the API connection

### 5. Use the API Client

```bash
python hubspot_client.py
```

## Usage Examples

### Basic OAuth Flow

```python
from hubspot_oauth import HubSpotOAuth

# Initialize OAuth client
oauth_client = HubSpotOAuth()

# Get authorization URL
auth_url = oauth_client.get_authorization_url()
print(f"Authorization URL: {auth_url}")

# After user authorizes, exchange code for token
token_data = oauth_client.exchange_code_for_token(authorization_code)
print(f"Access Token: {token_data['access_token']}")
```

### Using the API Client

```python
from hubspot_client import HubSpotClient

# Initialize client (will auto-load tokens from file)
client = HubSpotClient()

# Get contacts
contacts = client.get_contacts(limit=10)
print(f"Found {len(contacts['results'])} contacts")

# Search contacts
search_results = client.search_contacts("john@example.com")
print(f"Search results: {search_results}")

# Create a contact
new_contact = {
    "properties": {
        "email": "new@example.com",
        "firstname": "John",
        "lastname": "Doe"
    }
}
created_contact = client.create_contact(new_contact)
print(f"Created contact: {created_contact}")
```

### Manual Token Management

```python
from hubspot_oauth import HubSpotOAuth, load_saved_tokens, refresh_saved_tokens

# Load saved tokens
tokens = load_saved_tokens()
if tokens:
    print(f"User: {tokens['user']}")

# Refresh expired tokens
oauth_client = HubSpotOAuth()
new_tokens = oauth_client.refresh_access_token(tokens['refresh_token'])
print(f"New access token: {new_tokens['access_token']}")
```

## API Methods Available

### Contacts
- `get_contacts(limit=10, after=None)` - Get contacts
- `search_contacts(query, limit=10)` - Search contacts
- `get_contact_by_id(contact_id)` - Get specific contact
- `create_contact(contact_data)` - Create new contact
- `update_contact(contact_id, contact_data)` - Update contact
- `delete_contact(contact_id)` - Delete contact

### Notes
- `get_contact_notes(contact_id, limit=100)` - Get contact notes
- `create_note(note_data)` - Create new note

### Deals
- `get_deals(limit=10, after=None)` - Get deals
- `create_deal(deal_data)` - Create new deal

### Companies
- `get_companies(limit=10, after=None)` - Get companies
- `create_company(company_data)` - Create new company

### Utility
- `get_user_info()` - Get current user info
- `test_connection()` - Test API connection

## Scopes

The default scopes included are:
- `crm.objects.contacts.read` - Read contacts
- `crm.objects.contacts.write` - Create/update contacts
- `crm.schemas.contacts.read` - Read contact schemas
- `crm.schemas.contacts.write` - Modify contact schemas
- `oauth` - Basic OAuth access

## Token Management

### Automatic Token Loading
The client automatically loads tokens from `hubspot_tokens.json` if no access token is provided.

### Token Refresh
Tokens are automatically refreshed when they expire using the refresh token.

### Token Storage
Tokens are stored in `hubspot_tokens.json` with the following structure:
```json
{
  "access_token": "your_access_token",
  "refresh_token": "your_refresh_token",
  "expires_in": 3600,
  "user": "user@example.com",
  "scopes": ["crm.objects.contacts.read", "crm.objects.contacts.write"]
}
```

## Error Handling

The implementation includes comprehensive error handling:

- **Missing credentials**: Clear error message with setup instructions
- **Invalid tokens**: Automatic refresh attempt
- **API errors**: Detailed error messages with status codes
- **Network errors**: Graceful handling with retry suggestions

## Troubleshooting

### Common Issues

1. **"Missing HubSpot credentials"**
   - Check your `.env` file has `HUBSPOT_CLIENT_ID` and `HUBSPOT_CLIENT_SECRET`
   - Ensure the file is named `.env` (not `.env.txt`)

2. **"Access token expired"**
   - Run `python hubspot_oauth.py` to get new tokens
   - Or use the refresh functionality

3. **"API connection failed"**
   - Verify your HubSpot app has the required scopes enabled
   - Check that your app is properly configured in HubSpot

4. **"OAuth error"**
   - Ensure redirect URI matches your app settings
   - Check that your app is in the correct state (development/production)

### Debug Mode

For debugging, you can enable verbose logging by modifying the scripts to include:

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

## Security Notes

- Never commit your `.env` file to version control
- Keep your client secret secure
- Tokens are stored locally in `hubspot_tokens.json`
- Consider encrypting stored tokens for production use

## Integration with Existing Codebase

This Python implementation can be used alongside the existing Elixir implementation:

- Use Python for specific API operations or testing
- Use Elixir for the main application logic
- Share the same OAuth credentials between both implementations

## Production Considerations

For production use, consider:

1. **Token Storage**: Use a secure database instead of local files
2. **Error Handling**: Implement retry logic and circuit breakers
3. **Rate Limiting**: Respect HubSpot's API rate limits
4. **Monitoring**: Add logging and metrics for API calls
5. **Security**: Implement proper token encryption and rotation 