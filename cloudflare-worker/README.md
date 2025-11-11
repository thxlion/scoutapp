## Scout Cloudflare Worker

This worker acts as a thin GPT‑4o mini proxy with TMDB enrichment.

### What it does
1. `POST /api/suggest`
   - Sends the user’s vibe to GPT‑4o mini using the same conversational prompt you’d use in ChatGPT.
   - Returns GPT’s raw textual reply (no schema).
   - Runs a second GPT call to extract the titles mentioned.
   - Looks every title up on TMDB, attaching posters/providers when available (titles that can’t be matched still come back).

2. `GET /api/health`
   - Simple liveness ping.

### Setup
```bash
npm i -g wrangler
wrangler login
wrangler secret put OPENAI_API_KEY   # gpt-4o mini key
wrangler secret put TMDB_V4          # TMDB v4 read token
wrangler deploy
```

### API contract
```http
POST /api/suggest
{ "prompt": "africa inspired anime" }
```

Response:
```json
{
  "prompt": "africa inspired anime",
  "responseText": "(GPT-4o mini paragraph here)",
  "suggestions": [
    {
      "id": "...",
      "title": "Yasuke",
      "mediaType": "tv",
      "year": "2021",
      "tmdb": {
        "tmdbId": 91557,
        "title": "Yasuke",
        "posterPath": "/xyz.jpg",
        "overview": "...",
        "genres": ["Animation", "Action"],
        "providers": { "flatrate": [{ "name": "Netflix" }] }
      }
    },
    {
      "id": "...",
      "title": "Afro Samurai",
      "mediaType": "tv",
      "tmdb": null
    }
  ]
}
```

The iOS client displays `responseText` verbatim and shows cards for each suggestion using whatever TMDB metadata was found (or a text-only fallback when TMDB had no match).
