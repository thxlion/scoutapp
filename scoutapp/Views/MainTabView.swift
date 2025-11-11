//
//  MainTabView.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import SwiftUI

/**
 * Main tab view containing all main app screens.
 * Uses custom bottom navigation bar instead of SwiftUI's TabView.
 * Handles tab switching between Browse, Search, Watchlist, and Profile.
 */
struct MainTabView: View {
  @Bindable var appViewModel: AppViewModel;

  var body: some View {
    ZStack {
      // Background
      Color.appBackground
        .ignoresSafeArea();

      VStack(spacing: 0) {
        // Content area
        Group {
          switch appViewModel.selectedTab {
          case .browse:
            // TODO: Replace with BrowseView
            PlaceholderView(title: "Browse", icon: "film");
          case .search:
            // TODO: Replace with SearchView
            PlaceholderView(title: "Search", icon: "magnifyingglass");
          case .watchlist:
            // TODO: Replace with WatchlistView
            PlaceholderView(title: "Watchlist", icon: "heart");
          case .profile:
            // Settings view serves as profile for now
            SettingsView(appViewModel: appViewModel);
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity);

        // Bottom navigation bar
        BottomNavBar(
          selectedTab: $appViewModel.selectedTab
        );
      }
    }
  }
}

/**
 * Temporary placeholder view for tabs under development.
 */
private struct PlaceholderView: View {
  let title: String;
  let icon: String;

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: icon)
        .font(.system(size: 60))
        .foregroundColor(.appSecondaryText);

      Text(title)
        .font(.title)
        .foregroundColor(.appPrimaryText);

      Text("Coming soon...")
        .font(.body)
        .foregroundColor(.appSecondaryText);
    }
  }
}

#Preview {
  MainTabView(appViewModel: {
    let vm = AppViewModel();
    vm.currentUser = User(username: "testuser", authProvider: .apple);
    return vm;
  }());
}

