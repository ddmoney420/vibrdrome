import SwiftUI

struct EQView: View {
    @Environment(\.dismiss) private var dismiss
    private var eqEngine: EQEngine { EQEngine.shared }

    @State private var showSaveAlert = false
    @State private var customPresetName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    presetPicker

                    bandSliders

                    customPresetActions
                }
                .padding()
            }
            .navigationTitle("Equalizer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("eqDoneButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") {
                        eqEngine.applyPreset(EQPresets.flat)
                    }
                    .accessibilityIdentifier("eqResetButton")
                }
            }
            .alert("Save Preset", isPresented: $showSaveAlert) {
                TextField("Preset Name", text: $customPresetName)
                Button("Save") {
                    let name = customPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        eqEngine.saveCustomPreset(name: name)
                    }
                    customPresetName = ""
                }
                Button("Cancel", role: .cancel) {
                    customPresetName = ""
                }
            } message: {
                Text("Enter a name for this EQ preset.")
            }
        }
    }

    // MARK: - Preset Picker

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EQPresets.all) { preset in
                        Button {
                            eqEngine.applyPreset(preset)
                        } label: {
                            Text(preset.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    eqEngine.currentPresetId == preset.id
                                        ? AnyShapeStyle(.tint)
                                        : AnyShapeStyle(.quaternary)
                                )
                                .foregroundStyle(
                                    eqEngine.currentPresetId == preset.id ? .white : .primary
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom presets
                    let customs = eqEngine.loadCustomPresets()
                    ForEach(Array(customs.keys.sorted()), id: \.self) { name in
                        Button {
                            if let gains = customs[name], gains.count == 10 {
                                eqEngine.customGains = gains
                                eqEngine.applyPreset(EQPreset(id: "custom_\(name)", name: name, gains: gains))
                            }
                        } label: {
                            Text(name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.quaternary)
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Band Sliders

    private var bandSliders: some View {
        VStack(spacing: 4) {
            // dB scale labels
            HStack {
                Text("+12")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("0 dB")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("-12")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<10, id: \.self) { index in
                    VStack(spacing: 6) {
                        // Gain value label
                        Text(gainLabel(eqEngine.customGains[index]))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)

                        // Vertical slider
                        VerticalSlider(
                            value: Binding(
                                get: { eqEngine.customGains[index] },
                                set: { eqEngine.setGain($0, forBand: index) }
                            ),
                            range: -12...12,
                            label: EQPresets.bands[index]
                        )
                        .frame(height: 180)

                        // Frequency label
                        Text(EQPresets.bands[index])
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Custom Preset Actions

    private var customPresetActions: some View {
        HStack(spacing: 12) {
            Button {
                showSaveAlert = true
            } label: {
                Label("Save as Preset", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("savePresetButton")
        }
    }

    private func gainLabel(_ gain: Float) -> String {
        if gain >= 0 {
            return "+\(String(format: "%.0f", gain))"
        }
        return String(format: "%.0f", gain)
    }
}

// MARK: - Vertical Slider

private struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    var label: String = ""

    private let step: Float = 1.0

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let yPos = height * (1 - normalized)

            ZStack {
                // Track
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 4)

                // Zero line
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 12, height: 1)
                    .position(x: geo.size.width / 2, y: height / 2)

                // Fill from center
                let centerY = height / 2
                let fillHeight = abs(yPos - centerY)
                let fillY = min(yPos, centerY) + fillHeight / 2
                Capsule()
                    .fill(.tint)
                    .frame(width: 4, height: fillHeight)
                    .position(x: geo.size.width / 2, y: fillY)

                // Thumb
                Circle()
                    .fill(.tint)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .position(x: geo.size.width / 2, y: yPos)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = 1 - Float(drag.location.y / height)
                        let clamped = max(0, min(1, fraction))
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) Hz")
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + step, range.upperBound)
            case .decrement:
                value = max(value - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }

    private var accessibilityValueText: String {
        let rounded = Int(value.rounded())
        if rounded >= 0 {
            return "+\(rounded) dB"
        }
        return "\(rounded) dB"
    }
}
