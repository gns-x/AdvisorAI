#!/bin/bash

# Build Tailwind CSS
echo "Building Tailwind CSS..."
npx tailwindcss -i ./css/app.css -o ./css/app.min.css --minify

# Build JavaScript
echo "Building JavaScript..."
npx esbuild js/app.js --bundle --minify --outfile=js/app.min.js

echo "Assets built successfully!" 