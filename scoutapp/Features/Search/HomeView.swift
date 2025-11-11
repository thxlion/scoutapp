//
//  HomeView.swift
//  scoutapp
//
//  Created by Codex on 05/11/2025.
//

import SwiftUI
import Observation

struct HomeView: View {
  @State private var controller = DiscoveryController();
  @State private var shelfStore = ShelfStore();
  @State private var selectedCandidate: Candidate?;

  var body: some View {
    @Bindable var controller = controller;

    NavigationStack {
      ZStack(alignment: .bottom) {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text("What are we feeling like?")
              .font(.system(size: 34, weight: .bold))
              .foregroundColor(.primary)
              .padding(.top, 32);

            conversationSection(controller: controller);
            resultsSection(controller: controller);
            Spacer(minLength: 120);
          }
          .padding(.horizontal, 24);
        }

        inputBar(controller: controller);
      }
      .background(Color(.systemBackground))
      .navigationTitle("SCOUT")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(item: $selectedCandidate) { candidate in
        DetailSheetView(candidate: candidate, shelfStore: shelfStore);
      }
    }
  }

  @ViewBuilder
  private func conversationSection(controller: DiscoveryController) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let lastPrompt = controller.lastPrompt {
        bubble(text: lastPrompt, alignment: .trailing, color: Color(.systemGray6), textColor: .primary);
      } else {
        Text("Tell me a vibe. “Anime with a cat, cozy slice of life” or “Something like Aftersun but in Spain.”")
          .font(.subheadline)
          .foregroundStyle(.secondary);
      }

      if controller.isSearching {
        bubble(text: "Percolating…", alignment: .leading, color: Color.blue.opacity(0.15), textColor: .blue)
          .overlay(alignment: .trailing) {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.blue)
              .padding(.trailing, 12);
          };
      } else if !controller.visibleCandidates.isEmpty {
        bubble(text: summaryText(for: controller.visibleCandidates),
               alignment: .leading,
               color: Color.blue,
               textColor: .white);
      } else if let error = controller.errorMessage {
        bubble(text: error, alignment: .leading, color: Color.red.opacity(0.15), textColor: .red);
      }
    }
  }

  @ViewBuilder
  private func resultsSection(controller: DiscoveryController) -> some View {
    if controller.visibleCandidates.isEmpty {
      EmptyView();
    } else {
      ResultsGridView(
        candidates: controller.visibleCandidates,
        spectrum: controller.spectrum,
        onShowMore: { controller.showMore() },
        onRefineCloser: { controller.refineCloser() },
        onRefineWider: { controller.refineWider() },
        onSelect: { candidate in
          selectedCandidate = candidate;
        }
      )
      .animation(.spring(duration: 0.3), value: controller.visibleCandidates);
    }
  }

  private func summaryText(for candidates: [Candidate]) -> String {
    guard let first = candidates.first else { return "Here you go."; }
    let titles = candidates.prefix(3).map { $0.title };
    let remaining = max(0, candidates.count - 3);
    var text = "Found \(candidates.count) picks. \(titles.joined(separator: ", "))";
    if remaining > 0 {
      text += ", and \(remaining) more.";
    }
    return text;
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
        );

      Button(action: controller.search) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(.blue);
      }
      .disabled(controller.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty);
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .background(.ultraThinMaterial);
  }

  private func bubble(text: String, alignment: HorizontalAlignment, color: Color, textColor: Color) -> some View {
    HStack {
      if alignment == .trailing { Spacer(minLength: 40); }
      Text(text)
        .foregroundStyle(textColor)
        .padding(16)
        .background(
          RoundedRectangle(cornerRadius: 22)
            .fill(color)
        )
      if alignment == .leading { Spacer(minLength: 40); }
    }
  }
}

#Preview {
  HomeView();
}
