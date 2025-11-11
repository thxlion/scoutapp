interface Env {
  AI: Ai;
  TMDB_V4: string;
  TMDB_V3?: string;
  BRAVE_SEARCH_API_KEY?: string;
  OPENAI_API_KEY?: string;
}

const LLM_MODEL = "@cf/meta/llama-3.1-8b-instruct";
const EMBED_MODEL = "@cf/baai/bge-base-en-v1.5";
const TMDB_BASE = "https://api.themoviedb.org/3";

const embeddingCache = new Map<string, number[]>();

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/api/health") {
      return json({ ok: true });
    }

    if (url.pathname.startsWith("/api/tmdb/")) {
      return proxyTMDB(request, env, url);
    }

    if (url.pathname === "/api/llm" && request.method === "POST") {
      return handleLLM(request, env);
    }

    if (url.pathname === "/api/rerank" && request.method === "POST") {
      return handleRerank(request, env);
    }

    if (url.pathname === "/api/web-context" && request.method === "POST") {
      return handleWebContext(request, env);
    }

    if (url.pathname === "/api/rerank-v2" && request.method === "POST") {
      return handleRerankV2(request, env);
    }

    return new Response("Not found", { status: 404 });
  }
};

async function handleLLM(request: Request, env: Env): Promise<Response> {
  try {
    const { prompt } = await request.json<LLMRequest>();
    if (!prompt || typeof prompt !== "string") {
      return json({ error: "prompt required" }, 400);
    }

    const systemPrompt = `You are Scout's media sommelier. Extract structured filters AND generate TMDB search queries from free-form viewer vibes.
Return ONLY minified JSON with this schema:
{
  "media_types": ["movie","tv"],
  "include_keywords": ["samurai","slow burn"],
  "exclude_keywords": [],
  "genres": ["Drama","History"],
  "tone": ["Moody","Uplifting"],
  "year_min": 1960,
  "year_max": 2025,
  "languages": ["English","Japanese"],
  "search_queries": ["samurai champloo", "afro samurai", "samurai anime", "hip hop anime", "blade of the immortal"]
}
Rules for media_types:
- If user says "show", "tv show", "series", "television" → set media_types to ["tv"] ONLY
- If user says "movie", "film" → set media_types to ["movie"] ONLY
- If user says "documentary" → set media_types to ["movie","tv"] and genres MUST include "Documentary"
- Otherwise include both ["movie","tv"]

Rules for genres:
- Extract actual TMDB genres like: Action, Adventure, Animation, Comedy, Crime, Documentary, Drama, Family, Fantasy, History, Horror, Music, Mystery, Romance, Science Fiction, TV Movie, Thriller, War, Western
- If user asks for comedy → genres MUST include "Comedy"
- If user asks for documentary → genres MUST include "Documentary"
- If user asks for anime → genres MUST include "Animation"
- Prefer 2-4 genres max, focusing on what the user actually requested

Other rules:
- Extract relevant nouns as include_keywords
- Default year_min to 1960 and year_max to current year if not specified
- Default languages to ["English"] when nothing is implied
- Generate 5-7 TMDB-friendly search queries:
  * Include specific titles you know match
  * Use simple keyword combos
  * Avoid complex phrases
- Respond with valid JSON only.`;

    const aiResponse = await env.AI.run(LLM_MODEL, {
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: prompt }
      ]
    });

    const text = extractText(aiResponse);
    const payload = safeParseJSON(text);
    if (!payload) {
      return json({ error: "LLM returned invalid JSON", raw: text }, 502);
    }
    const result = applyLLMDefaults(payload);
    return json(result);
  } catch (error) {
    console.error("LLM error", error);
    return json({ error: "llm failure" }, 500);
  }
}

async function handleRerank(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json<RerankRequest>();
    if (!body.prompt || !Array.isArray(body.candidates)) {
      return json({ error: "Invalid payload" }, 400);
    }
    if (!body.candidates.length) {
      return json({ scores: [] });
    }

    const promptVector = await embedText(body.prompt, env);
    if (!promptVector) {
      return json({ error: "Unable to embed prompt" }, 500);
    }

    const scores: RerankScore[] = [];
    for (const candidate of body.candidates) {
      const key = candidateKey(candidate);
      let vector = embeddingCache.get(key);
      if (!vector) {
        const text = buildCandidateText(candidate);
        vector = await embedText(text, env);
        if (vector) {
          embeddingCache.set(key, vector);
        }
      }
      if (!vector) {
        continue;
      }
      const score = cosineSimilarity(promptVector, vector);
      scores.push({ identifier: candidate.identifier, score });
    }

    scores.sort((a, b) => b.score - a.score);
    return json({ scores });
  } catch (error) {
    console.error("Rerank error", error);
    return json({ error: "rerank failure" }, 500);
  }
}

async function proxyTMDB(request: Request, env: Env, url: URL): Promise<Response> {
  const targetPath = url.pathname.replace("/api/tmdb/", "");
  const targetUrl = `${TMDB_BASE}/${targetPath}${url.search}`;
  const headers: Record<string, string> = {
    Authorization: `Bearer ${env.TMDB_V4}`,
    Accept: "application/json"
  };
  if (env.TMDB_V3) {
    headers["X-TMDB-Api-Key"] = env.TMDB_V3;
  }

  const upstream = await fetch(targetUrl, {
    method: request.method,
    headers,
    body: request.method === "GET" ? undefined : await request.arrayBuffer()
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: upstream.headers
  });
}

async function embedText(text: string, env: Env): Promise<number[] | null> {
  try {
    const response = await env.AI.run(EMBED_MODEL, { text });
    if (Array.isArray(response) && typeof response[0] === "number") {
      return response as number[];
    }
    if (response && Array.isArray((response as any).data)) {
      const first = (response as any).data[0]?.embedding;
      if (Array.isArray(first)) {
        return first as number[];
      }
    }
    return null;
  } catch (error) {
    console.error("embed error", error);
    return null;
  }
}

function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) {
    return 0;
  }
  let dot = 0;
  let aNorm = 0;
  let bNorm = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    aNorm += a[i] * a[i];
    bNorm += b[i] * b[i];
  }
  if (aNorm === 0 || bNorm === 0) return 0;
  return dot / (Math.sqrt(aNorm) * Math.sqrt(bNorm));
}

function buildCandidateText(candidate: RerankRequest["candidates"][0]): string {
  const genreList = candidate.genres?.length ? candidate.genres.join(", ") : "Unspecified";
  return `${candidate.title} (${candidate.mediaType}${candidate.year ? `, ${candidate.year}` : ""})
Genres: ${genreList}
Overview: ${candidate.overview}`;
}

function candidateKey(candidate: RerankRequest["candidates"][0]): string {
  return `${candidate.identifier}:${candidate.title}:${candidate.year ?? ""}`;
}

function applyLLMDefaults(payload: any): LLMResponse {
  const now = new Date().getFullYear();
  return {
    media_types: normalizeStringArray(payload.media_types, ["movie", "tv"]),
    include_keywords: normalizeStringArray(payload.include_keywords, []),
    exclude_keywords: normalizeStringArray(payload.exclude_keywords, []),
    genres: normalizeStringArray(payload.genres, []),
    tone: normalizeStringArray(payload.tone, []),
    year_min: typeof payload.year_min === "number" ? payload.year_min : 1960,
    year_max: typeof payload.year_max === "number" ? payload.year_max : now,
    languages: normalizeStringArray(payload.languages, ["English"]),
    search_queries: normalizeStringArray(payload.search_queries, [])
  };
}

function normalizeStringArray(value: unknown, fallback: string[]): string[] {
  if (!Array.isArray(value)) return fallback;
  const cleaned = value
    .map((entry) => (typeof entry === "string" ? entry.trim() : ""))
    .filter(Boolean);
  return cleaned.length ? cleaned : fallback;
}

function extractText(result: any): string {
  if (!result) return "";
  if (typeof result === "string") return result;
  if (Array.isArray(result)) {
    return result.map((item) => extractText(item)).join("\n");
  }
  if (typeof result === "object") {
    if (typeof result.response === "string") return result.response;
    if (Array.isArray(result.output)) {
      return result.output.map((item) => extractText(item)).join("\n");
    }
    if (Array.isArray(result.results)) {
      return result.results.map((item) => extractText(item)).join("\n");
    }
  }
  return JSON.stringify(result);
}

function safeParseJSON(text: string): any | null {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" }
  });
}

// ============= WEB CONTEXT SEARCH =============

async function handleWebContext(request: Request, env: Env): Promise<Response> {
  try {
    const { prompt, contentType, intent } = await request.json<WebContextRequest>();
    if (!prompt || typeof prompt !== "string") {
      return json({ error: "prompt required" }, 400);
    }

    const context = await getWebContext(prompt, env, contentType, intent);
    return json(context);
  } catch (error) {
    console.error("Web context error", error);
    return json({ error: "web context failure" }, 500);
  }
}

async function getWebContext(
  prompt: string,
  env: Env,
  contentType?: string,
  intent?: WebContextRequest["intent"]
): Promise<WebContextResponse> {
  const recommendedTitles: TitleMention[] = [];
  const communityPhrases: string[] = [];
  const sources: string[] = [];

  // Determine content type for filtering
  const lowerPrompt = prompt.toLowerCase();
  const isAnime = intent?.animeOnly || lowerPrompt.includes('anime');
  const isDocumentary = lowerPrompt.includes('documentary') || lowerPrompt.includes('documentaries');

  // Determine what type to extract
  let extractionType = contentType;
  if (!extractionType) {
    if (isAnime) extractionType = 'anime';
    else if (isDocumentary) extractionType = 'documentary';
  }

  // Run searches in parallel
  const [redditResults, webResults] = await Promise.all([
    searchReddit(prompt),
    searchWeb(prompt, env)
  ]);

  // Combine all text for LLM extraction
  let combinedText = "";

  // Extract phrases from Reddit
  if (redditResults.length > 0) {
    sources.push("Reddit");
    const redditText = redditResults.map(r => r.text).join("\n\n");
    combinedText += redditText;
    communityPhrases.push(...extractPhrases(redditText));
  }

  // Add web search results
  if (webResults.length > 0) {
    sources.push("Web");
    const webText = webResults.map(r => `${r.title}\n${r.snippet}`).join("\n\n");
    combinedText += "\n\n" + webText;
  }

  // Use LLM to intelligently extract actual movie/TV/anime titles
  if (combinedText.trim()) {
    const llmTitles = await extractTitlesWithLLM(combinedText, env, extractionType);

    // Add relevance scoring to filter out garbage
    const scoredTitles = await scoreRelevance(llmTitles, prompt, env);
    recommendedTitles.push(...scoredTitles);
  }

  // Deduplicate and rank by frequency
  const titleMap = new Map<string, TitleMention>();
  for (const mention of recommendedTitles) {
    const existing = titleMap.get(mention.title.toLowerCase());
    if (existing) {
      existing.mentions++;
    } else {
      titleMap.set(mention.title.toLowerCase(), { ...mention, mentions: mention.mentions || 1 });
    }
  }

  const rankedTitles = Array.from(titleMap.values())
    .sort((a, b) => b.mentions - a.mentions)
    .slice(0, 20);

  const uniquePhrases = Array.from(new Set(communityPhrases)).slice(0, 15);

  return {
    recommendedTitles: rankedTitles,
    communityPhrases: uniquePhrases,
    sources,
    contextSummary: buildContextSummary(rankedTitles, uniquePhrases)
  };
}

async function searchReddit(query: string): Promise<RedditPost[]> {
  try {
    // Prioritize subreddits based on query keywords
    const lowerQuery = query.toLowerCase();
    let subreddits = ['movies', 'MovieSuggestions', 'television'];
    let searchTerms = query;

    // Customize search based on content type
    if (lowerQuery.includes('anime') || lowerQuery.includes('manga')) {
      subreddits = ['anime', 'Animesuggest', 'anime_suggestions', 'anime_irl'];
    } else if (lowerQuery.includes('documentary') || lowerQuery.includes('documentaries')) {
      subreddits = ['Documentaries', 'TrueFilm', 'NatureDocumentaries'];
      // For documentaries, ensure we're searching for actual documentaries
      if (!lowerQuery.includes('documentary')) {
        searchTerms = query + ' documentary';
      }
    } else if (lowerQuery.includes('tv') || lowerQuery.includes('series') || lowerQuery.includes('show')) {
      subreddits = ['television', 'televisionsuggestions', 'NetflixBestOf'];
    }

    const results: RedditPost[] = [];

    for (const subreddit of subreddits.slice(0, 3)) { // Limit to 3 subreddits to stay fast
      try {
        const searchQuery = encodeURIComponent(searchTerms);
        const url = `https://www.reddit.com/r/${subreddit}/search.json?q=${searchQuery}&restrict_sr=1&sort=relevance&limit=5`;

        const response = await fetch(url, {
          headers: {
            'User-Agent': 'Scout/1.0'
          }
        });

        if (!response.ok) continue;

        const data = await response.json() as any;
        if (data?.data?.children) {
          for (const child of data.data.children) {
            const post = child.data;
            results.push({
              title: post.title || '',
              text: `${post.title} ${post.selftext || ''}`.substring(0, 500),
              url: `https://reddit.com${post.permalink}`,
              score: post.score || 0
            });
          }
        }
      } catch (error) {
        console.error(`Reddit search error for r/${subreddit}:`, error);
      }
    }

    return results.sort((a, b) => b.score - a.score).slice(0, 10);
  } catch (error) {
    console.error("Reddit search error", error);
    return [];
  }
}

async function searchWeb(query: string, env: Env): Promise<WebResult[]> {
  try {
    if (!env.BRAVE_SEARCH_API_KEY) {
      console.warn("No BRAVE_SEARCH_API_KEY configured, skipping web search");
      return [];
    }

    // Search for recommendations and lists
    const searchQuery = `${query} recommendations site:letterboxd.com OR site:myanimelist.net OR site:imdb.com OR site:reddit.com`;
    const url = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(searchQuery)}&count=10`;

    const response = await fetch(url, {
      headers: {
        'Accept': 'application/json',
        'X-Subscription-Token': env.BRAVE_SEARCH_API_KEY
      }
    });

    if (!response.ok) {
      console.error("Brave Search API error:", response.status);
      return [];
    }

    const data = await response.json() as any;
    const results: WebResult[] = [];

    if (data?.web?.results) {
      for (const result of data.web.results) {
        results.push({
          title: result.title || '',
          snippet: result.description || '',
          url: result.url || ''
        });
      }
    }

    return results;
  } catch (error) {
    console.error("Web search error", error);
    return [];
  }
}

async function extractTitlesWithLLM(text: string, env: Env, contentType?: string): Promise<TitleMention[]> {
  try {
    // If OpenAI is available, use it (MUCH better at extraction)
    if (env.OPENAI_API_KEY) {
      return await extractTitlesWithOpenAI(text, env, contentType);
    }

    // Fallback to Cloudflare (less accurate but free)
    const truncatedText = text.substring(0, 3000);

    let extractionInstructions = "Extract ONLY actual movie, TV show, and anime titles";
    if (contentType) {
      if (contentType.includes('documentary')) {
        extractionInstructions = "Extract ONLY documentary titles. Ignore narrative films, TV shows, or anime unless they are documentaries";
      } else if (contentType.includes('anime')) {
        extractionInstructions = "Extract ONLY anime (Japanese animation) titles";
      }
    }

    const prompt = `You are analyzing Reddit discussions. ${extractionInstructions} that people are recommending or discussing.

For example, from "I loved Wolf's Rain and Princess Mononoke", extract: ["Wolf's Rain", "Princess Mononoke"]
From "Check out Magi, it's perfect for Arabian vibes", extract: ["Magi"]

DO NOT extract:
- Random phrases in quotes
- Usernames or subreddit names
- Partial sentences
- Generic terms

Text to analyze:
${truncatedText}

Return a JSON array of actual media titles only.`;

    const aiResponse = await env.AI.run(LLM_MODEL, {
      messages: [
        { role: "system", content: "Extract movie/TV/anime titles from discussions. Return JSON array of titles only." },
        { role: "user", content: prompt }
      ],
      temperature: 0.3
    });

    const responseText = extractText(aiResponse);
    const jsonMatch = responseText.match(/\[[\s\S]*?\]/);
    if (!jsonMatch) {
      console.warn("Cloudflare AI failed to extract titles");
      return [];
    }

    const titles = JSON.parse(jsonMatch[0]);
    if (!Array.isArray(titles)) return [];

    return titles
      .filter(t => typeof t === 'string' && t.length >= 2 && t.length <= 80)
      .map(t => ({ title: t.trim(), mentions: 1 }))
      .slice(0, 20);

  } catch (error) {
    console.error("Title extraction error:", error);
    return [];
  }
}

async function extractTitlesWithOpenAI(text: string, env: Env, contentType?: string): Promise<TitleMention[]> {
  try {
    const truncatedText = text.substring(0, 6000); // OpenAI can handle more context

    // Determine the specific content type being requested
    let extractionPrompt = "Extract all movie, TV show, and anime titles mentioned in this text.";
    if (contentType) {
      if (contentType.includes('documentary')) {
        extractionPrompt = "Extract ONLY documentary titles mentioned in this text. Do NOT include narrative films, TV shows, or anime unless they are documentaries.";
      } else if (contentType.includes('anime')) {
        extractionPrompt = "Extract ONLY anime titles mentioned in this text. Focus on Japanese animation.";
      }
    }

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `You are an expert at extracting movie, TV show, and anime titles from Reddit discussions and web content.

CRITICAL RULES:
- Extract ONLY actual media titles (movies, TV shows, anime, documentaries)
- Each title must be a real, released piece of media
- NEVER extract: Reddit post fragments, usernames, subreddit names, sentences, quotes from posts, URLs, markdown text
- NEVER extract titles that start with: "I", "The s", "ve", "m", "t", "Official", "Rotten", "Should You"
- NEVER extract titles containing: "episode discussion", "last episode", "write-up", "Part One", "movie I", "show I", "anime I"
- If a title seems like a sentence fragment or post text, SKIP IT
- Return ONLY the clean title names

Return a JSON object with a "titles" array of strings.`
          },
          {
            role: "user",
            content: `${extractionPrompt}

EXAMPLES OF WHAT TO EXTRACT:
✓ "Magi: The Labyrinth of Magic"
✓ "Wolf's Rain"
✓ "Planet Earth"
✓ "Samurai Champloo"

EXAMPLES OF WHAT NOT TO EXTRACT:
✗ "s last episode discussion"
✗ "I went to the Yuru Camp locations"
✗ "Official Teaser"
✗ "ve been keeping track of every movie I"
✗ "Rotten Tomatoes"

Text to analyze:
${truncatedText}

Return JSON object with "titles" array containing ONLY actual media titles.`
          }
        ],
        temperature: 0.2,
        max_tokens: 1000,
        response_format: { type: "json_object" }
      })
    });

    if (!response.ok) {
      const error = await response.text();
      console.error("OpenAI API error:", error);
      return [];
    }

    const data = await response.json() as any;
    const content = data.choices?.[0]?.message?.content;
    if (!content) return [];

    const parsed = JSON.parse(content);
    const titles = parsed.titles || parsed.results || parsed.movies || parsed.shows || parsed.anime || [];

    if (!Array.isArray(titles)) {
      // Maybe it returned an object with a titles key
      const possibleArrays = Object.values(parsed).filter(v => Array.isArray(v));
      if (possibleArrays.length > 0) {
        return (possibleArrays[0] as string[])
          .filter(t => typeof t === 'string' && t.length >= 2 && t.length <= 80)
          .map(t => ({ title: t.trim(), mentions: 1 }))
          .slice(0, 30);
      }
      return [];
    }

    return titles
      .filter(t => typeof t === 'string' && t.length >= 2 && t.length <= 80)
      .map(t => ({ title: t.trim(), mentions: 1 }))
      .slice(0, 30);

  } catch (error) {
    console.error("OpenAI title extraction error:", error);
    return [];
  }
}

async function scoreRelevance(
  titles: TitleMention[],
  originalPrompt: string,
  env: Env
): Promise<TitleMention[]> {
  // If we don't have OpenAI, skip relevance scoring (too expensive with Cloudflare AI)
  if (!env.OPENAI_API_KEY || titles.length === 0) {
    return titles;
  }

  try {
    const titleList = titles.map(t => t.title).join('\n');

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `You are a relevance scorer. Given a user's query and a list of recommended titles, score each title's relevance to the query on a scale of 0-10.

A score of:
- 9-10: Highly relevant, directly matches the query intent
- 7-8: Relevant, matches most aspects of the query
- 5-6: Somewhat relevant, tangentially related
- 3-4: Weakly relevant, barely related
- 0-2: Not relevant, unrelated to the query

Return JSON object with "scores" array: [{"title": "Title Name", "score": 8}, ...]`
          },
          {
            role: "user",
            content: `User query: "${originalPrompt}"

Titles to score:
${titleList}

Score each title's relevance to the query. Return JSON only.`
          }
        ],
        temperature: 0.2,
        max_tokens: 2000,
        response_format: { type: "json_object" }
      })
    });

    if (!response.ok) {
      console.error("Relevance scoring failed:", response.status);
      return titles; // Return all titles if scoring fails
    }

    const data = await response.json() as any;
    const content = data.choices?.[0]?.message?.content;
    if (!content) return titles;

    const parsed = JSON.parse(content);
    const scores = parsed.scores || [];

    // Create a map of title -> score
    const scoreMap = new Map<string, number>();
    for (const item of scores) {
      if (item.title && typeof item.score === 'number') {
        scoreMap.set(item.title.toLowerCase(), item.score);
      }
    }

    // Filter titles with score >= 5 (somewhat relevant or higher)
    const relevant = titles.filter(mention => {
      const score = scoreMap.get(mention.title.toLowerCase());
      if (score === undefined) return true; // Keep if not scored
      return score >= 5; // Filter out low relevance scores
    });

    const filtered = titles.length - relevant.length;
    if (filtered > 0) {
      console.log(`🔍 Filtered out ${filtered} irrelevant titles (score < 5)`);
    }

    return relevant;
  } catch (error) {
    console.error("Relevance scoring error:", error);
    return titles; // Return all titles if scoring fails
  }
}

function extractTitlesFromText(text: string): TitleMention[] {
  const titles: TitleMention[] = [];

  // ONLY extract quoted titles - be EXTREMELY conservative
  const patterns = [
    /"([^"]+)"/g,  // Double quoted titles
    /'([^']+)'/g,  // Single quoted titles
  ];

  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(text)) !== null) {
      const title = match[1].trim();

      // STRICT filtering - must pass ALL these checks
      const isValidLength = title.length >= 2 && title.length <= 50; // Max 50 chars
      const noUrls = !title.includes('http') && !title.includes('www.');
      const noSpecialChars = !title.includes('@') && !title.includes('\n') && !title.includes('[') && !title.includes(']');
      const notTooLong = title.split(' ').length <= 7; // Max 7 words
      const noJunk = !title.toLowerCase().startsWith('i ') &&
                     !title.toLowerCase().startsWith('i\'m ') &&
                     !title.toLowerCase().startsWith('it ') &&
                     !title.toLowerCase().includes('reddit.com') &&
                     !title.includes('##') &&
                     !title.includes('*');

      if (isValidLength && noUrls && noSpecialChars && notTooLong && noJunk) {
        titles.push({ title, mentions: 1 });
      }
    }
  }

  return titles;
}

function extractPhrases(text: string): string[] {
  const phrases: string[] = [];
  const lowerText = text.toLowerCase();

  // Common descriptive phrases in recommendations
  const keywords = [
    'cozy', 'wholesome', 'healing', 'dark', 'gritty', 'upbeat', 'slow burn',
    'fast paced', 'emotional', 'funny', 'sad', 'intense', 'relaxing',
    'thought-provoking', 'action-packed', 'character-driven', 'plot-driven',
    'atmospheric', 'nostalgic', 'modern', 'classic', 'underrated', 'hidden gem',
    'must watch', 'binge-worthy', 'slice of life', 'coming of age'
  ];

  for (const keyword of keywords) {
    if (lowerText.includes(keyword)) {
      phrases.push(keyword);
    }
  }

  return phrases;
}

function buildContextSummary(titles: TitleMention[], phrases: string[]): string {
  const topTitles = titles.slice(0, 5).map(t => t.title).join(', ');
  const topPhrases = phrases.slice(0, 5).join(', ');

  let summary = '';
  if (topTitles) {
    summary += `Frequently mentioned: ${topTitles}. `;
  }
  if (topPhrases) {
    summary += `Community describes this vibe as: ${topPhrases}.`;
  }

  return summary || 'Limited community context available.';
}

// ============= ENHANCED RERANK WITH WEB CONTEXT =============

async function handleRerankV2(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json<RerankV2Request>();
    if (!body.prompt || !Array.isArray(body.candidates)) {
      return json({ error: "Invalid payload" }, 400);
    }
    if (!body.candidates.length) {
      return json({ ranked: [], rejected: [] });
    }

    // Prefer OpenAI if available (much better), fallback to Cloudflare
    let result;
    if (env.OPENAI_API_KEY) {
      console.log("Using OpenAI for reranking (better quality)");
      try {
        result = await rerankWithOpenAI(body.prompt, body.candidates, body.webContext, env);
      } catch (error) {
        console.error("OpenAI rerank failed, falling back to Cloudflare:", error);
        result = await rerankWithCloudflare(body.prompt, body.candidates, body.webContext, env);
      }
    } else {
      console.log("Using Cloudflare AI for reranking (no OpenAI key)");
      result = await rerankWithCloudflare(body.prompt, body.candidates, body.webContext, env);
    }

    return json(result);
  } catch (error) {
    console.error("Rerank V2 error", error);
    return json({ error: "rerank failure" }, 500);
  }
}

async function rerankWithCloudflare(
  prompt: string,
  candidates: RerankV2Request["candidates"],
  webContext: WebContextResponse | undefined,
  env: Env
): Promise<RerankV2Response> {
  const curatorPrompt = buildCuratorPrompt(prompt, candidates, webContext);

  const aiResponse = await env.AI.run(LLM_MODEL, {
    messages: [
      { role: "system", content: CURATOR_SYSTEM_PROMPT },
      { role: "user", content: curatorPrompt }
    ]
  });

  const text = extractText(aiResponse);
  const result = safeParseJSON(text);

  if (!result || !Array.isArray(result.ranked)) {
    // Fallback: return all candidates with score 3.0
    return {
      ranked: candidates.map(c => ({
        identifier: c.identifier,
        score: 3.0,
        reasoning: "Cloudflare AI parsing failed",
        tags: []
      })),
      rejected: []
    };
  }

  return result as RerankV2Response;
}

async function rerankWithOpenAI(
  prompt: string,
  candidates: RerankV2Request["candidates"],
  webContext: WebContextResponse | undefined,
  env: Env
): Promise<RerankV2Response> {
  const curatorPrompt = buildCuratorPrompt(prompt, candidates, webContext);

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${env.OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: CURATOR_SYSTEM_PROMPT },
        { role: "user", content: curatorPrompt }
      ],
      temperature: 0.3,
      max_tokens: 3000,
      response_format: { type: "json_object" }
    })
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error: ${response.status} ${errorText}`);
  }

  const data = await response.json() as any;
  const content = data.choices?.[0]?.message?.content;

  if (!content) {
    throw new Error("No content in OpenAI response");
  }

  const result = JSON.parse(content);

  if (!result || !Array.isArray(result.ranked)) {
    throw new Error("Invalid JSON structure from OpenAI");
  }

  return result as RerankV2Response;
}

const CURATOR_SYSTEM_PROMPT = `You are an expert film/TV curator with deep knowledge of cinema, TV, anime, documentaries, and pop culture.

Your job: Score each candidate based on how well it matches the user's request. Use your world knowledge:
- You know Samurai Champloo has a Nujabes hip-hop soundtrack
- You know Ken Burns makes iconic American documentaries
- You know "cozy anime" means slice-of-life like Laid-Back Camp, Nichijou
- You know "snow leopard documentary" should return nature/wildlife content like Planet Earth
- You know community favorites and hidden gems

CRITICAL FILTERING RULES:
1. If request asks for "anime", REJECT all non-anime candidates (look for Animation genre)
2. If request asks for "documentary", REJECT all non-documentary candidates
3. If request specifies a genre, heavily penalize candidates missing that genre
4. If candidate is completely off-topic, REJECT it entirely

SCORING RUBRIC (0-5 for each):
1. Topical Fit (35%): Does the content actually match the subject matter?
2. Tone Match (20%): Does the vibe/mood match (cozy, gritty, upbeat, somber)?
3. Form Match (15%): Right format (anime vs live-action, documentary vs narrative)?
4. Community Consensus (20%): Is this frequently recommended for this vibe?
5. Era/Setting (10%): Right time period or cultural context?

APPLY BOOSTS:
- +0.5 if title appears in community recommendations
- +0.3 if community phrases align with the vibe
- REJECT if completely wrong (e.g., live-action for "anime" request, narrative for "documentary" request)

OUTPUT: Return ONLY valid JSON, no prose before or after.
{
  "ranked": [
    {
      "identifier": "movie:123",
      "score": 4.8,
      "reasoning": "Brief explanation",
      "tags": ["relevant", "tags"]
    }
  ],
  "rejected": [
    {"identifier": "movie:999", "reason": "Why it doesn't fit"}
  ]
}

CONSTRAINT: Only score the provided candidates. Never invent titles.`;

function buildCuratorPrompt(
  userPrompt: string,
  candidates: RerankV2Request["candidates"],
  webContext?: WebContextResponse
): string {
  let prompt = `User Request: "${userPrompt}"\n\n`;

  if (webContext && webContext.recommendedTitles.length > 0) {
    const topTitles = webContext.recommendedTitles
      .slice(0, 10)
      .map(t => `${t.title} (mentioned ${t.mentions}x)`)
      .join(', ');
    prompt += `Community Recommendations: ${topTitles}\n`;

    if (webContext.communityPhrases.length > 0) {
      prompt += `Community Vibe Words: ${webContext.communityPhrases.join(', ')}\n`;
    }

    if (webContext.contextSummary) {
      prompt += `Context: ${webContext.contextSummary}\n`;
    }
    prompt += '\n';
  }

  prompt += 'Candidates to score (from TMDB):\n';
  for (const candidate of candidates.slice(0, 40)) { // Limit to 40 to stay within token limits
    prompt += `\n${candidate.identifier} - "${candidate.title}"`;
    if (candidate.year) prompt += ` (${candidate.year})`;
    prompt += `\nType: ${candidate.mediaType}`;
    if (candidate.genres && candidate.genres.length > 0) {
      prompt += `\nGenres: ${candidate.genres.join(', ')}`;
    }
    if (candidate.overview) {
      prompt += `\nOverview: ${candidate.overview.substring(0, 200)}`;
    }
    prompt += '\n';
  }

  prompt += '\n\nScore each candidate using the rubric. Return JSON only.';
  return prompt;
}

type LLMRequest = {
  prompt: string;
};

type LLMResponse = {
  media_types: string[];
  include_keywords: string[];
  exclude_keywords: string[];
  genres: string[];
  tone: string[];
  year_min: number;
  year_max: number;
  languages: string[];
  search_queries?: string[];
};

type RerankRequest = {
  prompt: string;
  candidates: {
    identifier: string;
    title: string;
    overview: string;
    genres: string[];
    mediaType: string;
    year?: string | null;
  }[];
};

type RerankScore = {
  identifier: string;
  score: number;
};

type WebContextRequest = {
  prompt: string;
  contentType?: string; // "anime", "documentary", "movie", "tv", etc.
  intent?: {
    animeOnly?: boolean;
  };
};

type TitleMention = {
  title: string;
  mentions: number;
};

type WebContextResponse = {
  recommendedTitles: TitleMention[];
  communityPhrases: string[];
  sources: string[];
  contextSummary: string;
};

type RedditPost = {
  title: string;
  text: string;
  url: string;
  score: number;
};

type WebResult = {
  title: string;
  snippet: string;
  url: string;
};

type RerankV2Request = {
  prompt: string;
  candidates: {
    identifier: string;
    title: string;
    overview: string;
    genres: string[];
    mediaType: string;
    year?: string | null;
  }[];
  webContext?: WebContextResponse;
};

type RankedCandidate = {
  identifier: string;
  score: number;
  reasoning: string;
  tags: string[];
};

type RejectedCandidate = {
  identifier: string;
  reason: string;
};

type RerankV2Response = {
  ranked: RankedCandidate[];
  rejected: RejectedCandidate[];
};
