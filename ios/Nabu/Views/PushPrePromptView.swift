import SwiftUI

/// The notification permission pre-prompt: a one-screen explanation with an
/// explicit button, so the system permission dialog is never fired cold. Shown
/// when the user turns on push in notification settings while iOS permission
/// is still undetermined.
struct PushPrePromptView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called from the explicit enable button; fires the system dialog.
    var onEnable: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignColors.primary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Never miss a reminder")
                    .font(.title2.weight(.bold))
                    .foregroundColor(DesignColors.textPrimary)
                Text("Get notified when it's time to feed, medicate, or log a chore — right when it's due. You can change this anytime in Settings.")
                    .font(.body)
                    .foregroundColor(DesignColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        await onEnable()
                        dismiss()
                    }
                } label: {
                    Text("Enable Notifications")
                }
                .buttonStyle(NabuPrimaryButtonStyle())
                .accessibilityIdentifier("push-preprompt-enable")

                Button("Not Now") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(DesignColors.textSecondary)
                .accessibilityIdentifier("push-preprompt-not-now")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .pageBackground()
    }
}
