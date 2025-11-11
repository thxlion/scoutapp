//
//  GenreStore.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import Foundation

@MainActor
final class GenreStore {
  static let shared = GenreStore();

  private var movieGenresByName: [String: Int] = [:];
  private var tvGenresByName: [String: Int] = [:];
  private var idToName: [Int: String] = [:];
  private var isLoaded = false;

  private init() {}

  func ensureLoaded() async throws {
    guard !isLoaded else { return; }
    async let movie = APIClient.shared.genreList(for: .movie);
    async let tv = APIClient.shared.genreList(for: .tv);
    let movieResponse = try await movie;
    let tvResponse = try await tv;
    movieGenresByName = Dictionary(uniqueKeysWithValues: movieResponse.genres.map { ($0.name.lowercased(), $0.id) });
    tvGenresByName = Dictionary(uniqueKeysWithValues: tvResponse.genres.map { ($0.name.lowercased(), $0.id) });
    for genre in movieResponse.genres + tvResponse.genres {
      idToName[genre.id] = genre.name;
    }
    isLoaded = true;
  }

  func genreID(named name: String, type: MediaType) -> Int? {
    let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased();
    switch type {
    case .movie:
      return movieGenresByName[key] ?? tvGenresByName[key];
    case .tv:
      return tvGenresByName[key] ?? movieGenresByName[key];
    }
  }

  func genreNames(for ids: [Int]) -> [String] {
    ids.compactMap { idToName[$0] };
  }
}
