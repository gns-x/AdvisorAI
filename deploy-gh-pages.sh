#!/bin/bash

# Deploy to GitHub Pages manually
echo "🚀 Deploying to GitHub Pages..."

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
echo "📁 Created temporary directory: $TEMP_DIR"

# Copy frontend files to temp directory
cp -r frontend/* "$TEMP_DIR/"
echo "📋 Copied frontend files"

# Create .nojekyll file
touch "$TEMP_DIR/.nojekyll"
echo "📄 Created .nojekyll file"

# Navigate to temp directory
cd "$TEMP_DIR"

# Initialize git repository
git init
git add .
git commit -m "Deploy to GitHub Pages"

# Add remote and push to gh-pages branch
git remote add origin https://github.com/gns-x/AdvisorAI.git
git branch -M gh-pages
git push -f origin gh-pages

# Clean up
cd ..
rm -rf "$TEMP_DIR"
echo "🧹 Cleaned up temporary directory"

echo "✅ Deployment complete!"
echo "🌐 Your site should be available at: https://gns-x.github.io/AdvisorAI/"
