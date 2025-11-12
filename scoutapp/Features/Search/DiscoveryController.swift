import Foundation
import Observation

struct SearchResult: Identifiable, Codable, Hashable {
  let id: UUID
  let prompt: String
  let responseText: String
  let suggestions: [Suggestion]
  let timestamp: Date

  init(id: UUID = UUID(), prompt: String, responseText: String, suggestions: [Suggestion], timestamp: Date = Date()) {
    self.id = id
    self.prompt = prompt
    self.responseText = responseText
    self.suggestions = suggestions
    self.timestamp = timestamp
  }
}

@MainActor
@Observable
final class DiscoveryController {
  var prompt: String = ""
  var isSearching = false
  var errorMessage: String?
  var searchHistory: [SearchResult] = []
  var pendingPrompt: String?

  private let defaults = UserDefaults.standard
  private let historyKey = "discoverySearchHistory"

  init() {
    loadState()
  }

  func search() {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    isSearching = true
    errorMessage = nil
    let searchPrompt = trimmed
    pendingPrompt = trimmed
    prompt = ""
    Task {
      do {
        let response = try await APIClient.shared.suggest(prompt: searchPrompt)
        await MainActor.run {
          let result = SearchResult(
            prompt: searchPrompt,
            responseText: response.responseText,
            suggestions: response.suggestions
          )
          self.searchHistory.append(result)
          self.pendingPrompt = nil
          self.isSearching = false
          self.saveState()
        }
      } catch {
        await MainActor.run {
          self.errorMessage = "Something went wrong. Please try again."
          self.pendingPrompt = nil
          self.isSearching = false
        }
        print("Suggest error", error)
      }
    }
  }

  private func saveState() {
    if let encoded = try? JSONEncoder().encode(searchHistory) {
      defaults.set(encoded, forKey: historyKey)
    }
  }

  private func loadState() {
    if let data = defaults.data(forKey: historyKey),
       let decoded = try? JSONDecoder().decode([SearchResult].self, from: data) {
      searchHistory = decoded
    }
  }
}
