//
//  ResultsGridView.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import SwiftUI

struct ResultsGridView: View {
  let candidates: [Candidate];
  let spectrum: DiscoveryController.Spectrum;
  let onShowMore: () -> Void;
  let onRefineCloser: () -> Void;
  let onRefineWider: () -> Void;
  let onSelect: (Candidate) -> Void;

  private let columns = [
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16)
  ];

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(candidates) { candidate in
          Button {
            onSelect(candidate);
          } label: {
            ResultCard(candidate: candidate);
          }
          .buttonStyle(.plain);
        }
      }

      refinementControls;
    }
    .padding(.bottom, 16);
  }

  private var refinementControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        refineButton(title: "Closer", action: onRefineCloser, isPrimary: spectrum == .tight);
        refineButton(title: "Wider", action: onRefineWider, isPrimary: spectrum == .wide);
        Spacer();
        Button(action: onShowMore) {
          Text("Show more")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
              Capsule()
                .fill(Color.blue.opacity(0.12))
            )
        }
      }
      Text("Refine nudges how strict we are about year and genre fits.")
        .font(.caption)
        .foregroundStyle(.secondary);
    }
  }

  private func refineButton(title: String, action: @escaping () -> Void, isPrimary: Bool) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isPrimary ? Color.white : Color.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
          Capsule()
            .fill(isPrimary ? Color.blue : Color(.systemGray5))
        )
    }
  }
}

private struct ResultCard: View {
  let candidate: Candidate;

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AsyncImage(url: candidate.posterURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill();
        case .failure:
          placeholder;
        case .empty:
          placeholder.overlay {
            ProgressView().tint(.white);
          };
        @unknown default:
          placeholder;
        }
      }
      .frame(height: 220)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6);

      Text(candidate.title)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(2);

      if let year = candidate.year {
        Text(year)
          .font(.caption)
          .foregroundStyle(.secondary);
      }
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 16)
      .fill(Color(.systemGray4))
      .frame(maxWidth: .infinity);
  }
}

#Preview {
  ResultsGridView(
    candidates: [],
    spectrum: .normal,
    onShowMore: {},
    onRefineCloser: {},
    onRefineWider: {},
    onSelect: { _ in }
  );
}
