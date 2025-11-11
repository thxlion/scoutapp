//
//  User.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import Foundation

/**
 * User model representing an authenticated user in the app.
 * Supports multiple authentication providers (Apple, Google, Email).
 * Codable for future API integration.
 */
struct User: Codable, Identifiable {
  /// Unique identifier for the user
  let id: UUID;

  /// Username chosen by the user during onboarding
  var username: String?;

  /// Authentication provider used to sign in
  let authProvider: AuthProvider;

  /// Email address (if available from auth provider)
  let email: String?;

  /// Timestamp when the user account was created
  let createdAt: Date;

  /**
   * Initializes a new User instance.
   *
   * - Parameters:
   *   - id: Unique identifier (defaults to new UUID)
   *   - username: Optional username
   *   - authProvider: The authentication provider used
   *   - email: Optional email address
   *   - createdAt: Account creation timestamp (defaults to current date)
   */
  init(
    id: UUID = UUID(),
    username: String? = nil,
    authProvider: AuthProvider,
    email: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id;
    self.username = username;
    self.authProvider = authProvider;
    self.email = email;
    self.createdAt = createdAt;
  }
}

/**
 * Enumeration of supported authentication providers.
 */
enum AuthProvider: String, Codable {
  case apple = "apple";
  case google = "google";
  case email = "email";
}

