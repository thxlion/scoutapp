//
//  Models.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import Foundation

// MARK: - LLM Filters

struct LLMFilters: Codable {
  var mediaTypes: [String]?;
  var includeKeywords: [String]?;
  var excludeKeywords: [String]?;
  var genres: [String]?;
  var tone: [String]?;
  var yearMin: Int?;
  var yearMax: Int?;
  var languages: [String]?;
  var searchQueries: [String]?;
}

// MARK: - TMDB + Candidates

enum MediaType: String, Codable, CaseIterable {
  case movie;
  case tv;
}

struct Candidate: Identifiable, Hashable {
  let id: Int;
  let type: MediaType;
  let title: String;
  let posterPath: String?;
  let year: String?;
  let overview: String;
  let genreIDs: [Int];
  let popularity: Double;
  let vote: Double;
  let originCountry: [String];
  let originalLanguage: String;
  var scores: Scores;

  var identifier: String {
    "\(type.rawValue):\(id)";
  }

  init(from tmdb: TMDBMedia, type: MediaType) {
    self.id = tmdb.id;
    self.type = type;
    self.title = tmdb.title ?? tmdb.name ?? "Untitled";
    self.posterPath = tmdb.posterPath;
    self.year = Candidate.yearString(primary: tmdb.releaseDate, secondary: tmdb.firstAirDate);
    self.overview = tmdb.overview ?? "";
    self.genreIDs = tmdb.genreIds ?? [];
    self.popularity = tmdb.popularity ?? 0;
    self.vote = tmdb.voteAverage ?? 0;
    self.originCountry = tmdb.originCountry ?? [];
    self.originalLanguage = tmdb.originalLanguage ?? "";
    self.scores = Scores(metaOverlap: 0, popularityCap: 0, animeBoost: 0, semantic: 0, penalty: 0, communityBoost: 0);
  }

  private static func yearString(primary: String?, secondary: String?) -> String? {
    let formatter = DateFormatter();
    formatter.dateFormat = "yyyy-MM-dd";
    if let primary, let date = formatter.date(from: primary) {
      return String(primary.prefix(4));
    } else if let secondary, let _ = formatter.date(from: secondary) {
      return String(secondary.prefix(4));
    }
    return nil;
  }
}

extension Candidate {
  var posterURL: URL? {
    Config.posterURL(path: posterPath);
  }
}

struct Scores: Codable, Hashable {
  var metaOverlap: Double;
  var popularityCap: Double;
  var animeBoost: Double;
  var semantic: Double;
  var penalty: Double;
  var communityBoost: Double;

  var total: Double {
    max(0, 0.30 * metaOverlap + 0.20 * popularityCap + 0.35 * semantic + animeBoost + communityBoost - penalty);
  }
}

// MARK: - TMDB Responses

struct GenreListResponse: Decodable {
  let genres: [Genre];
}

struct Genre: Decodable {
  let id: Int;
  let name: String;
}

struct DiscoverResponse: Decodable {
  let page: Int;
  let results: [TMDBMedia];
  let totalPages: Int?; // Optional for search endpoints
}

struct TMDBMedia: Decodable {
  let id: Int;
  let title: String?;
  let name: String?;
  let posterPath: String?;
  let overview: String?;
  let genreIds: [Int]?;
  let popularity: Double?;
  let voteAverage: Double?;
  let releaseDate: String?;
  let firstAirDate: String?;
  let originCountry: [String]?;
  let originalLanguage: String?;
}

// MARK: - Watch Providers

struct WatchProvidersResponse: Codable {
  struct Country: Codable {
    let flatrate: [Provider]?;
    let rent: [Provider]?;
    let buy: [Provider]?;
  }

  struct Provider: Codable, Hashable {
    let providerName: String;
  }

  let results: [String: Country];
}

struct KeywordSearchResponse: Decodable {
  struct Keyword: Decodable {
    let id: Int;
    let name: String;
  }
  let results: [Keyword];
}

// MARK: - Rerank

struct RerankRequest: Codable {
  struct Candidate: Codable {
    let identifier: String;
    let title: String;
    let overview: String;
    let genres: [String];
    let mediaType: String;
    let year: String?;
  }
  let prompt: String;
  let candidates: [Candidate];
}

struct RerankResponse: Codable {
  struct Item: Codable {
    let identifier: String;
    let score: Double;
  }
  let scores: [Item];
}

// MARK: - Web Context

struct WebContextResponse: Codable {
  struct TitleMention: Codable {
    let title: String;
    let mentions: Int;
  }
  let recommendedTitles: [TitleMention];
  let communityPhrases: [String];
  let sources: [String];
  let contextSummary: String;
}

// MARK: - Enhanced Rerank V2

struct RerankV2Response: Codable {
  struct RankedCandidate: Codable {
    let identifier: String;
    let score: Double;
    let reasoning: String;
    let tags: [String];
  }

  struct RejectedCandidate: Codable {
    let identifier: String;
    let reason: String;
  }

  let ranked: [RankedCandidate];
  let rejected: [RejectedCandidate];
}
