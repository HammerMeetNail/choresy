import SwiftUI

struct UndoToast: View {
    let choreName: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var undoTapped = false

    var body: some View {
        HStack(spacing: 12) {
            Text("Logged \(choreName)")
                .font(.subheadline)
                .foregroundColor(.white)

            Spacer()

            Button("Undo") {
                undoTapped = true
                onUndo()
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: undoTapped)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.25))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .opacity(isVisible ? 1 : 0)
        // Spring slide from the bottom edge (C3); Reduce Motion fades in place.
        .offset(y: isVisible || Motion.reduceMotion ? 0 : 24)
        .onAppear {
            withAnimation(Motion.slide ?? Motion.fade) { isVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(Motion.fade) { isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }
}
