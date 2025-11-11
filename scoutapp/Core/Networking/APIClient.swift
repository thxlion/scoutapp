//
//  APIClient.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import Foundation

final class APIClient {
  static let shared = APIClient();
  private init() {}

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder();
    decoder.keyDecodingStrategy = .convertFromSnakeCase;
    return decoder;
  }();

  func llmFilters(prompt: String) async throws -> LLMFilters {
    var request = URLRequest(url: Config.workerBase.appending(path: "/api/llm"));
    request.httpMethod = "POST";
    request.addValue("application/json", forHTTPHeaderField: "Content-Type");
    request.httpBody = try JSONEncoder().encode(["prompt": prompt]);
    let (data, response) = try await URLSession.shared.data(for: request);
    try Self.validate(response: response);
    return try decode(LLMFilters.self, from: data, endpoint: "/api/llm");
  }

  func genreList(for type: MediaType) async throws -> GenreListResponse {
    try await requestTMDB("genre/\(type.rawValue)/list", query: [URLQueryItem(name: "language", value: "en-GB")]);
  }

  func discover(type: MediaType, query: [URLQueryItem]) async throws -> DiscoverResponse {
    try await requestTMDB("discover/\(type.rawValue)", query: query);
  }

  func watchProviders(for type: MediaType, id: Int) async throws -> WatchProvidersResponse {
    try await requestTMDB("\(type.rawValue)/\(id)/watch/providers");
  }

  func searchKeyword(_ query: String) async throws -> KeywordSearchResponse {
    let queryItems = [
      URLQueryItem(name: "query", value: query),
      URLQueryItem(name: "page", value: "1")
    ];
    return try await requestTMDB("search/keyword", query: queryItems);
  }

  func searchMulti(_ query: String) async throws -> DiscoverResponse {
    let queryItems = [
      URLQueryItem(name: "query", value: query),
      URLQueryItem(name: "page", value: "1")
    ];
    return try await requestTMDB("search/multi", query: queryItems);
  }

  func rerank(prompt: String, candidates: [RerankRequest.Candidate]) async throws -> RerankResponse {
    guard !candidates.isEmpty else {
      return RerankResponse(scores: []);
    }
    var request = URLRequest(url: Config.workerBase.appending(path: "/api/rerank"));
    request.httpMethod = "POST";
    request.addValue("application/json", forHTTPHeaderField: "Content-Type");
    let payload = RerankRequest(prompt: prompt, candidates: candidates);
    request.httpBody = try JSONEncoder().encode(payload);
    let (data, response) = try await URLSession.shared.data(for: request);
    try Self.validate(response: response);
    return try decode(RerankResponse.self, from: data, endpoint: "/api/rerank");
  }

  func getWebContext(prompt: String, contentType: String? = nil, intent: [String: Bool]? = nil) async throws -> WebContextResponse {
    var request = URLRequest(url: Config.workerBase.appending(path: "/api/web-context"));
    request.httpMethod = "POST";
    request.addValue("application/json", forHTTPHeaderField: "Content-Type");

    struct WebContextPayload: Encodable {
      let prompt: String;
      let contentType: String?;
      let intent: [String: Bool]?;
    }

    let payload = WebContextPayload(prompt: prompt, contentType: contentType, intent: intent);
    request.httpBody = try JSONEncoder().encode(payload);
    let (data, response) = try await URLSession.shared.data(for: request);
    try Self.validate(response: response);
    return try decode(WebContextResponse.self, from: data, endpoint: "/api/web-context");
  }

  func rerankV2(prompt: String, candidates: [RerankRequest.Candidate], webContext: WebContextResponse?) async throws -> RerankV2Response {
    guard !candidates.isEmpty else {
      return RerankV2Response(ranked: [], rejected: []);
    }
    var request = URLRequest(url: Config.workerBase.appending(path: "/api/rerank-v2"));
    request.httpMethod = "POST";
    request.addValue("application/json", forHTTPHeaderField: "Content-Type");

    struct Payload: Codable {
      let prompt: String;
      let candidates: [RerankRequest.Candidate];
      let webContext: WebContextResponse?;
    }

    let payload = Payload(prompt: prompt, candidates: candidates, webContext: webContext);
    request.httpBody = try JSONEncoder().encode(payload);
    let (data, response) = try await URLSession.shared.data(for: request);
    try Self.validate(response: response);
    return try decode(RerankV2Response.self, from: data, endpoint: "/api/rerank-v2");
  }

  private func requestTMDB<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
    var components = URLComponents(url: Config.workerBase.appending(path: "/api/tmdb/\(path)"), resolvingAgainstBaseURL: false)!;
    components.queryItems = query.isEmpty ? nil : query;
    guard let url = components.url else {
      throw URLError(.badURL);
    }
    let (data, response) = try await URLSession.shared.data(from: url);
    try Self.validate(response: response);
    return try decode(T.self, from: data, endpoint: path);
  }

  private static func validate(response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse);
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
    do {
      return try decoder.decode(T.self, from: data);
    } catch {
      if let raw = String(data: data, encoding: .utf8) {
        print("⚠️ Decode failed for \(endpoint): \(error)\nPayload: \(raw)");
      } else {
        print("⚠️ Decode failed for \(endpoint): \(error)");
      }
      throw error;
    }
  }
}
