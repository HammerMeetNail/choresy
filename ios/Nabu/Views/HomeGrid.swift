import SwiftUI

struct HomeGrid: View {
    let chores: [Chore]
    let latestLogs: [Int: ChoreLog]
    let isJiggling: Bool
    let onTap: (Chore) -> Void
    let onEdit: (Chore) -> Void
    let onHide: (Chore) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(chores) { chore in
                HomeChoreCell(
                    chore: chore,
                    latestLog: latestLogs[chore.id],
                    isJiggling: isJiggling,
                    onTap: { onTap(chore) },
                    onEdit: { onEdit(chore) },
                    onHide: { onHide(chore) }
                )
            }
        }
    }
}

struct HomeChoreCell: View {
    let chore: Chore
    let latestLog: ChoreLog?
    let isJiggling: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onHide: () -> Void

    @State private var isPressing = false
    @State private var wobbleAngle: Double = 0

    var body: some View {
        Button {
            onTap()
        } label: {
            // HStack approach: colored left stripe + content
            // clipShape rounds both together — no clipping bug
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: chore.color) ?? .accentColor)
                    .frame(width: 4)

                VStack(spacing: 4) {
                    Text(chore.icon)
                        .font(.system(size: 24))
                    Text(chore.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let log = latestLog {
                        Text(formatTimeAgo(log.completedAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("never")
                            .font(.caption2)
                            .foregroundColor(DesignColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }
            .frame(minHeight: 90)
            .background(DesignColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(DesignColors.border.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
            // Tap bounce: a quick spring so a log *feels* logged (C3). With
            // Reduce Motion the scale is skipped and only opacity dips.
            .scaleEffect(isPressing && !Motion.reduceMotion ? 0.92 : 1.0)
            .opacity(isPressing ? 0.75 : 1.0)
            .animation(Motion.snappy ?? Motion.fade, value: isPressing)
            .rotationEffect(.degrees(wobbleAngle))
        }
        .buttonStyle(.plain)
        // Jiggle-mode wobble (C3); Reduce Motion keeps tiles still — the
        // context menu and toolbar checkmark already signal edit mode.
        .onChange(of: isJiggling) { _, jiggling in
            if jiggling && !Motion.reduceMotion {
                wobbleAngle = -1.4
                withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) {
                    wobbleAngle = 1.4
                }
            } else {
                withAnimation(Motion.fade) { wobbleAngle = 0 }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chore.name), \(latestLog != nil ? "done \(formatTimeAgo(latestLog!.completedAt))" : "never done")")
        // Long-press context menu replaces the old long-press-to-log gesture:
        // native counterpart of the PWA's tile actions (§2.1 mapping).
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Log…", systemImage: "checkmark.circle")
            }
            Button {
                onEdit()
            } label: {
                Label("Edit chore", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onHide()
            } label: {
                Label("Hide from Home", systemImage: "eye.slash")
            }
        }
        .onLongPressGesture(minimumDuration: 0.1, perform: {}) {
            isPressing = $0
        }
    }

}
