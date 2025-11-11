import Foundation

final class APIClient {
  static let shared = APIClient()
  private init() {}

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  func suggest(prompt: String) async throws -> SuggestionResponse {
    var request = URLRequest(url: Config.workerBase.appending(path: "/api/suggest"))
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    struct Payload: Encodable { let prompt: String }
    request.httpBody = try JSONEncoder().encode(Payload(prompt: prompt))
    let (data, response) = try await URLSession.shared.data(for: request)
    try Self.validate(response: response)
    return try decode(SuggestionResponse.self, from: data, endpoint: "/api/suggest")
  }

  private static func validate(response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
    do {
      return try decoder.decode(T.self, from: data)
    } catch {
      if let raw = String(data: data, encoding: .utf8) {
        print("⚠️ Decode failed for \(endpoint): \(error)\nPayload: \(raw)")
      } else {
        print("⚠️ Decode failed for \(endpoint): \(error)")
      }
      throw error
    }
  }
}
