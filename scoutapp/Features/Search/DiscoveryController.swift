//
//  DiscoveryController.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import Foundation
import Observation
import NaturalLanguage

@MainActor
@Observable
final class DiscoveryController {
  enum Spectrum: Int {
    case tight = -1;
    case normal = 0;
    case wide = 1;

    var yearPadding: Int {
      switch self {
      case .tight: return 0;
      case .normal: return 6;
      case .wide: return 12;
      }
    }

    var strictnessPenalty: Double {
      switch self {
      case .tight: return 0.2;
      case .normal: return 0.1;
      case .wide: return 0.0;
      }
    }

    func closer() -> Spectrum {
      switch self {
      case .tight: return .tight;
      case .normal: return .tight;
      case .wide: return .normal;
      }
    }

    func wider() -> Spectrum {
      switch self {
      case .tight: return .normal;
      case .normal: return .wide;
      case .wide: return .wide;
      }
    }
  }

  struct Intent: CustomStringConvertible {
    var animeOnly: Bool = false;

    var description: String {
      "Intent(animeOnly: \(animeOnly))";
    }
  }

  var prompt: String = "";
  var lastPrompt: String?;
  var isSearching = false;
  var errorMessage: String?;
  var isReady = false;
  var spectrum: Spectrum = .normal;
  var visibleCandidates: [Candidate] = [];

  private var filters: LLMFilters?;
  private var filterGenreIDs: [MediaType: Set<Int>] = [:];
  private var pool: [Candidate] = [];
  private var identifiers: Set<String> = [];
  private var intent = Intent();
  private var displayCount = 8;
  private var moviePage = 1;
  private var tvPage = 1;
  private var rerankScores: [String: Double] = [:];
  private var isReranking = false;
  private var promptEmbedding: [Double]?;
  private var embeddingCache: [String: [Double]] = [:];
  private var embeddingFailures: Set<String> = [];
  private var webContext: WebContextResponse?;

  init() {
    Task {
      try? await GenreStore.shared.ensureLoaded();
      await MainActor.run {
        self.isReady = true;
      }
    };
  }

  func search() {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines);
    guard !trimmed.isEmpty else { return; }
    Task {
      await executeSearch(text: trimmed);
    };
  }

  func showMore() {
    Task {
      await loadMoreIfNeeded();
    };
  }

  func refineCloser() {
    spectrum = spectrum.closer();
    rescorePool();
  }

  func refineWider() {
    spectrum = spectrum.wider();
    rescorePool();
  }

  private func executeSearch(text: String) async {
    isSearching = true;
    errorMessage = nil;
    lastPrompt = text;
    pool = [];
    identifiers = [];
    displayCount = 8;
    moviePage = 1;
    tvPage = 1;
    rerankScores = [:];
    embeddingCache = [:];
    embeddingFailures = [];
    webContext = nil;
    communityRecommendedIDs = [];
    intent = inferIntent(from: text);
    promptEmbedding = EmbeddingHelper.vector(for: text);
    do {
      try await GenreStore.shared.ensureLoaded();

      // Fetch filters and web context in parallel
      async let filtersTask = APIClient.shared.llmFilters(prompt: text);
      filters = try await filtersTask;

      logDebugInfo(filters: filters, webContext: nil);
      mapFilterGenres();

      // Determine content type for web context
      let contentType = determineContentType(from: text, filters: filters);

      // Fetch web context with proper content type
      webContext = try? await APIClient.shared.getWebContext(
        prompt: text,
        contentType: contentType,
        intent: ["animeOnly": intent.animeOnly]
      );

      if let webContext {
        print("🌐 Web Context:");
        print("  - Sources: \(webContext.sources.joined(separator: ", "))");
        print("  - Top Recommendations: \(webContext.recommendedTitles.prefix(5).map { "\($0.title) (\($0.mentions)x)" }.joined(separator: ", "))");
      }

      // HYBRID STRATEGY: Merge web context + LLM queries together
      print("🔀 Using HYBRID strategy (web context + LLM queries combined)");

      // Search web context titles (if available)
      if let webContext, !webContext.recommendedTitles.isEmpty {
        print("🌐 Searching \(webContext.recommendedTitles.count) web-recommended titles...");
        await searchWebContextTitles(webContext);
      }

      // ALWAYS add LLM search queries (don't wait for web context to fail)
      if let queries = filters?.searchQueries, !queries.isEmpty {
        print("🔍 Adding \(queries.count) LLM-generated search queries...");
        await searchWithLLMQueries(queries);
      }

      // FALLBACK: If still not enough results, add discover
      if pool.count < 10 {
        print("📊 Adding discover results as FINAL FALLBACK");
        try await loadMinimalDiscoverResults();
      }

      isSearching = false;
    } catch {
      self.errorMessage = "Something went wrong. Please try again.";
      self.isSearching = false;
      print("Search error: \(error)");
    }
  }

  private func loadMoreIfNeeded() async {
    guard !isSearching else { return; }
    if displayCount < pool.count {
      displayCount += 8;
      updateVisible();
      return;
    }
    // If we've exhausted the pool, fetch a few more from discover as fallback
    do {
      try await loadMinimalDiscoverResults();
      displayCount += 8;
      updateVisible();
    } catch {
      errorMessage = "Could not load more results.";
      print("Show more error: \(error)");
    }
  }

  private func loadNextBatch(reset: Bool) async throws {
    guard let filters else { return; }
    if reset {
      pool = [];
      identifiers = [];
    }
    let mediaTypes = desiredMediaTypes(from: filters);
    var fetched: [Candidate] = [];
    for type in mediaTypes {
      let page = type == .movie ? moviePage : tvPage;
      let query = try buildQuery(for: type, filters: filters, page: page);
      let response = try await APIClient.shared.discover(type: type, query: query);

      // ONLY take top 10 results from discover to reduce garbage
      let candidates = response.results.prefix(10).map { Candidate(from: $0, type: type) };
      fetched.append(contentsOf: candidates);

      if type == .movie {
        moviePage += 1;
      } else {
        tvPage += 1;
      }
    }
    appendToPool(fetched);
    rescorePool();
  }

  private func appendToPool(_ candidates: [Candidate]) {
    for candidate in candidates {
      if identifiers.insert(candidate.identifier).inserted {
        pool.append(candidate);
      }
    }
  }

  private var communityRecommendedIDs: Set<String> = [];

  private func searchWithLLMQueries(_ queries: [String]) async {
    // Search TMDB with LLM-generated queries
    var foundCandidates: [Candidate] = [];

    // Get desired media types and genres from filters
    let desiredMediaTypes = filters?.mediaTypes?.compactMap { str -> MediaType? in
      switch str.lowercased() {
      case "movie": return .movie
      case "tv": return .tv
      default: return nil
      }
    } ?? [.movie, .tv]

    let filterGenreIDs = self.filterGenreIDs
    let isDocumentarySearch = lastPrompt?.lowercased().contains("documentary") ?? false;
    let documentaryGenreId = 99; // TMDB genre ID for documentary

    print("🔍 Searching TMDB with \(queries.count) LLM-generated queries...");
    print("📌 Media types filter: \(desiredMediaTypes.map { $0.rawValue }.joined(separator: ", "))")
    if isDocumentarySearch {
      print("📹 Documentary mode: Will filter for documentaries only");
    }
    if let genres = filters?.genres, !genres.isEmpty {
      print("🎭 Genre filter: \(genres.joined(separator: ", "))")
    }

    for (index, query) in queries.prefix(7).enumerated() { // Take up to 7 queries
      do {
        print("  [\(index+1)/\(min(queries.count, 7))] Query: '\(query)'");
        let response = try await APIClient.shared.searchMulti(query);

        var candidates = response.results.prefix(10).compactMap { media -> Candidate? in
          let type: MediaType
          if let mediaType = media.title, !mediaType.isEmpty {
            type = .movie;
          } else if let _ = media.name {
            type = .tv;
          } else {
            return nil;
          }

          // Filter by media type immediately
          guard desiredMediaTypes.contains(type) else {
            return nil
          }

          return Candidate(from: media, type: type);
        };

        // Filter for documentaries if needed
        if isDocumentarySearch {
          candidates = candidates.filter { candidate in
            candidate.genreIDs.contains(documentaryGenreId);
          };
        }

        // Filter by requested genres if any
        if !filterGenreIDs.isEmpty {
          candidates = candidates.filter { candidate in
            // Check if candidate has at least one of the requested genres
            let genreSet = filterGenreIDs[candidate.type] ?? []
            if !genreSet.isEmpty {
              return !Set(candidate.genreIDs).intersection(genreSet).isEmpty
            }
            return true
          }
        }

        if !candidates.isEmpty {
          print("    ✓ Found \(candidates.count) results: \(candidates.map { $0.title }.joined(separator: ", "))");
        } else {
          print("    ✗ No matching results for '\(query)' (filters active)");
        }
        foundCandidates.append(contentsOf: candidates);
      } catch {
        print("    ✗ Search failed: \(error)");
      }
    }

    if !foundCandidates.isEmpty {
      print("✅ Found \(foundCandidates.count) total candidates from LLM search queries");
      appendToPool(foundCandidates);
      rescorePool();
    } else {
      print("⚠️  No candidates found from LLM search queries");
    }
  }

  private func loadMinimalDiscoverResults() async throws {
    // Get minimal supplementary results from discover (only 5 per type)
    guard let filters else { return; }
    let mediaTypes = desiredMediaTypes(from: filters);
    var fetched: [Candidate] = [];

    for type in mediaTypes {
      let page = type == .movie ? moviePage : tvPage;
      let query = try buildQuery(for: type, filters: filters, page: page);
      let response = try await APIClient.shared.discover(type: type, query: query);

      // ONLY take top 5 as supplementary
      let candidates = response.results.prefix(5).map { Candidate(from: $0, type: type) };
      fetched.append(contentsOf: candidates);

      // Increment page counter for next time
      if type == .movie {
        moviePage += 1;
      } else {
        tvPage += 1;
      }
    }

    if !fetched.isEmpty {
      print("📊 Added \(fetched.count) supplementary results from discover (page \(moviePage-1)/\(tvPage-1))");
      appendToPool(fetched);
      rescorePool();
    }
  }

  private func searchValidWebContextTitles(_ webContext: WebContextResponse) async {
    // Filter for titles that look like actual media titles (not Reddit garbage)
    let validTitles = webContext.recommendedTitles.filter { mention in
      let title = mention.title
      // Must be reasonable length
      guard title.count >= 2 && title.count <= 60 else { return false }
      // Must not contain markdown or HTML
      guard !title.contains("##"), !title.contains("**"), !title.contains("["), !title.contains("]") else { return false }
      // Must not contain URLs
      guard !title.contains("http"), !title.contains("www."), !title.contains(".com") else { return false }
      // Must not start with sentence fragments
      let lower = title.lowercased()
      guard !lower.hasPrefix("i "), !lower.hasPrefix("i'm "), !lower.hasPrefix("it "), !lower.hasPrefix("the ") else { return false }
      // Must have reasonable word count (titles are usually 1-6 words)
      let wordCount = title.split(separator: " ").count
      guard wordCount >= 1 && wordCount <= 6 else { return false }
      return true
    }.prefix(10) // Only take top 10 valid titles

    guard !validTitles.isEmpty else {
      print("⚠️  No valid titles found in web context");
      return
    }

    var foundCandidates: [Candidate] = []
    print("🔍 Searching TMDB for \(validTitles.count) valid web context titles...")

    for (index, mention) in validTitles.enumerated() {
      do {
        print("  [\(index+1)/\(validTitles.count)] Searching for: '\(mention.title)' (\(mention.mentions)x mentions)")
        let response = try await APIClient.shared.searchMulti(mention.title)

        if let firstResult = response.results.first {
          let type: MediaType
          if let _ = firstResult.title, !firstResult.title!.isEmpty {
            type = .movie
          } else if let _ = firstResult.name {
            type = .tv
          } else {
            continue
          }

          let candidate = Candidate(from: firstResult, type: type)
          communityRecommendedIDs.insert(candidate.identifier)
          foundCandidates.append(candidate)
          print("    ✓ Found: \(candidate.title) (\(candidate.type.rawValue))")
        } else {
          print("    ✗ No TMDB results")
        }
      } catch {
        print("    ✗ Search failed: \(error)")
      }
    }

    if !foundCandidates.isEmpty {
      print("✅ Found \(foundCandidates.count) candidates from valid web context titles")
      appendToPool(foundCandidates)
      rescorePool()
    }
  }

  private func searchWebContextTitles(_ webContext: WebContextResponse) async {
    // Search TMDB for ALL web context titles (trust the LLM extraction)
    let titles = Array(webContext.recommendedTitles.prefix(30))
    guard !titles.isEmpty else {
      print("⚠️  No titles in web context");
      return
    }

    var foundCandidates: [Candidate] = []
    communityRecommendedIDs = []

    // Get desired media types and genres from filters
    let desiredMediaTypes = filters?.mediaTypes?.compactMap { str -> MediaType? in
      switch str.lowercased() {
      case "movie": return .movie
      case "tv": return .tv
      default: return nil
      }
    } ?? [.movie, .tv]

    let filterGenreIDs = self.filterGenreIDs
    let isDocumentarySearch = lastPrompt?.lowercased().contains("documentary") ?? false
    let documentaryGenreId = 99 // TMDB genre ID for documentary

    print("🔍 Searching TMDB for \(titles.count) web-recommended titles...")
    print("📌 Media types filter: \(desiredMediaTypes.map { $0.rawValue }.joined(separator: ", "))")
    if isDocumentarySearch {
      print("📹 Documentary mode: Will filter for documentaries only")
    }
    if let genres = filters?.genres, !genres.isEmpty {
      print("🎭 Genre filter: \(genres.joined(separator: ", "))")
    }

    for (index, mention) in titles.enumerated() {
      do {
        print("  [\(index+1)/\(titles.count)] Searching: '\(mention.title)' (\(mention.mentions)x mentions)")
        let response = try await APIClient.shared.searchMulti(mention.title)

        // Take top 5 results for each title search
        var candidates = response.results.prefix(5).compactMap { media -> Candidate? in
          let type: MediaType
          if let _ = media.title, !media.title!.isEmpty {
            type = .movie
          } else if let _ = media.name {
            type = .tv
          } else {
            return nil
          }

          // Filter by media type immediately
          guard desiredMediaTypes.contains(type) else {
            return nil
          }

          return Candidate(from: media, type: type)
        }

        // Filter for documentaries if needed
        if isDocumentarySearch {
          candidates = candidates.filter { candidate in
            candidate.genreIDs.contains(documentaryGenreId)
          }
        }

        // Filter by requested genres if any
        if !filterGenreIDs.isEmpty {
          candidates = candidates.filter { candidate in
            // Check if candidate has at least one of the requested genres
            let genreSet = filterGenreIDs[candidate.type] ?? []
            if !genreSet.isEmpty {
              return !Set(candidate.genreIDs).intersection(genreSet).isEmpty
            }
            return true
          }
        }

        // Take top 3 after filtering
        candidates = Array(candidates.prefix(3))

        for candidate in candidates {
          communityRecommendedIDs.insert(candidate.identifier)
          foundCandidates.append(candidate)
          print("    ✓ Found: \(candidate.title) (\(candidate.type.rawValue))")
        }

        if candidates.isEmpty {
          print("    ✗ No matching results (filters active)")
        }
      } catch {
        print("    ✗ Search failed: \(error)")
      }
    }

    if !foundCandidates.isEmpty {
      print("✅ Found \(foundCandidates.count) total candidates from web context")
      appendToPool(foundCandidates)
      rescorePool()
    } else {
      print("⚠️  No candidates found from web context")
    }
  }

  private func rescorePool() {
    guard let filters else { return; }
    let filterSets = filterGenreIDs;
    pool = pool.map { candidate in
      var updated = candidate;
      let genreSet = filterSets[candidate.type] ?? [];
      updated.scores = score(candidate: candidate,
                             filterGenres: genreSet,
                             filters: filters);
      return updated;
    }
    .sorted { $0.scores.total > $1.scores.total };
    updateVisible();
    Task {
      await rerankTopCandidates();
    }
  }

  private func updateVisible() {
    if pool.isEmpty {
      visibleCandidates = [];
    } else {
      let limit = min(displayCount, pool.count);
      visibleCandidates = Array(pool.prefix(limit));
    }
  }

  private func mapFilterGenres() {
    guard let filters else { return; }
    var map: [MediaType: Set<Int>] = [:];
    let requested = filters.genres ?? [];
    for type in MediaType.allCases {
      let ids = requested.compactMap { GenreStore.shared.genreID(named: $0, type: type) };
      if !ids.isEmpty {
        map[type] = Set(ids);
      }
    }
    filterGenreIDs = map;
  }

  private func desiredMediaTypes(from filters: LLMFilters) -> [MediaType] {
    let strings = filters.mediaTypes ?? ["movie", "tv"];
    let mapped = strings.compactMap { MediaType(rawValue: $0.lowercased()) };
    return mapped.isEmpty ? MediaType.allCases : mapped;
  }

  private func buildQuery(for type: MediaType, filters: LLMFilters, page: Int) throws -> [URLQueryItem] {
    var items: [URLQueryItem] = [
      URLQueryItem(name: "page", value: "\(page)"),
      URLQueryItem(name: "sort_by", value: "popularity.desc"),
      URLQueryItem(name: "region", value: Config.region)
    ];

    let baseMin = filters.yearMin ?? 1960;
    let baseMax = filters.yearMax ?? Calendar.current.component(.year, from: Date());
    let pad = spectrum.yearPadding;
    let minYear = max(1900, baseMin - pad);
    let maxYear = min(Calendar.current.component(.year, from: Date()), baseMax + pad);

    switch type {
    case .movie:
      items.append(contentsOf: [
        URLQueryItem(name: "primary_release_date.gte", value: "\(minYear)-01-01"),
        URLQueryItem(name: "primary_release_date.lte", value: "\(maxYear)-12-31")
      ]);
    case .tv:
      items.append(contentsOf: [
        URLQueryItem(name: "first_air_date.gte", value: "\(minYear)-01-01"),
        URLQueryItem(name: "first_air_date.lte", value: "\(maxYear)-12-31")
      ]);
    }

    var genreSet = filterGenreIDs[type] ?? [];
    if intent.animeOnly {
      genreSet.insert(16);
    }
    if !genreSet.isEmpty {
      let joined = genreSet.map(String.init).joined(separator: ",");
      items.append(URLQueryItem(name: "with_genres", value: joined));
    }

    if intent.animeOnly {
      if type == .tv {
        items.append(URLQueryItem(name: "with_origin_country", value: "JP"));
      } else {
        items.append(URLQueryItem(name: "with_original_language", value: "ja"));
      }
    } else if let languages = filters.languages, !languages.isEmpty {
      let normalized = languages.map { Self.languageCode(from: $0) }.filter { !$0.isEmpty };
      if let language = normalized.first {
        items.append(URLQueryItem(name: "with_original_language", value: language));
      }
    }

    return compact(items);
  }

  private func compact(_ items: [URLQueryItem]) -> [URLQueryItem] {
    items.filter { $0.value != nil };
  }

  private func score(candidate: Candidate,
                     filterGenres: Set<Int>,
                     filters: LLMFilters) -> Scores {
    let metaOverlap = overlapScore(candidate.genreIDs, filterGenres: filterGenres);
    let popularityCap = logScore(candidate.popularity);
    let animeBoost = animeScore(for: candidate);
    let penalty = spectrum.strictnessPenalty
      + animePenalty(for: candidate)
      + yearPenalty(for: candidate, filters: filters);
    let semantic = semanticScore(for: candidate);

    // MASSIVE boost for community-recommended titles
    let communityBoost = communityRecommendedIDs.contains(candidate.identifier) ? 5.0 : 0.0;

    return Scores(metaOverlap: metaOverlap,
                  popularityCap: popularityCap,
                  animeBoost: animeBoost,
                  semantic: semantic,
                  penalty: penalty,
                  communityBoost: communityBoost);
  }

  private func overlapScore(_ genres: [Int], filterGenres: Set<Int>) -> Double {
    guard !filterGenres.isEmpty else { return 0.3; }
    let set = Set(genres);
    let overlap = Double(set.intersection(filterGenres).count);
    return min(1.0, overlap / Double(filterGenres.count));
  }

  private func logScore(_ popularity: Double) -> Double {
    let value = log10(max(popularity, 1) + 1);
    return min(1.0, value / 2.0);
  }

  private func animeScore(for candidate: Candidate) -> Double {
    guard intent.animeOnly else { return 0; }
    let isAnimation = candidate.genreIDs.contains(16);
    let jpOrigin = candidate.originCountry.contains("JP") || candidate.originalLanguage == "ja";
    if isAnimation && jpOrigin { return 0.3; }
    if isAnimation || jpOrigin { return 0.15; }
    return 0;
  }

  private func animePenalty(for candidate: Candidate) -> Double {
    guard intent.animeOnly else { return 0; }
    let isAnimation = candidate.genreIDs.contains(16);
    let jpOrigin = candidate.originCountry.contains("JP") || candidate.originalLanguage == "ja";
    return (isAnimation || jpOrigin) ? 0 : 0.3;
  }

  private func yearPenalty(for candidate: Candidate, filters: LLMFilters) -> Double {
    guard let yearString = candidate.year, let year = Int(yearString) else { return 0; }
    let minYear = filters.yearMin ?? 1960;
    let maxYear = filters.yearMax ?? Calendar.current.component(.year, from: Date());
    let pad = spectrum.yearPadding;
    if year < minYear - pad || year > maxYear + pad {
      return 0.2;
    }
    return 0;
  }

  private func inferIntent(from text: String) -> Intent {
    let lowered = text.lowercased();
    var result = Intent();
    if lowered.contains("anime") {
      result.animeOnly = true;
    }
    return result;
  }

  private func rerankTopCandidates(force: Bool = false) async {
    guard !pool.isEmpty,
          let prompt = lastPrompt else { return; }
    let topCandidates = Array(pool.prefix(60)); // Increased from 30 to 60
    guard force || topCandidates.contains(where: { rerankScores[$0.identifier] == nil }) else {
      return;
    }
    guard !isReranking else { return; }
    isReranking = true;
    defer { isReranking = false; }
    let payload = topCandidates.map {
      RerankRequest.Candidate(
        identifier: $0.identifier,
        title: $0.title,
        overview: $0.overview,
        genres: GenreStore.shared.genreNames(for: $0.genreIDs),
        mediaType: $0.type.rawValue,
        year: $0.year
      );
    };
    do {
      // Use V2 endpoint with web context if available
      let response = try await APIClient.shared.rerankV2(prompt: prompt, candidates: payload, webContext: webContext);
      var updatedScores = rerankScores;

      // Process ranked candidates from V2 response
      for item in response.ranked {
        // Normalize score from 0-5 to 0-1 range for consistency
        let normalizedScore = item.score / 5.0;
        updatedScores[item.identifier] = normalizedScore;
      }

      // Give rejected candidates a very low score
      for item in response.rejected {
        updatedScores[item.identifier] = 0.01;
      }

      rerankScores = updatedScores;

      // Sort pool by rerank scores, with fallback to local scores
      pool.sort { lhs, rhs in
        let lhsScore = rerankScores[lhs.identifier];
        let rhsScore = rerankScores[rhs.identifier];
        if let lhsScore, let rhsScore, lhsScore != rhsScore {
          return lhsScore > rhsScore;
        } else if let lhsScore {
          return true;
        } else if let rhsScore {
          return false;
        } else {
          return lhs.scores.total > rhs.scores.total;
        }
      };
      updateVisible();
    } catch {
      print("Rerank V2 error: \(error), falling back to embedding-based rerank");
      // Fallback to old embedding-based rerank
      do {
        let response = try await APIClient.shared.rerank(prompt: prompt, candidates: payload);
        var updatedScores = rerankScores;
        for item in response.scores {
          updatedScores[item.identifier] = item.score;
        }
        rerankScores = updatedScores;
        pool.sort { lhs, rhs in
          let lhsScore = rerankScores[lhs.identifier];
          let rhsScore = rerankScores[rhs.identifier];
          if let lhsScore, let rhsScore, lhsScore != rhsScore {
            return lhsScore > rhsScore;
          } else if let lhsScore {
            return true;
          } else if let rhsScore {
            return false;
          } else {
            return lhs.scores.total > rhs.scores.total;
          }
        };
        updateVisible();
      } catch {
        print("Fallback rerank also failed: \(error)");
      }
    }
  }

  private func logDebugInfo(filters: LLMFilters?, webContext: WebContextResponse?) {
#if DEBUG
    guard let filters else { return; }
    if let prompt = lastPrompt {
      print("🧠 SCOUT Prompt: \(prompt)");
    }
    print("🧠 Filters: \(filters)");
    print("🧠 Intent: \(intent)");

    if let searchQueries = filters.searchQueries {
      print("🔍 LLM Search Queries: \(searchQueries.joined(separator: " | "))");
    }

    if let webContext {
      print("🌐 Web Context:");
      print("  - Sources: \(webContext.sources.joined(separator: ", "))");
      print("  - Top Recommendations: \(webContext.recommendedTitles.prefix(5).map { "\($0.title) (\($0.mentions)x)" }.joined(separator: ", "))");
      print("  - Community Phrases: \(webContext.communityPhrases.prefix(5).joined(separator: ", "))");
      print("  - Summary: \(webContext.contextSummary)");
    }
#endif
  }

  private func semanticScore(for candidate: Candidate) -> Double {
    guard let promptVector = promptEmbedding, !promptVector.isEmpty else {
      return 0;
    }
    if let cached = embeddingCache[candidate.identifier] {
      return cosineSimilarity(promptVector, cached);
    }
    if embeddingFailures.contains(candidate.identifier) {
      return 0;
    }
    let text = "\(candidate.title). \(candidate.overview)";
    guard let vector = EmbeddingHelper.vector(for: text) else {
      embeddingFailures.insert(candidate.identifier);
      return 0;
    }
    embeddingCache[candidate.identifier] = vector;
    return cosineSimilarity(promptVector, vector);
  }

  private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0; }
    var dot: Double = 0;
    var lhsNorm: Double = 0;
    var rhsNorm: Double = 0;
    for idx in 0..<lhs.count {
      let l = lhs[idx];
      let r = rhs[idx];
      dot += l * r;
      lhsNorm += l * l;
      rhsNorm += r * r;
    }
    guard lhsNorm > 0, rhsNorm > 0 else { return 0; }
    return max(-1, min(1, dot / (sqrt(lhsNorm) * sqrt(rhsNorm))));
  }

  private static func languageCode(from language: String) -> String {
    let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased();
    if trimmed.count == 2 { return trimmed; }
    return String(trimmed.prefix(2));
  }

  private func determineContentType(from text: String, filters: LLMFilters?) -> String? {
    let lowerText = text.lowercased();

    // Check intent first
    if intent.animeOnly || lowerText.contains("anime") {
      return "anime";
    }

    // Check for documentary
    if lowerText.contains("documentary") || lowerText.contains("documentaries") {
      return "documentary";
    }

    // Check filters for Documentary genre
    if let genres = filters?.genres, genres.contains("Documentary") {
      return "documentary";
    }

    // Check filters for Animation genre (might be anime)
    if let genres = filters?.genres, genres.contains("Animation") {
      // If also has Japanese language, likely anime
      if let languages = filters?.languages, languages.contains("Japanese") {
        return "anime";
      }
    }

    return nil; // General media search
  }
}

enum EmbeddingHelper {
  static func vector(for text: String) -> [Double]? {
    if #available(iOS 16.0, *), let sentence = NLEmbedding.sentenceEmbedding(for: .english) {
      if let vector = sentence.vector(for: text) {
        return vector;
      }
    }
    if let word = NLEmbedding.wordEmbedding(for: .english) {
      let tokens = tokenize(text);
      var aggregate: [Double] = [];
      var count = 0;
      for token in tokens {
        if let vector = word.vector(for: token) {
          if aggregate.isEmpty {
            aggregate = vector;
          } else {
            for idx in 0..<vector.count {
              aggregate[idx] += vector[idx];
            }
          }
          count += 1;
        }
      }
      if count > 0 {
        return aggregate.map { $0 / Double(count) };
      }
    }
    return nil;
  }

  private static func tokenize(_ text: String) -> [String] {
    text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty };
  }
}
