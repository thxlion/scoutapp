## Scout Cloudflare Worker

Serverless Worker that powers Scout's intelligent discovery:

- **`/api/llm`** - Calls Workers AI to turn the user vibe into structured filters
- **`/api/web-context`** - Searches Reddit and the web for community recommendations
- **`/api/rerank-v2`** - Uses LLM with curator rubric + web context to intelligently rank results
- **`/api/rerank`** - Legacy embedding-based reranking (fallback)
- **`/api/tmdb/...`** - Proxies TMDB requests so secrets never ship with the app

### Setup

1. Install Wrangler: `npm i -g wrangler`
2. Authenticate: `wrangler login`
3. Create a TMDB v4 token and (optionally) a TMDB v3 API key.
4. Create a KV namespace for caching embeddings (optional) or rely on the in-memory Map in the Worker.

### Environment variables / bindings

Update `wrangler.toml` to match your account id and keep the AI binding:

```toml
[ai]
binding = "AI"
```

Store API credentials as secrets (they won't live in git):

```bash
wrangler secret put TMDB_V4                # Required: TMDB v4 bearer token
wrangler secret put TMDB_V3                # Optional: TMDB v3 API key
wrangler secret put OPENAI_API_KEY         # Highly recommended: OpenAI API key for intelligent reranking
wrangler secret put BRAVE_SEARCH_API_KEY   # Optional: Brave Search for web context
```

**Important:**
- **`OPENAI_API_KEY`** (highly recommended): Enables intelligent LLM-based reranking with GPT-4o-mini. Without it, falls back to basic embedding similarity (less accurate). Cost: ~$0.01 per search.
- **`BRAVE_SEARCH_API_KEY`** (optional): Adds Letterboxd/MyAnimeList context to search. Free tier: 2,000 queries/month.

Get API keys:
- OpenAI: https://platform.openai.com/api-keys
- Brave Search: https://brave.com/search/api/

### Development

```
cd cloudflare-worker
wrangler dev
```

### Deploy

```
wrangler deploy
```

### How It Works

The discovery system uses a three-stage pipeline:

**Stage 1: Web Context (NEW!)**
- Searches Reddit (`r/movies`, `r/anime`, `r/documentaries`, etc.)
- Optionally searches Brave Search for Letterboxd/MyAnimeList recommendations
- Extracts frequently mentioned titles and community vibe phrases
- ~500-800ms

**Stage 2: Filter Extraction + TMDB Fetch**
- LLM extracts genres, keywords, year ranges from user prompt
- TMDB returns candidates based on filters (popularity + genres)
- ~700ms

**Stage 3: Intelligent Reranking (THE MAGIC!)**
- LLM curator scores each candidate using:
  - World knowledge (knows Samurai Champloo = hip-hop, Ken Burns = documentaries)
  - Community recommendations (boosts titles mentioned on Reddit)
  - Rubric scoring (topical fit 35%, tone 20%, form 15%, community 20%, era 10%)
- Returns top-scored results with reasoning
- ~1-2s

**Total:** ~2.5-3.5s end-to-end (still feels instant!)

### Technical Notes

**LLM Models:**
- **`/api/llm`** uses Cloudflare Workers AI (`@cf/meta/llama-3.1-8b-instruct`) - free tier, good for parsing filters
- **`/api/rerank-v2`** uses OpenAI GPT-4o-mini when `OPENAI_API_KEY` is set - excellent at structured JSON + world knowledge (~$0.01/search)
- **`/api/rerank`** uses Cloudflare embeddings (`@cf/baai/bge-base-en-v1.5`) - fallback, less accurate but free

**External APIs:**
- **Reddit API** is free and doesn't require authentication for public searches
- **Brave Search** offers 2,000 free queries/month (enough for most usage)
- **OpenAI API** costs ~$0.01-0.02 per search (GPT-4o-mini with ~4K input + 2K output tokens)

**Architecture:**
- Filter extraction: Cloudflare AI (fast, free, works well)
- Web context: Reddit (free) + Brave Search (optional, 2K free/month)
- Reranking: OpenAI GPT-4o-mini (best quality) OR embeddings (fallback)
- The Worker enforces JSON-only responses for easy iOS `Codable` parsing
