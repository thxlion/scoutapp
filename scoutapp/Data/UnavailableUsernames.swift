//
//  UnavailableUsernames.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import Foundation

/**
 * Static list of reserved/unavailable usernames.
 * These usernames cannot be chosen by users during registration.
 * In production, this would be fetched from the backend.
 */
struct UnavailableUsernames {
  /// Hardcoded list of unavailable usernames
  static let list: Set<String> = [
    "admin",
    "administrator",
    "bobastudio",
    "boba",
    "studio",
    "root",
    "system",
    "user",
    "test",
    "guest",
    "support",
    "help",
    "info",
    "contact",
    "api",
    "webmaster",
    "mail",
    "noreply",
    "nobody",
    "null",
    "undefined",
    "service",
    "services",
    "official",
    "team",
    "staff",
    "moderator",
    "mod",
    "owner",
    "founder",
    "creator",
  ];

  /**
   * Checks if a username is available.
   *
   * - Parameter username: The username to check
   * - Returns: True if the username is available (not in the list), false otherwise
   */
  static func isAvailable(_ username: String) -> Bool {
    return !list.contains(username.lowercased());
  }
}

