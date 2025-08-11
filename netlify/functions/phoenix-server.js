const { spawn } = require('child_process');
const path = require('path');

exports.handler = async (event, context) => {
  // This is a placeholder for the Phoenix server function
  // Netlify Functions are not suitable for long-running Phoenix applications
  // Consider using Render, Fly.io, or Heroku for full Phoenix functionality
  
  const { path: requestPath, httpMethod, headers, body } = event;
  
  return {
    statusCode: 200,
    headers: {
      'Content-Type': 'text/html',
      'Cache-Control': 'no-cache',
    },
    body: `
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <title>AdvisorAI - Phoenix App</title>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
              max-width: 800px;
              margin: 0 auto;
              padding: 2rem;
              line-height: 1.6;
              color: #333;
            }
            .container {
              background: #f8f9fa;
              border-radius: 8px;
              padding: 2rem;
              margin: 2rem 0;
            }
            .warning {
              background: #fff3cd;
              border: 1px solid #ffeaa7;
              border-radius: 4px;
              padding: 1rem;
              margin: 1rem 0;
            }
            .success {
              background: #d4edda;
              border: 1px solid #c3e6cb;
              border-radius: 4px;
              padding: 1rem;
              margin: 1rem 0;
            }
            code {
              background: #e9ecef;
              padding: 0.2rem 0.4rem;
              border-radius: 3px;
              font-family: 'Monaco', 'Menlo', monospace;
            }
            .button {
              display: inline-block;
              background: #007bff;
              color: white;
              padding: 0.5rem 1rem;
              text-decoration: none;
              border-radius: 4px;
              margin: 0.5rem 0;
            }
            .button:hover {
              background: #0056b3;
            }
          </style>
        </head>
        <body>
          <h1>🚀 AdvisorAI Phoenix Application</h1>
          
          <div class="container">
            <h2>Deployment Status</h2>
            <div class="warning">
              <strong>⚠️ Important Notice:</strong> This is a static deployment placeholder.
            </div>
            
            <p>Your Phoenix application has been successfully configured for Netlify deployment, but Netlify Functions are not suitable for long-running Phoenix applications that require persistent connections (like WebSockets for LiveView).</p>
            
            <h3>Current Request Details:</h3>
            <ul>
              <li><strong>Path:</strong> <code>${requestPath}</code></li>
              <li><strong>Method:</strong> <code>${httpMethod}</code></li>
              <li><strong>User Agent:</strong> <code>${headers['user-agent'] || 'Unknown'}</code></li>
            </ul>
          </div>
          
          <div class="container">
            <h2>Recommended Deployment Options</h2>
            
            <h3>1. Render (Recommended)</h3>
            <p>Render provides excellent support for Phoenix applications with automatic deployments from Git.</p>
            <a href="https://render.com/docs/deploy-phoenix" class="button" target="_blank">Deploy to Render</a>
            
            <h3>2. Fly.io</h3>
            <p>Fly.io offers global deployment with edge computing capabilities.</p>
            <a href="https://fly.io/docs/elixir/getting-started/" class="button" target="_blank">Deploy to Fly.io</a>
            
            <h3>3. Heroku</h3>
            <p>Heroku has long been a reliable platform for Phoenix applications.</p>
            <a href="https://hexdocs.pm/phoenix/heroku.html" class="button" target="_blank">Deploy to Heroku</a>
            
            <h3>4. Railway</h3>
            <p>Railway provides simple deployment with good Phoenix support.</p>
            <a href="https://docs.railway.app/deploy/deployments" class="button" target="_blank">Deploy to Railway</a>
          </div>
          
          <div class="container">
            <h2>Environment Variables to Set</h2>
            <p>Make sure to configure these environment variables in your chosen platform:</p>
            <ul>
              <li><code>DATABASE_URL</code> - Your PostgreSQL database URL</li>
              <li><code>SECRET_KEY_BASE</code> - Phoenix secret key base</li>
              <li><code>GOOGLE_CLIENT_ID</code> - Google OAuth client ID</li>
              <li><code>GOOGLE_CLIENT_SECRET</code> - Google OAuth client secret</li>
              <li><code>HUBSPOT_CLIENT_ID</code> - HubSpot OAuth client ID</li>
              <li><code>HUBSPOT_CLIENT_SECRET</code> - HubSpot OAuth client secret</li>
              <li><code>HUBSPOT_REDIRECT_URI</code> - HubSpot OAuth redirect URI</li>
              <li><code>OPENAI_API_KEY</code> - OpenAI API key</li>
              <li><code>OPENROUTER_API_KEY</code> - OpenRouter API key</li>
              <li><code>WEBHOOK_URL</code> - Webhook URL for Gmail notifications</li>
            </ul>
          </div>
          
          <div class="success">
            <strong>✅ Success:</strong> Your Phoenix application is ready for deployment on a suitable platform!
          </div>
        </body>
      </html>
    `
  };
};
