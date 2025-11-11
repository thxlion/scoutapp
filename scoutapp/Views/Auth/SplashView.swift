//
//  SplashView.swift
//  scoutapp
//
//  Created on 04/11/2025.
//

import SwiftUI

/**
 * Splash/authentication screen.
 * Displays app branding and three authentication options: Apple, Google, and Email.
 * Matches the design with dark theme and proper button styling.
 */
struct SplashView: View {
  @Bindable var appViewModel: AppViewModel;

  @State private var isSigningIn: Bool = false;

  var body: some View {
    ZStack {
      // Background
      Color.appBackground
        .ignoresSafeArea();

      VStack(spacing: 0) {
        Spacer();

        // App branding section
        VStack(spacing: 8) {
          // App name with custom styling
          Text("boba studio")
            .font(.system(size: 48, weight: .bold, design: .default))
            .foregroundColor(.appPrimaryText);

          // Tagline
          Text("From thought, to Anime")
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(.appSecondaryText);
        }
        .padding(.bottom, 60);

        // Authentication buttons
        VStack(spacing: 16) {
          // Continue with Apple button
          Button(action: {
            Task {
              await handleAppleSignIn();
            }
          }) {
            HStack {
              Image(systemName: "apple.logo")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.black);

              Text("Continue with Apple")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black);
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
          }
          .disabled(isSigningIn);

          // Continue with Google button
          Button(action: {
            Task {
              await handleGoogleSignIn();
            }
          }) {
            HStack {
              // Google "G" icon
              ZStack {
                Circle()
                  .fill(Color.white)
                  .frame(width: 24, height: 24);

                Text("G")
                  .font(.system(size: 14, weight: .bold))
                  .foregroundColor(.black);
              }

              Text("Continue with Google")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.appPrimaryText);
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.appButtonBackground)
            .cornerRadius(12)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appButtonBorder, lineWidth: 1)
            )
          }
          .disabled(isSigningIn);

          // Continue with Email button
          Button(action: {
            Task {
              await handleEmailSignIn();
            }
          }) {
            HStack {
              Image(systemName: "envelope")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.appPrimaryText);

              Text("Continue with Email")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.appPrimaryText);
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.appButtonBackground)
            .cornerRadius(12)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appButtonBorder, lineWidth: 1)
            )
          }
          .disabled(isSigningIn);
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40);

        // Terms and Privacy text
        VStack(spacing: 4) {
          Text("By using Boba Studio, you agree with our")
            .font(.system(size: 12))
            .foregroundColor(.appTertiaryText);

          HStack(spacing: 4) {
            Button(action: {
              // Open terms of service
            }) {
              Text("Terms of Service")
                .font(.system(size: 12))
                .foregroundColor(.appSecondaryText)
                .underline();
            }

            Text("and")
              .font(.system(size: 12))
              .foregroundColor(.appTertiaryText);

            Button(action: {
              // Open privacy policy
            }) {
              Text("Privacy Policy")
                .font(.system(size: 12))
                .foregroundColor(.appSecondaryText)
                .underline();
            }
          }
        }
        .padding(.bottom, 40);

        Spacer();
      }
    }
  }

  /**
   * Handles Apple Sign In authentication.
   * Calls the app view model's sign in method.
   */
  private func handleAppleSignIn() async {
    isSigningIn = true;
    await appViewModel.signInWithApple();
    isSigningIn = false;
  }

  /**
   * Handles Google Sign In authentication.
   * Calls the app view model's sign in method.
   */
  private func handleGoogleSignIn() async {
    isSigningIn = true;
    await appViewModel.signInWithGoogle();
    isSigningIn = false;
  }

  /**
   * Handles Email Sign In authentication.
   * For now, uses a mock email/password.
   * In production, this would show a form or sheet.
   */
  private func handleEmailSignIn() async {
    isSigningIn = true;
    // Mock email authentication
    await appViewModel.signInWithEmail(email: "user@example.com", password: "password");
    isSigningIn = false;
  }
}

#Preview {
  SplashView(appViewModel: AppViewModel());
}

