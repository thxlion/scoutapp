//
//  AuthService.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import Foundation

/**
 * Service for handling authentication operations.
 * Mock implementation that simulates authentication flows.
 * In production, this would integrate with Apple Sign In, Google Sign In, and email authentication APIs.
 */
class AuthService {
  /**
   * Authenticates a user with Apple Sign In.
   * Mock implementation that returns a user immediately.
   *
   * - Returns: An authenticated User object
   * - Throws: AuthError if authentication fails
   */
  func signInWithApple() async throws -> User {
    // Simulate network delay
    try await Task.sleep(nanoseconds: 500_000_000); // 0.5 seconds

    // Mock successful authentication
    return User(
      authProvider: .apple,
      email: "user@example.com"
    );
  }

  /**
   * Authenticates a user with Google Sign In.
   * Mock implementation that returns a user immediately.
   *
   * - Returns: An authenticated User object
   * - Throws: AuthError if authentication fails
   */
  func signInWithGoogle() async throws -> User {
    // Simulate network delay
    try await Task.sleep(nanoseconds: 500_000_000); // 0.5 seconds

    // Mock successful authentication
    return User(
      authProvider: .google,
      email: "user@gmail.com"
    );
  }

  /**
   * Authenticates a user with email and password.
   * Mock implementation that returns a user immediately.
   *
   * - Parameters:
   *   - email: User's email address
   *   - password: User's password
   * - Returns: An authenticated User object
   * - Throws: AuthError if authentication fails
   */
  func signInWithEmail(email: String, password: String) async throws -> User {
    // Simulate network delay
    try await Task.sleep(nanoseconds: 500_000_000); // 0.5 seconds

    // Mock validation
    guard !email.isEmpty, !password.isEmpty else {
      throw AuthError.invalidCredentials;
    }

    // Mock successful authentication
    return User(
      authProvider: .email,
      email: email
    );
  }

  /**
   * Signs out the current user.
   * Mock implementation that clears local authentication state.
   */
  func signOut() async {
    // In production, this would call the backend to invalidate the session
    // For now, we just return immediately
    return;
  }
}

/**
 * Authentication error types.
 */
enum AuthError: Error {
  case invalidCredentials;
  case networkError;
  case unknown;
}

