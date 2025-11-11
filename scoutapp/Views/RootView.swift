//
//  RootView.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import SwiftUI

/**
 * Root view that handles conditional navigation based on app state.
 * Routes to SplashView, UsernamePickerView, or MainTabView based on authentication and onboarding status.
 */
struct RootView: View {
  @Bindable var appViewModel: AppViewModel;

  var body: some View {
    Group {
      if !appViewModel.isAuthenticated {
        // User is not authenticated, show splash screen
        SplashView(appViewModel: appViewModel);
      } else if !appViewModel.hasCompletedOnboarding {
        // User is authenticated but hasn't set a username
        UsernamePickerView(appViewModel: appViewModel);
      } else {
        // User is fully onboarded, show main app
        MainTabView(appViewModel: appViewModel);
      }
    }
  }
}

#Preview {
  RootView(appViewModel: AppViewModel());
}

