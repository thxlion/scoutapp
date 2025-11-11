//
//  UsernamePickerView.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import SwiftUI

/**
 * Username picker screen for onboarding.
 * Allows users to choose a username with real-time availability checking.
 * Validates format and checks against unavailable usernames list.
 */
struct UsernamePickerView: View {
  @Bindable var appViewModel: AppViewModel;

  @State private var username: String = "";
  @State private var isCheckingAvailability: Bool = false;
  @State private var isAvailable: Bool? = nil;
  @State private var isValidFormat: Bool = false;

  private let usernameService = UsernameService();

  var body: some View {
    ZStack {
      // Background
      Color.appBackground
        .ignoresSafeArea();

      VStack(spacing: 0) {
        Spacer();

        // Title section
        VStack(spacing: 8) {
          Text("Username")
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(.appPrimaryText);

          Text("A username for easy recognition")
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(.appSecondaryText);
        }
        .padding(.bottom, 40);

        // Username input field
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            TextField("Enter username here", text: $username)
              .textFieldStyle(.plain)
              .font(.system(size: 16))
              .foregroundColor(.appPrimaryText)
              .autocapitalization(.none)
              .autocorrectionDisabled()
              .onChange(of: username) { _, newValue in
                checkUsername(newValue);
              };

            // Availability indicator
            if isCheckingAvailability {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .appSecondaryText))
                .scaleEffect(0.8);
            } else if let available = isAvailable {
              Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(available ? .green : .red)
                .font(.system(size: 20));
            }
          }
          .padding()
          .background(Color.appSecondaryBackground)
          .cornerRadius(12)
          .overlay(
            RoundedRectangle(cornerRadius: 12)
            .stroke(Color.appButtonBorder, lineWidth: 1)
          );

          // Validation feedback
          if !username.isEmpty {
            if !isValidFormat {
              Text("Username must be at least 3 characters, alphanumeric and underscore only")
                .font(.system(size: 12))
                .foregroundColor(.red);
            } else if let available = isAvailable, !available {
              Text("This username is not available")
                .font(.system(size: 12))
                .foregroundColor(.red);
            }
          }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32);

        // Continue button
        Button(action: {
          handleContinue();
        }) {
          Text("Continue")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.appPrimaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isContinueEnabled ? Color.appButtonBackground : Color.appSecondaryBackground.opacity(0.5))
            .cornerRadius(12)
        }
        .disabled(!isContinueEnabled)
        .padding(.horizontal, 32);

        Spacer();
      }
    }
  }

  /**
   * Computed property to determine if the continue button should be enabled.
   * Button is enabled only when username is valid and available.
   */
  private var isContinueEnabled: Bool {
    return isValidFormat && (isAvailable == true);
  }

  /**
   * Checks username format and availability.
   * Validates format first, then checks availability if format is valid.
   *
   * - Parameter newValue: The username string to check
   */
  private func checkUsername(_ newValue: String) {
    // Validate format
    isValidFormat = validateFormat(newValue);

    if !isValidFormat {
      isAvailable = nil;
      return;
    }

    // Check availability
    Task {
      await checkAvailability(newValue);
    }
  }

  /**
   * Validates username format.
   * Must be at least 3 characters, alphanumeric and underscore only.
   *
   * - Parameter username: The username to validate
   * - Returns: True if format is valid, false otherwise
   */
  private func validateFormat(_ username: String) -> Bool {
    guard username.count >= 3 else {
      return false;
    }

    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"));
    return username.rangeOfCharacter(from: allowedCharacters.inverted) == nil;
  }

  /**
   * Checks username availability using the service.
   * Updates the availability state.
   *
   * - Parameter username: The username to check
   */
  private func checkAvailability(_ username: String) async {
    await MainActor.run {
      isCheckingAvailability = true;
    }

    let available = await usernameService.checkAvailability(username);

    await MainActor.run {
      isCheckingAvailability = false;
      isAvailable = available;
    }
  }

  /**
   * Handles the continue button tap.
   * Saves the username to the user model and completes onboarding.
   */
  private func handleContinue() {
    guard isContinueEnabled else {
      return;
    }

    appViewModel.setUsername(username);
  }
}

#Preview {
  UsernamePickerView(appViewModel: AppViewModel());
}

