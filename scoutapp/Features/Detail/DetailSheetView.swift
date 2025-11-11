//
//  DetailSheetView.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import SwiftUI

@MainActor
struct DetailSheetView: View {
  let candidate: Candidate;
  var shelfStore: ShelfStore;

  @State private var providers: WatchProvidersResponse.Country?;
  @State private var isLoadingProviders = false;
  @State private var watchError: String?;

  var body: some View {
    @Bindable var shelfStore = shelfStore;

    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        headerSection;
        overviewSection;
        watchSection;
        shelfButton(store: shelfStore);
      }
      .padding(24);
    }
    .presentationDetents([.fraction(0.7), .large])
    .presentationDragIndicator(.visible)
    .task(id: candidate.identifier) {
      await fetchWatchProviders();
    }
  }

  private var headerSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 16) {
        AsyncImage(url: candidate.posterURL) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill();
          case .failure:
            Color(.systemGray4);
          case .empty:
            Color(.systemGray4)
              .overlay { ProgressView().tint(.white); };
          @unknown default:
            Color(.systemGray4);
          }
        }
        .frame(width: 120, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18))

        VStack(alignment: .leading, spacing: 6) {
          Text(candidate.title)
            .font(.title2.weight(.bold));
          Text(detailHeader())
            .font(.subheadline)
            .foregroundStyle(.secondary);
          if !GenreStore.shared.genreNames(for: candidate.genreIDs).isEmpty {
            Text(GenreStore.shared.genreNames(for: candidate.genreIDs).joined(separator: " • "))
              .font(.footnote)
              .foregroundStyle(.secondary);
          }
        }
        Spacer();
      }
    }
  }

  private func detailHeader() -> String {
    var components: [String] = [];
    if let year = candidate.year {
      components.append(year);
    }
    components.append(candidate.type == .movie ? "Film" : "Series");
    return components.joined(separator: " • ");
  }

  private var overviewSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Overview")
        .font(.headline);
      Text(candidate.overview.isEmpty ? "No overview available." : candidate.overview)
        .font(.body)
        .foregroundStyle(.secondary);
    }
  }

  @ViewBuilder
  private var watchSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Where to watch (\(Config.region))")
        .font(.headline);
      if isLoadingProviders {
        ProgressView()
          .tint(.blue);
      } else if let watchError {
        Text(watchError)
          .font(.subheadline)
          .foregroundStyle(.secondary);
      } else if let providers {
        if providers.flatrate == nil, providers.rent == nil, providers.buy == nil {
          Text("We couldn’t find streaming info right now.")
            .font(.subheadline)
            .foregroundStyle(.secondary);
        } else {
          watchSection(title: "Included with", providers: providers.flatrate);
          watchSection(title: "Rent", providers: providers.rent);
          watchSection(title: "Buy", providers: providers.buy);
        }
      }
    }
  }

  @ViewBuilder
  private func watchSection(title: String, providers: [WatchProvidersResponse.Provider]?) -> some View {
    if let providers, !providers.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.subheadline.weight(.semibold));
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(providers, id: \.self) { provider in
              Text(provider.providerName)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                  Capsule()
                    .fill(Color(.systemGray6))
                );
            }
          }
        }
      }
    }
  }

  private func shelfButton(store: ShelfStore) -> some View {
    let isSaved = store.contains(candidate);
    return Button {
      store.toggle(candidate);
    } label: {
      Text(isSaved ? "Remove from Shelf" : "Add to Shelf")
        .font(.headline)
        .foregroundStyle(isSaved ? Color.primary : Color.white)
        .frame(maxWidth: .infinity)
        .padding()
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(isSaved ? Color(.systemGray5) : Color.blue)
        );
    }
  }

  private func fetchWatchProviders() async {
    isLoadingProviders = true;
    watchError = nil;
    do {
      let response = try await APIClient.shared.watchProviders(for: candidate.type, id: candidate.id);
      providers = response.results[Config.region];
      isLoadingProviders = false;
    } catch {
      watchError = "No provider data available right now.";
      isLoadingProviders = false;
      print("Providers error: \(error)");
    }
  }
}

#Preview {
  DetailSheetView(candidate: Candidate(from: TMDBMedia(
    id: 1,
    title: "Sample",
    name: nil,
    posterPath: nil,
    overview: "Overview",
    genreIds: [16],
    popularity: 10,
    voteAverage: 8.2,
    releaseDate: "2019-01-01",
    firstAirDate: nil,
    originCountry: ["JP"],
    originalLanguage: "ja"
  ), type: .tv), shelfStore: ShelfStore());
}
