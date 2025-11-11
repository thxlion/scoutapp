//
//  UsernameService.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import Foundation

/**
 * Service for checking username availability.
 * Validates usernames against a hardcoded list of unavailable usernames.
 * In production, this would make an API call to check availability.
 */
class UsernameService {
  /**
   * Checks if a username is available.
   * Validates format and checks against the unavailable usernames list.
   *
   * - Parameter username: The username to check
   * - Returns: True if the username is available, false otherwise
   */
  func checkAvailability(_ username: String) async -> Bool {
    // Simulate network delay
    try? await Task.sleep(nanoseconds: 300_000_000); // 0.3 seconds

    // Validate format
    guard isValidFormat(username) else {
      return false;
    }

    // Check against unavailable list
    return UnavailableUsernames.isAvailable(username);
  }

  /**
   * Validates username format.
   * Username must be at least 3 characters, alphanumeric plus underscore.
   *
   * - Parameter username: The username to validate
   * - Returns: True if the format is valid, false otherwise
   */
  private func isValidFormat(_ username: String) -> Bool {
    // Minimum length check
    guard username.count >= 3 else {
      return false;
    }

    // Alphanumeric and underscore only
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"));
    return username.rangeOfCharacter(from: allowedCharacters.inverted) == nil;
  }
}

