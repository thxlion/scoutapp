import Foundation
import Observation

@MainActor
@Observable
final class DiscoveryController {
  var prompt: String = ""
  var lastPrompt: String?
  var isSearching = false
  var errorMessage: String?
  var responseText: String?
  var suggestions: [Suggestion] = []

  func search() {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    isSearching = true
    errorMessage = nil
    lastPrompt = trimmed
    prompt = ""
    Task {
      do {
        let response = try await APIClient.shared.suggest(prompt: trimmed)
        await MainActor.run {
          self.responseText = response.responseText
          self.suggestions = response.suggestions
          self.isSearching = false
        }
      } catch {
        await MainActor.run {
          self.errorMessage = "Something went wrong. Please try again."
          self.isSearching = false
        }
        print("Suggest error", error)
      }
    }
  }
}
