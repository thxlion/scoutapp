import Foundation

enum MediaType: String, Codable {
  case movie
  case tv
  case unknown
}

struct SuggestionResponse: Codable {
  let prompt: String
  let responseText: String
  let suggestions: [Suggestion]
}

struct Suggestion: Identifiable, Codable, Hashable {
  let id: String
  let title: String
  let mediaType: MediaType
  let year: String?
  let tmdb: TMDBInfo?

  var posterURL: URL? {
    guard let path = tmdb?.posterPath else { return nil }
    return Config.posterURL(path: path)
  }

  var overview: String { tmdb?.overview ?? "" }
  var genres: [String] { tmdb?.genres ?? [] }
  var providers: ProviderInfo? { tmdb?.providers }
  var displayYear: String { year ?? tmdb?.year ?? "" }
}

struct TMDBInfo: Codable, Hashable {
  let tmdbId: Int
  let title: String
  let mediaType: MediaType
  let year: String?
  let overview: String
  let posterPath: String?
  let backdropPath: String?
  let voteAverage: Double?
  let popularity: Double?
  let genres: [String]
  let providers: ProviderInfo?
}

struct ProviderInfo: Codable, Hashable {
  let flatrate: [Provider]?
  let rent: [Provider]?
  let buy: [Provider]?
}

struct Provider: Codable, Hashable {
  let name: String
}
