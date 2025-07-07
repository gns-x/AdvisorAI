#!/bin/bash

echo "🚀 Setting up Together AI for AdvisorAI"
echo "========================================"

# Check if .env file exists and has TOGETHER_API_KEY
if [ -f ".env" ] && grep -q "TOGETHER_API_KEY=" .env; then
    echo "✅ .env file exists with TOGETHER_API_KEY"
    current_key=$(grep "TOGETHER_API_KEY=" .env | cut -d'=' -f2)
    if [ "$current_key" = "your_api_key_here" ]; then
        echo "⚠️  Please update the API key in .env file"
        echo "Current value: $current_key"
    else
        echo "✅ API key is configured: ${current_key:0:10}..."
    fi
else
    echo "❌ .env file not found or TOGETHER_API_KEY not set"
    echo ""
    echo "To get your free API key:"
    echo "1. Go to https://www.together.ai/"
    echo "2. Sign up for a free account"
    echo "3. Get your API key from the dashboard"
    echo ""
    echo "Then update the .env file:"
    echo "Edit .env and replace 'your_api_key_here' with your actual API key"
    echo ""
fi

echo ""
echo "📋 Next steps:"
echo "1. Get your API key from https://www.together.ai/"
echo "2. Edit .env file and replace 'your_api_key_here' with your actual key"
echo "3. Test the connection: curl -H \"Authorization: Bearer YOUR_API_KEY\" https://api.together.xyz/v1/models"
echo "4. Start your app: mix phx.server"
echo ""
echo "🎯 Your app will now use the free Llama 3.3 70B model from Together AI!"
echo "   - No local setup required"
echo "   - Free tier available"
echo "   - OpenAI-compatible API"
echo "" 