//
//  SettingsView.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import SwiftUI

/**
 * Settings screen with account management, help, and logout options.
 * Matches the design with three sections in rounded containers.
 */
struct SettingsView: View {
  @Bindable var appViewModel: AppViewModel;

  var body: some View {
    ZStack {
      // Background
      Color.appBackground
        .ignoresSafeArea();

      ScrollView {
        VStack(spacing: 0) {
          // Header
          Text("Settings")
            .font(.system(size: 36, weight: .bold))
            .foregroundColor(.appPrimaryText)
            .padding(.top, 16)
            .padding(.bottom, 24);

          // Account section
          SettingsSection {
            SettingsRow(
              icon: "person",
              title: "Account",
              hasChevron: true,
              action: {
                // Navigate to account settings
              }
            );

            SettingsRow(
              icon: "bell",
              title: "Notifications",
              hasChevron: true,
              action: {
                // Navigate to notification settings
              }
            );

            SettingsRow(
              icon: "photo.on.rectangle",
              title: "Generations",
              hasChevron: true,
              action: {
                // Navigate to generations settings
              }
            );
          }

          // Help section
          VStack(alignment: .leading, spacing: 8) {
            Text("Help")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.appSecondaryText)
              .padding(.horizontal, 20)
              .padding(.top, 24);

            SettingsSection {
              SettingsRow(
                icon: "envelope",
                title: "Terms & Privacy",
                hasChevron: false,
                action: {
                  // Open terms and privacy
                }
              );

              SettingsRow(
                icon: "doc.text",
                title: "Help & Resources",
                hasChevron: false,
                action: {
                  // Open help and resources
                }
              );

              SettingsRow(
                icon: "pencil",
                title: "Give Feedback",
                hasChevron: true,
                action: {
                  // Navigate to feedback
                }
              );

              SettingsRow(
                icon: "flag",
                title: "Report a Bug",
                hasChevron: true,
                action: {
                  // Navigate to bug report
                }
              );
            }
          }

          // Log Out section
          SettingsSection {
            SettingsRow(
              icon: "rectangle.portrait.and.arrow.right",
              title: "Log Out",
              hasChevron: false,
              action: {
                Task {
                  await handleLogOut();
                }
              }
            );
          }
          .padding(.top, 24);

          Spacer()
            .frame(height: 40);
        }
        .padding(.horizontal, 20);
      }
    }
  }

  /**
   * Handles logout action.
   * Signs out the user and returns to splash screen.
   */
  private func handleLogOut() async {
    await appViewModel.signOut();
  }
}

/**
 * Settings section container component.
 * Provides rounded background for grouped settings rows.
 */
private struct SettingsSection<Content: View>: View {
  @ViewBuilder let content: Content;

  var body: some View {
    VStack(spacing: 0) {
      content;
    }
    .background(Color.appSecondaryBackground)
    .cornerRadius(12);
  }
}

/**
 * Individual settings row component.
 * Displays icon, title, and optional chevron.
 */
private struct SettingsRow: View {
  let icon: String;
  let title: String;
  let hasChevron: Bool;
  let action: () -> Void;

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 20))
          .foregroundColor(.appPrimaryText)
          .frame(width: 24);

        Text(title)
          .font(.system(size: 16))
          .foregroundColor(.appPrimaryText);

        Spacer();

        if hasChevron {
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.appSecondaryText);
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
    }
  }
}

#Preview {
  SettingsView(appViewModel: {
    let vm = AppViewModel();
    vm.currentUser = User(username: "testuser", authProvider: .apple);
    return vm;
  }());
}

