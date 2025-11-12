import SwiftUI

struct HomeView: View {
  @State private var controller = DiscoveryController()
  @State private var selectedResult: SearchResult?
  @FocusState private var isInputFocused: Bool

  var body: some View {
    @Bindable var controller = controller

    NavigationStack {
      GeometryReader { geometry in
        ZStack(alignment: .bottom) {
          ScrollViewReader { proxy in
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
                Spacer(minLength: 120)
                  .id("bottom")
              }
              .padding(.horizontal, 20)
            }
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) }
            .simultaneousGesture(
              DragGesture().onChanged { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
              }
            )
            .onChange(of: controller.isSearching) { _, isSearching in
              if isSearching {
                withAnimation {
                  proxy.scrollTo("bottom", anchor: .bottom)
                }
              }
            }
          }

          inputBar(controller: controller)
        }
      }
      .background(Color(.systemBackground))
      .navigationBarHidden(true)
      .preferredColorScheme(.light)
      .fullScreenCover(item: $selectedResult) { result in
        CarouselDetailView(suggestions: result.suggestions)
      }
    }
  }

  @ViewBuilder
  private func conversationSection(controller: DiscoveryController) -> some View {
    LazyVStack(alignment: .leading, spacing: 16) {
      // Display search history (limit to last 10 for performance)
      ForEach(controller.searchHistory.suffix(10)) { result in
        VStack(alignment: .leading, spacing: 16) {
          // User's prompt bubble
          bubble(text: result.prompt, alignment: .trailing, color: Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF4/255), textColor: Color(red: 0x79/255, green: 0x79/255, blue: 0x79/255))

          // Response bubble
          responseSummaryBubble(suggestions: result.suggestions)

          // Stacked cards preview
          StackedCardsPreview(suggestions: result.suggestions) {
            selectedResult = result
          }
          .padding(.top, -8)
        }
      }

      // Show pending prompt immediately
      if let pending = controller.pendingPrompt {
        bubble(text: pending, alignment: .trailing, color: Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF4/255), textColor: Color(red: 0x79/255, green: 0x79/255, blue: 0x79/255))
      }

      // Show loading state for current search
      if controller.isSearching {
        LoadingBubbleView()
      }

      // Show error if present
      if let error = controller.errorMessage {
        bubble(text: error, alignment: .leading, color: Color.red.opacity(0.15), textColor: .red)
      }
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
          Button(action: {
            controller.search()
            isInputFocused = false
          }) {
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

  private func responseSummaryBubble(suggestions: [Suggestion]) -> some View {
    let count = suggestions.count
    let mediaType = suggestions.first?.mediaType == .tv ? "Anime's" : "titles"

    var summaryText = "Found \(count) \(mediaType) that fit this vibe. "

    if count > 0 {
      summaryText += suggestions[0].title
    }
    if count > 1 {
      summaryText += ", \(suggestions[1].title)"
    }
    if count > 2 {
      let remaining = count - 2
      summaryText += ", and \(remaining) other\(remaining == 1 ? "" : "s")."
    } else if count <= 2 {
      summaryText += "."
    }

    return bubble(
      text: summaryText,
      alignment: .leading,
      color: Color(red: 0x3B/255, green: 0x90/255, blue: 0xFF/255),
      textColor: Color(red: 0xFF/255, green: 0xFF/255, blue: 0xFF/255)
    )
  }
}

struct LoadingBubbleView: View {
  @State private var currentPhraseIndex = 0
  @State private var displayedText = ""
  @State private var animationTask: Task<Void, Never>?

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
    .onDisappear {
      animationTask?.cancel()
    }
  }

  private func startTypingAnimation() {
    // Cancel any existing animation
    animationTask?.cancel()

    // Start a new animation task
    animationTask = Task {
      while !Task.isCancelled {
        await typeText(phrases[currentPhraseIndex])
        currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
      }
    }
  }

  private func typeText(_ text: String) async {
    displayedText = ""

    for character in text {
      guard !Task.isCancelled else { return }
      displayedText.append(character)
      try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
    }

    // Wait 2 seconds before next phrase
    guard !Task.isCancelled else { return }
    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
  }
}

struct AnimatedDots: View {
  @State private var currentPhase = 0

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<3) { index in
        Circle()
          .fill(Color(red: 0x3B/255, green: 0x90/255, blue: 0xFF/255))
          .frame(width: 5, height: 5)
          .opacity(opacityForDot(index))
          .animation(.easeInOut(duration: 0.6), value: currentPhase)
      }
    }
    .onAppear {
      Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
        currentPhase = (currentPhase + 1) % 3
      }
    }
  }

  private func opacityForDot(_ index: Int) -> Double {
    let phase = (index - currentPhase + 3) % 3
    switch phase {
    case 0: return 1.0
    case 1: return 0.6
    case 2: return 0.3
    default: return 1.0
    }
  }
}

struct StackedCardsPreview: View {
  let suggestions: [Suggestion]
  let onViewTapped: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      // Image stack container
      ZStack {
        // Left card - -15 degrees
        if suggestions.count > 0 {
          cardView(suggestion: suggestions[0])
            .rotationEffect(.degrees(-15), anchor: .center)
            .position(x: 15, y: 20)
            .zIndex(0)
        }

        // Middle card - no rotation
        if suggestions.count > 1 {
          cardView(suggestion: suggestions[1])
            .rotationEffect(.degrees(0))
            .position(x: 27, y: 16)
            .zIndex(1)
        }

        // Right card - 14 degrees
        if suggestions.count > 2 {
          cardView(suggestion: suggestions[2])
            .rotationEffect(.degrees(14), anchor: .center)
            .position(x: 35, y: 22)
            .zIndex(2)
        }
      }
      .frame(width: 52, height: 40)

      // View button
      Button(action: onViewTapped) {
        HStack(spacing: 6) {
          Text("View")
            .font(.system(size: 13, weight: .regular, design: .default))
            .tracking(-0.24)
            .lineSpacing(20 - 13)
            .foregroundColor(Color(red: 0x79/255, green: 0x79/255, blue: 0x79/255))

          // Circular icon container
          ZStack {
            Image("play")
              .resizable()
              .renderingMode(.template)
              .scaledToFit()
              .frame(width: 16, height: 16)
              .foregroundStyle(Color(red: 0x79/255, green: 0x79/255, blue: 0x79/255))
          }
          .frame(width: 24, height: 24)
          .background(
            Circle()
              .fill(Color.white)
              .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
          )
        }
        .frame(height: 40)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .background(Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF4/255))
        .cornerRadius(20)
      }
      .fixedSize()
    }
    .padding(.leading, 4)
  }

  private func cardView(suggestion: Suggestion) -> some View {
    AsyncImage(url: suggestion.posterURL) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
      case .failure:
        Color(.systemGray4)
      case .empty:
        Color(.systemGray4)
      @unknown default:
        Color(.systemGray4)
      }
    }
    .frame(width: 24, height: 32)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.32), radius: 4, x: 0, y: 1)
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

struct CarouselDetailView: View {
  let suggestions: [Suggestion]
  @State private var currentIndex: Int = 0
  @State private var dragOffset: CGFloat = 0
  @State private var coverFlowParameters = CoverFlowParameters()
  @State private var showCoverFlowHUD = false
  @Environment(\.dismiss) private var dismiss

  var currentSuggestion: Suggestion {
    return suggestions[min(max(0, currentIndex), suggestions.count - 1)]
  }

  private func coverFlowCarousel(width: CGFloat) -> some View {
    let size = coverFlowParameters.cardSize(for: width)
    return CoverFlowPagerView(
      suggestions: suggestions,
      currentIndex: $currentIndex,
      cardSize: size,
      parameters: coverFlowParameters
    )
    .frame(height: size.height)
  }

  private var movieDetailsContent: some View {
    VStack(spacing: 24) {
      // Title and metadata
      VStack(spacing: 12) {
        Text(currentSuggestion.title)
          .font(.system(size: 24, weight: .bold))
          .multilineTextAlignment(.center)

        HStack(spacing: 12) {
          if !currentSuggestion.displayYear.isEmpty {
            Text(currentSuggestion.displayYear)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          if let rating = currentSuggestion.tmdb?.voteAverage {
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
      }

      // Genres
      if !currentSuggestion.genres.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(currentSuggestion.genres, id: \.self) { genre in
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
          .padding(.horizontal, 24)
        }
      }

      // Overview
      if !currentSuggestion.overview.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Overview")
            .font(.headline)
          Text(currentSuggestion.overview)
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
      }

      // Providers
      if let providers = currentSuggestion.providers {
        ProviderSection(providers: providers)
          .padding(.horizontal, 24)
      }
    }
    .transition(.opacity.combined(with: .scale(scale: 0.98)))
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topTrailing) {
        sheetContent(width: geometry.size.width)
        hudOverlay()
      }
    }
  }

  @ViewBuilder
  private func sheetContent(width: CGFloat) -> some View {
    VStack(spacing: 0) {
      RoundedRectangle(cornerRadius: 2.5)
        .fill(Color(.systemGray3))
        .frame(width: 36, height: 5)
        .padding(.top, 8)

      ScrollView {
        VStack(spacing: 24) {
          coverFlowCarousel(width: width)

          movieDetailsContent
            .animation(.easeInOut(duration: 0.3), value: currentIndex)
        }
        .padding(.vertical, 24)
      }
    }
    .offset(y: dragOffset)
    .simultaneousGesture(
      DragGesture()
        .onChanged { value in
          if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
            let translation = value.translation.height
            let dampingFactor: CGFloat = 0.65
            let resistance = pow(translation, 0.85)
            dragOffset = resistance * dampingFactor
          }
        }
        .onEnded { value in
          let translation = value.translation.height
          if translation > 150 && abs(value.translation.height) > abs(value.translation.width) {
            dismiss()
          } else {
            withAnimation(.spring()) {
              dragOffset = 0
            }
          }
        }
    )
  }

  @ViewBuilder
  private func hudOverlay() -> some View {
#if DEBUG
    VStack {
      Spacer()
      HStack {
        Spacer()
        VStack(alignment: .trailing, spacing: 12) {
          if showCoverFlowHUD {
            CoverFlowDebugHUD(parameters: $coverFlowParameters) {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showCoverFlowHUD = false
              }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
          }

          Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
              showCoverFlowHUD.toggle()
            }
          } label: {
            Image(systemName: showCoverFlowHUD ? "xmark.circle" : "slider.horizontal.3")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(.primary)
              .padding(12)
              .background(.ultraThinMaterial, in: Circle())
          }
          .accessibilityLabel("Toggle cover flow tuning HUD")
        }
      }
      .padding(.trailing, 20)
      .padding(.bottom, 28)
    }
#else
    EmptyView()
#endif
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
