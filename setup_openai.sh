#!/bin/bash

echo "🤖 AdvisorAI OpenAI API Key Setup"
echo "=================================="
echo ""

# Check if API key is already set
if [ ! -z "$OPENAI_API_KEY" ] && [ "$OPENAI_API_KEY" != "your_openai_api_key_here" ]; then
    echo "✅ OpenAI API key is already configured!"
    echo "Current key: ${OPENAI_API_KEY:0:10}..."
    echo ""
    echo "To use a different key, run: export OPENAI_API_KEY=\"your_new_key\""
    exit 0
fi

echo "To use the AI agent features, you need an OpenAI API key."
echo ""
echo "1. Go to https://platform.openai.com/account/api-keys"
echo "2. Create a new API key"
echo "3. Copy the key"
echo ""

read -p "Enter your OpenAI API key: " api_key

if [ -z "$api_key" ]; then
    echo "❌ No API key provided. Setup cancelled."
    exit 1
fi

# Set the environment variable
export OPENAI_API_KEY="$api_key"

# Add to shell profile
shell_profile=""
if [[ "$SHELL" == *"zsh"* ]]; then
    shell_profile="$HOME/.zshrc"
elif [[ "$SHELL" == *"bash"* ]]; then
    shell_profile="$HOME/.bashrc"
else
    shell_profile="$HOME/.profile"
fi

# Check if already in profile
if ! grep -q "OPENAI_API_KEY" "$shell_profile" 2>/dev/null; then
    echo "" >> "$shell_profile"
    echo "# AdvisorAI OpenAI API Key" >> "$shell_profile"
    echo "export OPENAI_API_KEY=\"$api_key\"" >> "$shell_profile"
    echo "✅ Added to $shell_profile"
else
    echo "⚠️  OPENAI_API_KEY already exists in $shell_profile"
    echo "   Please update it manually with your new key"
fi

echo ""
echo "✅ OpenAI API key configured!"
echo "Current session: export OPENAI_API_KEY=\"${api_key:0:10}...\""
echo ""
echo "To start the application:"
echo "  mix phx.server"
echo ""
echo "To reload your shell profile:"
echo "  source $shell_profile" 