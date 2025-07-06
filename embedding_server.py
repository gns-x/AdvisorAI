#!/usr/bin/env python3
"""
Local Embedding Server for AdvisorAI
Provides embeddings for RAG (Retrieval Augmented Generation) using sentence-transformers
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import SentenceTransformer
import uvicorn
import logging
from typing import List, Union
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(title="AdvisorAI Embedding Server", version="1.0.0")

# Load the embedding model (this will download on first run)
MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
logger.info(f"Loading embedding model: {MODEL_NAME}")
model = SentenceTransformer(MODEL_NAME)
logger.info("Embedding model loaded successfully!")

class EmbeddingRequest(BaseModel):
    input: Union[str, List[str]]

class EmbeddingResponse(BaseModel):
    data: List[dict]
    model: str
    usage: dict

@app.get("/")
async def root():
    return {"message": "AdvisorAI Embedding Server", "model": MODEL_NAME}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "model": MODEL_NAME}

@app.post("/v1/embeddings", response_model=EmbeddingResponse)
async def create_embeddings(request: EmbeddingRequest):
    try:
        # Handle both single string and list of strings
        if isinstance(request.input, str):
            texts = [request.input]
        else:
            texts = request.input
        
        # Generate embeddings
        embeddings = model.encode(texts, convert_to_tensor=False)
        
        # Convert to list format for response
        embedding_list = embeddings.tolist() if hasattr(embeddings, 'tolist') else embeddings
        
        # Format response to match OpenAI API format
        data = []
        for i, embedding in enumerate(embedding_list):
            data.append({
                "object": "embedding",
                "embedding": embedding,
                "index": i
            })
        
        # Calculate usage (approximate)
        total_tokens = sum(len(text.split()) for text in texts)
        
        return EmbeddingResponse(
            data=data,
            model=MODEL_NAME,
            usage={
                "prompt_tokens": total_tokens,
                "total_tokens": total_tokens
            }
        )
        
    except Exception as e:
        logger.error(f"Error generating embeddings: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Embedding generation failed: {str(e)}")

@app.post("/embeddings")
async def create_embeddings_legacy(request: EmbeddingRequest):
    """Legacy endpoint for compatibility"""
    return await create_embeddings(request)

if __name__ == "__main__":
    # Get port from environment or default to 8001
    port = int(os.getenv("EMBEDDING_SERVER_PORT", 8001))
    host = os.getenv("EMBEDDING_SERVER_HOST", "0.0.0.0")
    
    logger.info(f"Starting embedding server on {host}:{port}")
    uvicorn.run(app, host=host, port=port) 