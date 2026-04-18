import SwiftUI

/// A button-group control with Yes / No options for tri-state filtering.
/// Tapping the active button deselects it (returns to .none).
/// When .none is active, neither button is highlighted.
struct TriStateFilterControl: View {
    let label: String
    @Binding var value: TriState

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            HStack(spacing: 1) {
                filterButton("Yes", state: .yes)
                filterButton("No", state: .no)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func filterButton(_ title: String, state: TriState) -> some View {
        let isActive = value == state
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                value = isActive ? .none : state
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isActive ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(title)")
        .accessibilityValue(isActive ? "Active" : "Inactive")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
