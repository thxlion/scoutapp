import SwiftUI

struct HomeView: View {
  @State private var controller = DiscoveryController()
  @State private var selectedSuggestion: Suggestion?

  var body: some View {
    @Bindable var controller = controller

    NavigationStack {
      ZStack(alignment: .bottom) {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text("What are we feeling like?")
              .font(.system(size: 34, weight: .bold))
              .foregroundColor(.primary)
              .padding(.top, 32)

            conversationSection(controller: controller)
            suggestionsSection(controller: controller)
            Spacer(minLength: 120)
          }
          .padding(.horizontal, 24)
        }

        inputBar(controller: controller)
      }
      .background(Color(.systemBackground))
      .navigationTitle("SCOUT")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(item: $selectedSuggestion) { suggestion in
        SuggestionDetailView(suggestion: suggestion, responseText: controller.responseText)
      }
    }
  }

  @ViewBuilder
  private func conversationSection(controller: DiscoveryController) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let lastPrompt = controller.lastPrompt {
        bubble(text: lastPrompt, alignment: .trailing, color: Color(.systemGray6), textColor: .primary)
      } else {
        Text("Tell me a vibe. ‘Anime with a cat’ or ‘Something like Aftersun in Spain.’")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if controller.isSearching {
        bubble(text: "Percolating…", alignment: .leading, color: Color.blue.opacity(0.15), textColor: .blue)
          .overlay(alignment: .trailing) {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.blue)
              .padding(.trailing, 12)
          }
      } else if let error = controller.errorMessage {
        bubble(text: error, alignment: .leading, color: Color.red.opacity(0.15), textColor: .red)
      }
      // Hide GPT response text - just show cards
      // else if let response = controller.responseText, !response.isEmpty {
      //   bubble(text: response, alignment: .leading, color: Color.blue, textColor: .white)
      // }
    }
  }

  @ViewBuilder
  private func suggestionsSection(controller: DiscoveryController) -> some View {
    if controller.suggestions.isEmpty {
      EmptyView()
    } else {
      SuggestionGridView(suggestions: controller.suggestions) { suggestion in
        selectedSuggestion = suggestion
      }
      .animation(.spring(duration: 0.3), value: controller.suggestions)
    }
  }

  private func inputBar(controller: DiscoveryController) -> some View {
    HStack(spacing: 12) {
      TextField("Search for a movie or show", text: $controller.prompt, axis: .vertical)
        .textFieldStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
          RoundedRectangle(cornerRadius: 28)
            .fill(Color(.systemGray6))
        )

      Button(action: controller.search) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(.blue)
      }
      .disabled(controller.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .background(.ultraThinMaterial)
  }

  private func bubble(text: String, alignment: HorizontalAlignment, color: Color, textColor: Color) -> some View {
    HStack {
      if alignment == .trailing { Spacer(minLength: 40) }
      Text(text)
        .foregroundStyle(textColor)
        .padding(16)
        .background(
          RoundedRectangle(cornerRadius: 22)
            .fill(color)
        )
      if alignment == .leading { Spacer(minLength: 40) }
    }
  }
}

struct SuggestionGridView: View {
  let suggestions: [Suggestion]
  let onSelect: (Suggestion) -> Void

  private let columns = [
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16)
  ]

  var body: some View {
    LazyVGrid(columns: columns, spacing: 16) {
      ForEach(suggestions) { suggestion in
        Button {
          onSelect(suggestion)
        } label: {
          SuggestionCard(suggestion: suggestion)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

struct SuggestionCard: View {
  let suggestion: Suggestion

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AsyncImage(url: suggestion.posterURL) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        case .failure:
          placeholder
        case .empty:
          placeholder.overlay { ProgressView().tint(.white) }
        @unknown default:
          placeholder
        }
      }
      .frame(height: 220)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)

      Text(suggestion.title)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(2)

      if !suggestion.displayYear.isEmpty {
        Text(suggestion.displayYear)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 16)
      .fill(Color(.systemGray4))
      .frame(maxWidth: .infinity)
  }
}

struct SuggestionDetailView: View {
  let suggestion: Suggestion
  let responseText: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        AsyncImage(url: suggestion.posterURL) { phase in
          switch phase {
          case .success(let image):
            image.resizable().scaledToFit()
          case .failure:
            Color(.systemGray5)
          case .empty:
            Color(.systemGray5).overlay { ProgressView() }
          @unknown default:
            Color(.systemGray5)
          }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))

        Text(suggestion.title)
          .font(.title.bold())

        HStack(spacing: 12) {
          if !suggestion.displayYear.isEmpty {
            Text(suggestion.displayYear)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          if let rating = suggestion.tmdb?.voteAverage {
            HStack(spacing: 4) {
              Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
              Text(String(format: "%.1f", rating))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
        }

        if !suggestion.genres.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(suggestion.genres, id: \.self) { genre in
                Text(genre)
                  .font(.footnote.weight(.medium))
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(
                    Capsule()
                      .fill(Color.blue.opacity(0.15))
                  )
                  .foregroundStyle(.blue)
              }
            }
          }
        }

        if !suggestion.overview.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Overview")
              .font(.headline)
            Text(suggestion.overview)
          }
        }

        if let providers = suggestion.providers {
          ProviderSection(providers: providers)
        }
      }
      .padding(24)
    }
    .presentationDetents([.large])
  }
}

struct ProviderSection: View {
  let providers: ProviderInfo

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Where to watch")
        .font(.headline)

      providerRow(label: "Included", providers: providers.flatrate)
      providerRow(label: "Rent", providers: providers.rent)
      providerRow(label: "Buy", providers: providers.buy)

      if providers.flatrate == nil, providers.rent == nil, providers.buy == nil {
        Text("We couldn’t find streaming info right now.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func providerRow(label: String, providers: [Provider]?) -> some View {
    if let providers, !providers.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text(label)
          .font(.subheadline.weight(.semibold))
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(providers, id: \.self) { provider in
              Text(provider.name)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                  Capsule()
                    .fill(Color(.systemGray6))
                )
            }
          }
        }
      }
    }
  }
}

#Preview {
  HomeView()
}
