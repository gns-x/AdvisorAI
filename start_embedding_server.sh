#!/bin/bash

# Start the local embedding server for AdvisorAI
echo "Starting AdvisorAI Embedding Server..."

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    exit 1
fi

# Check if pip is available
if ! command -v pip3 &> /dev/null; then
    echo "Error: pip3 is required but not installed."
    exit 1
fi

# Install dependencies if needed
echo "Installing Python dependencies..."
pip3 install -r requirements.txt

# Start the server
echo "Starting embedding server on http://localhost:8001"
echo "Health check: http://localhost:8001/health"
echo "Press Ctrl+C to stop the server"
echo ""

python3 embedding_server.py 