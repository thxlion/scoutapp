interface Env {
  OPENAI_API_KEY: string;
  TMDB_V4: string;
  OMDB_API_KEY: string;
}

const TMDB_BASE = "https://api.themoviedb.org/3";
const OMDB_BASE = "https://www.omdbapi.com";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/api/health") {
      return json({ ok: true });
    }

    if (url.pathname === "/api/suggest" && request.method === "POST") {
      return handleSuggest(request, env);
    }

    return new Response("Not found", { status: 404 });
  }
};

async function handleSuggest(request: Request, env: Env): Promise<Response> {
  try {
    const body = await request.json() as { prompt: string };
    const { prompt } = body;
    if (!prompt || typeof prompt !== "string") {
      return json({ error: "prompt required" }, 400);
    }

    const responseText = await generateGPTResponse(prompt, env);
    const extracted = await extractTitles(prompt, responseText, env);
    const suggestions = await enrichWithTMDB(extracted, env);

    return json({ prompt, responseText, suggestions });
  } catch (error) {
    console.error("suggest error", error);
    return json({ error: "suggestion failure" }, 500);
  }
}

async function generateGPTResponse(prompt: string, env: Env): Promise<string> {
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0.3, // Lower for more consistent results
      messages: [
        {
          role: "system",
          content: "You are Scout, a passionate film and TV curator. When recommending media, always provide 5-8 specific titles with brief context about each. Respond conversationally but be comprehensive like ChatGPT."
        },
        { role: "user", content: prompt }
      ]
    })
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`OpenAI error ${response.status}: ${body}`);
  }

  const data = await response.json() as any;
  const text = data.choices?.[0]?.message?.content;
  if (!text) throw new Error("Missing GPT response");
  return text.trim();
}

async function extractTitles(prompt: string, responseText: string, env: Env): Promise<ExtractedTitle[]> {
  let extracted: ExtractedTitle[] = [];

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: `Extract ONLY the actual names of movies, TV shows, anime, or documentaries from the assistant reply. Return them as JSON.

Critical Rules:
- Extract ONLY proper titles/names of watchable media (e.g., "Naruto", "Breaking Bad", "Inception")
- DO NOT extract concepts, themes, features, or descriptive words (e.g., "quirks", "powers", "magic", "breathing styles")
- DO NOT extract single common words unless clearly a title
- Return clean title text (no markdown ** or *, no extra quotes)
- If year is mentioned, include it; otherwise omit
- Use media_type: "movie", "tv", or "documentary"

Respond with JSON: {"titles": [{"title":"...", "media_type":"...", "year":"..."}]}`
        },
        {
          role: "user",
          content: `User prompt: ${prompt}\nAssistant reply: ${responseText}`
        }
      ]
    })
  });

  if (response.ok) {
    try {
      const data = await response.json() as any;
      const content = data.choices?.[0]?.message?.content;
      if (content) {
        const parsed = JSON.parse(content);
        const titles = parsed.titles;
        if (Array.isArray(titles)) {
          extracted = titles
            .filter((entry: any) => {
              if (typeof entry.title !== "string" || !entry.title.trim().length) return false;
              const cleaned = entry.title.replace(/^[\*_]+|[\*_]+$/g, "").trim();
              // Filter out likely concept words: too short or common descriptor words
              if (cleaned.length < 2) return false;
              // Filter out common concept words that aren't titles
              const lower = cleaned.toLowerCase();
              const conceptWords = ['quirks', 'powers', 'magic', 'abilities', 'styles', 'breathing', 'nen', 'stands', 'haki', 'chakra', 'jutsu'];
              if (conceptWords.includes(lower)) return false;
              return true;
            })
            .map((entry: any, index: number) => ({
              id: crypto.randomUUID(),
              title: entry.title.replace(/^[\*_]+|[\*_]+$/g, "").trim(), // Clean markdown
              mediaType: normalizeMediaType(entry.media_type),
              year: entry.year ? String(entry.year) : undefined,
              order: index
            }));
        }
      }
    } catch (error) {
      console.warn("extract parse error", error);
    }
  } else {
    console.warn("extract titles failed", await response.text());
  }

  // Fallback extraction disabled - JSON extraction should be sufficient
  // and fallback was causing text fragments to be treated as titles

  // Smart deduplication: remove duplicates and very similar titles
  const deduplicated: ExtractedTitle[] = [];
  const seenNormalized = new Set<string>();

  for (const entry of extracted) {
    // Normalize for comparison: remove subtitle, articles, special chars, lowercase
    const normalizedTitle = removeArticle(removeSubtitle(entry.title))
      .toLowerCase()
      .replace(/[^\w\s]/g, '') // Remove all special chars
      .replace(/\s+/g, ' ')     // Normalize whitespace
      .trim();

    // Skip if we've seen this exact normalized title
    if (seenNormalized.has(normalizedTitle)) {
      continue;
    }

    // Check if we already have a very similar title
    const isDuplicate = deduplicated.some(existing => {
      const existingNormalized = removeArticle(removeSubtitle(existing.title))
        .toLowerCase()
        .replace(/[^\w\s]/g, '')
        .replace(/\s+/g, ' ')
        .trim();

      // Check if one is substring of the other (with some wiggle room)
      if (normalizedTitle.length >= 4 && existingNormalized.length >= 4) {
        if (normalizedTitle.includes(existingNormalized) || existingNormalized.includes(normalizedTitle)) {
          return true;
        }
      }

      // Check string similarity
      const similarity = stringSimilarity(normalizedTitle, existingNormalized);
      return similarity > 0.8; // Lower threshold, more aggressive
    });

    if (!isDuplicate) {
      deduplicated.push(entry);
      seenNormalized.add(normalizedTitle);
    }
  }

  return deduplicated
    .sort((a, b) => a.order - b.order)
    .slice(0, 25);
}

function extractFallbackTitles(text: string): string[] {
  const cleaned = text.replace(/[\*_`]/g, "");
  const titles: string[] = [];

  const quoteRegex = /“([^”]+)”|"([^"\n]+)"|'([^'\n]+)'/g;
  let match: RegExpExecArray | null;
  while ((match = quoteRegex.exec(cleaned)) !== null) {
    const title = (match[1] || match[2] || match[3] || "").trim();
    if (title.length > 0) titles.push(title);
  }

  for (const line of cleaned.split(/\n+/)) {
    const trimmed = line.trim();
    if (/^[-*\d\.]+/.test(trimmed)) {
      const title = trimmed.replace(/^[-*\d\.\s]+/, "").trim();
      if (title.length > 0) titles.push(title);
    }
  }

  return titles
    .map(title => title.replace(/[^\w\s:'!\/\-&]/g, "").trim()) // Keep /, -, &
    .filter(Boolean);
}

async function enrichWithTMDB(entries: ExtractedTitle[], env: Env): Promise<SuggestionResult[]> {
  const results: SuggestionResult[] = [];
  for (const entry of entries) {
    let tmdb = await findTMDBMatch(entry, env);

    // Fallback to OMDb if TMDB fails
    if (!tmdb) {
      console.log(`  → Trying OMDb fallback for: "${entry.title}"`);
      tmdb = await findOMDbMatch(entry, env);
    }

    results.push({
      id: entry.id,
      title: entry.title,
      mediaType: entry.mediaType,
      year: entry.year,
      tmdb
    });
  }
  return results;
}

// ===== Title Normalization Helpers =====

function removeArticle(title: string): string {
  return title.replace(/^(The|A|An)\s+/i, "").trim();
}

function removeSubtitle(title: string): string {
  return title.split(/[:—-]/)[0].trim();
}

// ===== String Similarity Helpers =====

function levenshteinDistance(str1: string, str2: string): number {
  const matrix: number[][] = [];
  for (let i = 0; i <= str2.length; i++) matrix[i] = [i];
  for (let j = 0; j <= str1.length; j++) matrix[0][j] = j;

  for (let i = 1; i <= str2.length; i++) {
    for (let j = 1; j <= str1.length; j++) {
      if (str2.charAt(i - 1) === str1.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }
  return matrix[str2.length][str1.length];
}

function stringSimilarity(str1: string, str2: string): number {
  const longer = str1.length > str2.length ? str1 : str2;
  const shorter = str1.length > str2.length ? str2 : str1;
  if (longer.length === 0) return 1.0;
  const distance = levenshteinDistance(longer, shorter);
  return (longer.length - distance) / longer.length;
}

// ===== TMDB Search with Fallbacks =====

async function findTMDBMatch(entry: ExtractedTitle, env: Env): Promise<TMDBInfo | undefined> {
  try {
    // Build search strategies
    const strategies: Array<{ endpoint: string; query: string; description: string }> = [
      { endpoint: "/search/multi", query: entry.title, description: "exact title" },
    ];

    // Strategy 2: Specific media type if known
    if (entry.mediaType === "movie" || entry.mediaType === "tv") {
      strategies.push({
        endpoint: `/search/${entry.mediaType}`,
        query: entry.title,
        description: `specific ${entry.mediaType}`
      });
    }

    // Strategy 3: Without leading article
    const withoutArticle = removeArticle(entry.title);
    if (withoutArticle !== entry.title) {
      strategies.push({
        endpoint: "/search/multi",
        query: withoutArticle,
        description: "without article"
      });
    }

    // Strategy 4: Without subtitle
    const withoutSubtitle = removeSubtitle(entry.title);
    if (withoutSubtitle !== entry.title && withoutSubtitle.length > 2) {
      strategies.push({
        endpoint: "/search/multi",
        query: withoutSubtitle,
        description: "without subtitle"
      });
    }

    // Strategy 5: With year appended
    if (entry.year) {
      strategies.push({
        endpoint: "/search/multi",
        query: `${entry.title} ${entry.year}`,
        description: "with year"
      });
    }

    // Try each strategy
    console.log(`Searching TMDB for: "${entry.title}" (type: ${entry.mediaType}, year: ${entry.year || "unknown"})`);

    for (let i = 0; i < strategies.length; i++) {
      const strategy = strategies[i];
      console.log(`  Strategy ${i + 1}/${strategies.length}: ${strategy.description} → ${strategy.endpoint}?query=${strategy.query}`);

      const search = await tmdbRequest(strategy.endpoint, { query: strategy.query, include_adult: "false" }, env);
      const results: any[] = search.results || [];

      if (results.length === 0) {
        console.log(`    ↳ No results`);
        continue;
      }

      const best = pickBestResultWithSimilarity(results, entry);
      if (best) {
        const resultTitle = best.title || best.name || "unknown";
        console.log(`    ↳ Found: "${resultTitle}" (id: ${best.id})`);

        const mediaType: MediaKind = best.media_type === "tv" ? "tv" : "movie";
        const year = best.release_date?.slice(0, 4) || best.first_air_date?.slice(0, 4);
        const genres = (best.genre_ids || []).map((id: number) => TMDB_GENRES[id]).filter(Boolean) as string[];
        const providers = await fetchProviders(mediaType, best.id, env);

        return {
          tmdbId: best.id,
          mediaType,
          title: best.title || best.name || entry.title,
          year,
          overview: best.overview || "",
          posterPath: best.poster_path || undefined,
          backdropPath: best.backdrop_path || undefined,
          voteAverage: best.vote_average,
          popularity: best.popularity,
          genres,
          providers
        };
      } else {
        console.log(`    ↳ Results found but no good match (similarity too low)`);
      }
    }

    console.warn(`  ✗ All ${strategies.length} strategies failed for: "${entry.title}"`);
    return undefined;
  } catch (error) {
    console.warn("TMDB match error", error);
    return undefined;
  }
}

function pickBestResultWithSimilarity(results: any[], entry: ExtractedTitle, threshold = 0.8) {
  if (!results.length) return null;

  // Normalize the search title for better matching
  const normalizeForMatch = (title: string) => {
    return removeArticle(title)
      .toLowerCase()
      .replace(/[^\w\s]/g, '') // Remove special chars
      .replace(/\s+/g, ' ')
      .trim();
  };

  const normalizedEntry = normalizeForMatch(entry.title);

  const candidates = results.map(result => {
    const resultTitle = result.title || result.name || "";
    const normalizedResult = normalizeForMatch(resultTitle);

    // Calculate similarity on normalized titles
    const similarity = stringSimilarity(normalizedEntry, normalizedResult);

    const resultYear = result.release_date?.slice(0, 4) || result.first_air_date?.slice(0, 4);
    const yearMatch = entry.year && resultYear === entry.year;
    const yearClose = entry.year && resultYear && Math.abs(parseInt(resultYear) - parseInt(entry.year)) <= 1;

    // Filter by media type if specified
    const typeMatch = !entry.mediaType || entry.mediaType === "unknown" ||
                      result.media_type === entry.mediaType ||
                      (entry.mediaType === "tv" && result.media_type === "tv") ||
                      (entry.mediaType === "movie" && result.media_type === "movie");

    // Score: similarity (0-1) + exact year bonus (0.3) + close year (0.1) + popularity (0-0.1)
    let score = similarity;
    if (typeMatch) score += 0.05; // Small bonus for type match
    if (yearMatch) score += 0.3;   // Big bonus for exact year
    else if (yearClose) score += 0.1; // Small bonus for year ±1
    score += Math.min((result.popularity || 0) / 1000, 0.1);

    return { result, similarity, score, yearMatch, typeMatch };
  });

  candidates.sort((a, b) => b.score - a.score);

  // Only return if similarity is above threshold
  if (candidates[0].similarity >= threshold) {
    return candidates[0].result;
  }

  return null;
}

// ===== OMDb Fallback =====

async function findOMDbMatch(entry: ExtractedTitle, env: Env): Promise<TMDBInfo | undefined> {
  try {
    const url = new URL(OMDB_BASE);
    url.searchParams.set("apikey", env.OMDB_API_KEY);
    url.searchParams.set("t", entry.title);
    if (entry.year) {
      url.searchParams.set("y", entry.year);
    }
    url.searchParams.set("plot", "short");

    const response = await fetch(url);
    if (!response.ok) {
      console.warn(`OMDb API error: ${response.status}`);
      return undefined;
    }

    const data = await response.json() as any;
    if (data.Response === "False") {
      console.log(`    ↳ OMDb: No match found`);
      return undefined;
    }

    // Map OMDb response to our TMDBInfo format
    const mediaType: MediaKind = data.Type === "series" ? "tv" : data.Type === "movie" ? "movie" : "unknown";
    const posterPath = data.Poster && data.Poster !== "N/A" ? data.Poster : undefined;

    // OMDb uses full URLs for posters, we'll store them as-is
    // Note: We'll need to handle this differently in the response
    console.log(`    ↳ OMDb: Found "${data.Title}" (${data.Year})`);

    return {
      tmdbId: 0, // OMDb doesn't have TMDB IDs
      mediaType,
      title: data.Title,
      year: data.Year,
      overview: data.Plot !== "N/A" ? data.Plot : "",
      posterPath, // This is a full URL from OMDb, not a TMDB path
      backdropPath: undefined,
      voteAverage: data.imdbRating !== "N/A" ? parseFloat(data.imdbRating) : undefined,
      popularity: undefined,
      genres: data.Genre && data.Genre !== "N/A" ? data.Genre.split(", ") : [],
      providers: undefined
    };
  } catch (error) {
    console.warn("OMDb match error", error);
    return undefined;
  }
}

async function fetchProviders(mediaType: MediaKind, tmdbId: number, env: Env): Promise<ProviderInfo | undefined> {
  try {
    const data = await tmdbRequest(`/${mediaType}/${tmdbId}/watch/providers`, {}, env);
    const gb = data.results?.GB;
    if (!gb) return undefined;
    return {
      flatrate: normalizeProviders(gb.flatrate),
      rent: normalizeProviders(gb.rent),
      buy: normalizeProviders(gb.buy)
    };
  } catch (error) {
    console.warn("provider fetch error", error);
    return undefined;
  }
}

function normalizeProviders(list: any[] | undefined) {
  if (!Array.isArray(list)) return undefined;
  return list.map(item => ({ name: item.provider_name })).filter(p => p.name);
}

async function tmdbRequest(path: string, query: Record<string, string>, env: Env) {
  const url = new URL(`${TMDB_BASE}${path}`);
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value);
  }
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${env.TMDB_V4}`,
      Accept: "application/json"
    }
  });
  if (!response.ok) {
    const body = await response.text();
    console.error("TMDB error", response.status, body);
    throw new Error(`TMDB ${response.status}`);
  }
  return response.json();
}

function normalizeMediaType(value: any): MediaKind {
  if (typeof value !== "string") return "unknown";
  const lower = value.toLowerCase();
  if (lower.includes("tv")) return "tv";
  if (lower.includes("movie") || lower.includes("film")) return "movie";
  return "unknown";
}

const TMDB_GENRES: Record<number, string> = {
  28: "Action",
  12: "Adventure",
  16: "Animation",
  35: "Comedy",
  80: "Crime",
  99: "Documentary",
  18: "Drama",
  10751: "Family",
  14: "Fantasy",
  36: "History",
  27: "Horror",
  10402: "Music",
  9648: "Mystery",
  10749: "Romance",
  878: "Science Fiction",
  10770: "TV Movie",
  53: "Thriller",
  10752: "War",
  37: "Western"
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" }
  });
}

// ===== Types =====

type MediaKind = "movie" | "tv" | "unknown";

type ExtractedTitle = {
  id: string;
  title: string;
  mediaType: MediaKind;
  year?: string;
  order: number;
};

type ProviderInfo = {
  flatrate?: { name: string }[];
  rent?: { name: string }[];
  buy?: { name: string }[];
};

type TMDBInfo = {
  tmdbId: number;
  mediaType: MediaKind;
  title: string;
  year?: string;
  overview: string;
  posterPath?: string;
  backdropPath?: string;
  voteAverage?: number;
  popularity?: number;
  genres: string[];
  providers?: ProviderInfo;
};

type SuggestionResult = {
  id: string;
  title: string;
  mediaType: MediaKind;
  year?: string;
  tmdb?: TMDBInfo;
};
