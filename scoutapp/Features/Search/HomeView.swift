import SwiftUI

struct HomeView: View {
  @State private var controller = DiscoveryController()
  @State private var selectedSuggestion: Suggestion?
  @FocusState private var isInputFocused: Bool

  var body: some View {
    @Bindable var controller = controller

    NavigationStack {
      GeometryReader { geometry in
        ZStack(alignment: .bottom) {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              Text("What do you feel like watching?")
                .font(.system(size: 20, weight: .regular, design: .default))
                .tracking(-0.24)
                .lineSpacing(32 - 20) // Line height 32pt - font size 20pt
                .foregroundColor(Color(red: 0x91/255, green: 0x91/255, blue: 0x91/255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)

              conversationSection(controller: controller)
              suggestionsSection(controller: controller)
              Spacer(minLength: 120)
            }
            .padding(.horizontal, 20)
          }
          .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) }
          .simultaneousGesture(
            DragGesture().onChanged { _ in
              UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
          )

          inputBar(controller: controller)
        }
      }
      .background(Color(.systemBackground))
      .navigationBarHidden(true)
      .preferredColorScheme(.light)
      .sheet(item: $selectedSuggestion) { suggestion in
        SuggestionDetailView(suggestion: suggestion, responseText: controller.responseText)
      }
    }
  }

  @ViewBuilder
  private func conversationSection(controller: DiscoveryController) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      if let lastPrompt = controller.lastPrompt {
        bubble(text: lastPrompt, alignment: .trailing, color: Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF4/255), textColor: Color(red: 0x79/255, green: 0x79/255, blue: 0x79/255))
      }

      if controller.isSearching {
        LoadingBubbleView()
      } else if let error = controller.errorMessage {
        bubble(text: error, alignment: .leading, color: Color.red.opacity(0.15), textColor: .red)
      }
      // Hide GPT response text - just show cards
      // else if let response = controller.responseText, !response.isEmpty {
      //   bubble(text: response, alignment: .leading, color: Color(red: 0x3B/255, green: 0x90/255, blue: 0xFF/255), textColor: Color(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255))
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
    let hasText = !controller.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    return VStack(spacing: 0) {
      // Input field
      HStack(spacing: 0) {
        ZStack(alignment: .leading) {
          if controller.prompt.isEmpty {
            Text("Simply describe it ...")
              .font(.system(size: 15, weight: .regular, design: .default))
              .tracking(-0.24)
              .foregroundColor(Color(red: 0xB3/255, green: 0xB3/255, blue: 0xB3/255))
              .padding(.leading, 28)
          }
          TextField("", text: $controller.prompt)
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular, design: .default))
            .tracking(-0.24)
            .foregroundColor(Color.primary)
            .padding(.leading, 28)
            .padding(.trailing, isInputFocused ? 12 : 28)
            .focused($isInputFocused)
        }
        .frame(maxWidth: .infinity)

        if isInputFocused {
          Button(action: controller.search) {
            Image("send")
              .resizable()
              .renderingMode(.template)
              .scaledToFit()
              .frame(width: 16, height: 16)
              .foregroundStyle(.white)
              .frame(width: 32, height: 32)
              .background(
                Circle()
                  .fill(hasText ? Color(red: 0x3B/255, green: 0x90/255, blue: 0xFF/255) : Color(red: 0x79/255, green: 0x79/255, blue: 0x79/255))
              )
          }
          .disabled(!hasText)
          .padding(.trailing, 12)
        }
      }
      .frame(height: 56)
      .background(Color.white)
      .cornerRadius(28)
      .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 18)
      .padding(.horizontal, 20)
      .padding(.bottom, 20)
    }
  }

  private func bubble(text: String, alignment: HorizontalAlignment, color: Color, textColor: Color) -> some View {
    let estimatedLines = estimateNumberOfLines(text: text, maxWidth: 272 - 32, fontSize: 15)
    let cornerRadius: CGFloat = estimatedLines >= 3 ? 22 : 18

    return HStack {
      if alignment == .trailing { Spacer(minLength: 40) }
      Text(text)
        .font(.system(size: 15, weight: .regular, design: .default))
        .tracking(-0.24)
        .lineSpacing(20 - 15)
        .foregroundStyle(textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
        )
        .frame(maxWidth: 272, alignment: alignment == .trailing ? .trailing : .leading)
      if alignment == .leading { Spacer(minLength: 40) }
    }
  }

  private func estimateNumberOfLines(text: String, maxWidth: CGFloat, fontSize: CGFloat) -> Int {
    // Rough estimate: approximately 2.5 characters per 10pt at 15pt font size
    let charsPerLine = Int(maxWidth / (fontSize * 0.6))
    let totalChars = text.count
    let lines = max(1, (totalChars + charsPerLine - 1) / charsPerLine)
    return lines
  }
}

struct LoadingBubbleView: View {
  @State private var currentPhraseIndex = 0
  @State private var displayedText = ""
  @State private var isTyping = false

  private let phrases = [
    "Hunting gems",
    "Checking the archives",
    "Asking the film gods",
    "Searching the universe",
    "Plotting something"
  ]

  var body: some View {
    HStack {
      HStack(spacing: 8) {
        AnimatedDots()

        Text(displayedText)
          .font(.system(size: 15, weight: .regular, design: .default))
          .tracking(-0.24)
          .foregroundStyle(Color(red: 0x3B/255, green: 0x90/255, blue: 0xFF/255))
      }
      .frame(height: 44)

      Spacer(minLength: 40)
    }
    .onAppear {
      startTypingAnimation()
    }
  }

  private func startTypingAnimation() {
    typeText(phrases[currentPhraseIndex])
  }

  private func typeText(_ text: String) {
    displayedText = ""
    isTyping = true

    for (index, character) in text.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
        displayedText.append(character)

        if index == text.count - 1 {
          // Wait 2 seconds then move to next phrase
          DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            typeText(phrases[currentPhraseIndex])
          }
        }
      }
    }
  }
}

struct AnimatedDots: View {
  @State private var animationPhase = 0

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<3) { index in
        Circle()
          .fill(Color(red: 0x3B/255, green: 0x90/255, blue: 0xFF/255))
          .frame(width: 5, height: 5)
          .opacity(opacityForDot(index))
      }
    }
    .onAppear {
      Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
        animationPhase = (animationPhase + 1) % 3
      }
    }
  }

  private func opacityForDot(_ index: Int) -> Double {
    let adjusted = (index - animationPhase + 3) % 3
    switch adjusted {
    case 0: return 1.0
    case 1: return 0.6
    case 2: return 0.3
    default: return 1.0
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
