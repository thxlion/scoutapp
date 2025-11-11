//
//  AppViewModel.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import Foundation
import SwiftUI
import Observation

/**
 * Global app state view model.
 * Manages authentication state, current user, and navigation flow.
 * Uses @Observable macro for iOS 18+ state management.
 */
@Observable
class AppViewModel {
  /// Current authenticated user, nil if not authenticated
  var currentUser: User?;

  /// Currently selected tab in the main navigation
  var selectedTab: MainTab = .browse;

  /// Authentication service instance
  private let authService = AuthService();

  /**
   * Initializes the app view model.
   * Checks for existing authentication state from UserDefaults.
   * 
   * For development/testing: Set `skipUserDefaultsLoad` to true to always start from splash screen.
   */
  init(skipUserDefaultsLoad: Bool = false) {
    // In production, this would check for a valid session token
    // For now, we check UserDefaults for a saved user
    // Skip loading for development/testing to always see the sign up flow
    if !skipUserDefaultsLoad {
      if let userData = UserDefaults.standard.data(forKey: "currentUser"),
         let user = try? JSONDecoder().decode(User.self, from: userData) {
        self.currentUser = user;
      }
    }
  }

  /**
   * Checks if the user is authenticated.
   *
   * - Returns: True if user is authenticated, false otherwise
   */
  var isAuthenticated: Bool {
    return currentUser != nil;
  }

  /**
   * Checks if the user has completed onboarding (has a username).
   *
   * - Returns: True if user has a username, false otherwise
   */
  var hasCompletedOnboarding: Bool {
    return currentUser?.username != nil;
  }

  /**
   * Signs in a user with Apple.
   * Sets the current user and saves to UserDefaults.
   */
  func signInWithApple() async {
    do {
      let user = try await authService.signInWithApple();
      await MainActor.run {
        self.currentUser = user;
        self.saveUser();
      }
    } catch {
      // Handle error (in production, show error alert)
      print("Error signing in with Apple: \(error)");
    }
  }

  /**
   * Signs in a user with Google.
   * Sets the current user and saves to UserDefaults.
   */
  func signInWithGoogle() async {
    do {
      let user = try await authService.signInWithGoogle();
      await MainActor.run {
        self.currentUser = user;
        self.saveUser();
      }
    } catch {
      // Handle error (in production, show error alert)
      print("Error signing in with Google: \(error)");
    }
  }

  /**
   * Signs in a user with email.
   * Sets the current user and saves to UserDefaults.
   *
   * - Parameters:
   *   - email: User's email address
   *   - password: User's password
   */
  func signInWithEmail(email: String, password: String) async {
    do {
      let user = try await authService.signInWithEmail(email: email, password: password);
      await MainActor.run {
        self.currentUser = user;
        self.saveUser();
      }
    } catch {
      // Handle error (in production, show error alert)
      print("Error signing in with email: \(error)");
    }
  }

  /**
   * Sets the username for the current user.
   *
   * - Parameter username: The username to set
   */
  func setUsername(_ username: String) {
    currentUser?.username = username;
    saveUser();
  }

  /**
   * Signs out the current user.
   * Clears authentication state and saved data.
   */
  func signOut() async {
    await authService.signOut();
    await MainActor.run {
      self.currentUser = nil;
      UserDefaults.standard.removeObject(forKey: "currentUser");
    }
  }

  /**
   * Saves the current user to UserDefaults.
   * Private helper method.
   */
  private func saveUser() {
    guard let user = currentUser,
          let userData = try? JSONEncoder().encode(user) else {
      return;
    }
    UserDefaults.standard.set(userData, forKey: "currentUser");
  }
}

/**
 * Enumeration of main navigation tabs.
 */
enum MainTab: String, CaseIterable {
  case browse = "browse";
  case search = "search";
  case watchlist = "watchlist";
  case profile = "profile";

  /// Display name for the tab
  var displayName: String {
    switch self {
    case .browse:
      return "Browse";
    case .search:
      return "Search";
    case .watchlist:
      return "Watchlist";
    case .profile:
      return "Profile";
    }
  }

  /// SF Symbol name for the tab icon
  var iconName: String {
    switch self {
    case .browse:
      return "film";
    case .search:
      return "magnifyingglass";
    case .watchlist:
      return "heart";
    case .profile:
      return "person";
    }
  }
}
