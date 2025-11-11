//
//  Extensions.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import Foundation
import SwiftUI

/**
 * App theme colors matching the dark theme design.
 */
extension Color {
  /// Primary background color (black)
  static let appBackground = Color.black;

  /// Secondary background color (dark grey)
  static let appSecondaryBackground = Color(white: 0.15);

  /// Primary text color (white)
  static let appPrimaryText = Color.white;

  /// Secondary text color (light grey)
  static let appSecondaryText = Color(white: 0.7);

  /// Tertiary text color (grey)
  static let appTertiaryText = Color(white: 0.5);

  /// Button background color (dark grey)
  static let appButtonBackground = Color(white: 0.2);

  /// Button border color (light grey)
  static let appButtonBorder = Color(white: 0.3);

  /// Overlay background for semi-transparent overlays
  static let appOverlayBackground = Color.black.opacity(0.5);
}

/**
 * Date formatting extensions.
 */
extension Date {
  /**
   * Formats the date for display in activity items.
   * Shows time if today, date if older.
   *
   * - Returns: Formatted date string
   */
  func activityDisplayString() -> String {
    let calendar = Calendar.current;
    let now = Date();

    if calendar.isDateInToday(self) {
      // Show time for today's items
      let formatter = DateFormatter();
      formatter.dateStyle = .none;
      formatter.timeStyle = .short;
      return formatter.string(from: self);
    } else {
      // Show date for older items
      let formatter = DateFormatter();
      formatter.dateFormat = "d MMM";
      return formatter.string(from: self);
    }
  }

  /**
   * Formats the date for display in media sections.
   * Shows full date format.
   *
   * - Returns: Formatted date string
   */
  func mediaDisplayString() -> String {
    let formatter = DateFormatter();
    formatter.dateFormat = "d MMMM";
    return formatter.string(from: self);
  }
}

