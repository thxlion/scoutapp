//
//  BottomNavBar.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import SwiftUI

/**
 * Custom bottom navigation bar component.
 * Matches the design with 4 tabs: Browse, Search, Watchlist, Profile.
 * Active tab is highlighted with a white circle/background.
 */
struct BottomNavBar: View {
  @Binding var selectedTab: MainTab;

  var body: some View {
    HStack(spacing: 0) {
      // Browse tab
      TabButton(
        tab: .browse,
        selectedTab: $selectedTab,
        iconName: "film"
      );

      // Search tab
      TabButton(
        tab: .search,
        selectedTab: $selectedTab,
        iconName: "magnifyingglass"
      );

      // Watchlist tab
      TabButton(
        tab: .watchlist,
        selectedTab: $selectedTab,
        iconName: "heart"
      );

      // Profile tab
      TabButton(
        tab: .profile,
        selectedTab: $selectedTab,
        iconName: "person"
      );
    }
    .frame(height: 60)
    .background(Color.appBackground)
  }
}

/**
 * Individual tab button component.
 * Shows active state with white circle background.
 */
private struct TabButton: View {
  let tab: MainTab;
  @Binding var selectedTab: MainTab;
  let iconName: String;

  var isSelected: Bool {
    selectedTab == tab;
  }

  var body: some View {
    Button(action: {
      selectedTab = tab;
    }) {
      ZStack {
        if isSelected {
          Circle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 40, height: 40);
        }

        Image(systemName: iconName)
          .font(.system(size: 24))
          .foregroundColor(isSelected ? .appPrimaryText : .appSecondaryText);
      }
      .frame(maxWidth: .infinity);
    }
  }
}

#Preview {
  BottomNavBar(
    selectedTab: .constant(.browse)
  );
}

