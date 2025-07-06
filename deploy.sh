#!/bin/bash

echo "🚀 Deploying AdvisorAI..."

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    echo "❌ Error: mix.exs not found. Please run this script from the project root."
    exit 1
fi

# Commit any changes
echo "📝 Committing changes..."
git add .
git commit -m "Deploy $(date +%Y-%m-%d_%H-%M-%S)" || true

# Push to GitHub
echo "📤 Pushing to GitHub..."
git push origin main

echo "✅ Deployment initiated!"
echo ""
echo "🌐 Next steps:"
echo "1. Go to Railway: https://railway.app"
echo "2. Create new project from GitHub repo"
echo "3. Set environment variables:"
echo "   - OPENAI_API_KEY"
echo "   - GOOGLE_CLIENT_ID"
echo "   - GOOGLE_CLIENT_SECRET"
echo "   - HUBSPOT_CLIENT_ID"
echo "   - HUBSPOT_CLIENT_SECRET"
echo ""
echo "🔗 Your app will be available at: https://your-app-name.railway.app" 