import SwiftUI

// MARK: - Visualizer Presets

enum VisualizerPreset: String, CaseIterable, Identifiable {
    case plasma = "Plasma"
    case aurora = "Aurora"
    case nebula = "Nebula"
    case waveform = "Waveform"
    case tunnel = "Tunnel"
    case kaleidoscope = "Kaleidoscope"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .plasma: "flame.fill"
        case .aurora: "sparkles"
        case .nebula: "staroflife.fill"
        case .waveform: "waveform.path"
        case .tunnel: "circle.circle"
        case .kaleidoscope: "hexagon.fill"
        }
    }

    func shader(size: CGSize, time: Float, energy: Float) -> Shader {
        let w = Float(size.width)
        let h = Float(size.height)
        switch self {
        case .plasma:
            return ShaderLibrary.plasma(.float2(w, h), .float(time), .float(energy))
        case .aurora:
            return ShaderLibrary.aurora(.float2(w, h), .float(time), .float(energy))
        case .nebula:
            return ShaderLibrary.nebula(.float2(w, h), .float(time), .float(energy))
        case .waveform:
            return ShaderLibrary.waveform(.float2(w, h), .float(time), .float(energy))
        case .tunnel:
            return ShaderLibrary.tunnel(.float2(w, h), .float(time), .float(energy))
        case .kaleidoscope:
            return ShaderLibrary.kaleidoscope(.float2(w, h), .float(time), .float(energy))
        }
    }
}

// MARK: - Visualizer View

struct VisualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("visualizerPreset") private var presetName: String = "Plasma"
    @AppStorage("reduceMotion") private var reduceMotion = false

    @State private var time: Float = 0
    @State private var energy: Float = 0.5
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showPresetPicker = false

    private var engine: AudioEngine { AudioEngine.shared }

    private var preset: VisualizerPreset {
        VisualizerPreset(rawValue: presetName) ?? .plasma
    }

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Shader canvas
                TimelineView(.animation(paused: !engine.isPlaying && energy < 0.01)) { timeline in
                    Rectangle()
                        .colorEffect(preset.shader(size: geo.size, time: time, energy: energy))
                }
                .ignoresSafeArea()

                // Controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(true)
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            updateTime()
            updateEnergy()
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls.toggle()
            }
            scheduleHideControls()
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else if abs(value.translation.width) > 50 {
                        // Swipe left/right to change preset
                        cyclePreset(forward: value.translation.width < 0)
                    }
                }
        )
        .onAppear {
            scheduleHideControls()
        }
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(radius: 4)
                }

                Spacer()

                Button { showPresetPicker.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preset.icon)
                        Text(preset.rawValue)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .popover(isPresented: $showPresetPicker) {
                    presetPickerContent
                }

                Spacer()

                // Placeholder for symmetry
                Color.clear.frame(width: 28, height: 28)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Bottom playback controls
            VStack(spacing: 12) {
                // Song info
                if let song = engine.currentSong {
                    VStack(spacing: 4) {
                        Text(song.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .lineLimit(1)
                        Text(song.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .shadow(radius: 4)
                            .lineLimit(1)
                    }
                } else if let station = engine.currentRadioStation {
                    Text(station.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                        .lineLimit(1)
                }

                // Transport controls
                HStack(spacing: 40) {
                    Button { engine.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .disabled(engine.queue.isEmpty)

                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                    }

                    Button { engine.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .disabled(engine.queue.isEmpty)
                }
                .foregroundStyle(.white)
                .shadow(radius: 6)
            }
            .padding(.bottom, 50)
        }
    }

    private var presetPickerContent: some View {
        VStack(spacing: 0) {
            ForEach(VisualizerPreset.allCases) { p in
                Button {
                    presetName = p.rawValue
                    showPresetPicker = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: p.icon)
                            .frame(width: 24)
                            .foregroundColor(.accentColor)
                        Text(p.rawValue)
                            .foregroundColor(.primary)
                        Spacer()
                        if p == preset {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if p != VisualizerPreset.allCases.last {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .frame(width: 220)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Animation

    private func updateTime() {
        if engine.isPlaying {
            time += 1.0 / 60.0
        }
    }

    private func updateEnergy() {
        if engine.isPlaying {
            let t = time
            // Simulated beat at ~120 BPM with harmonics and noise
            let beat = sin(t * 2.0 * .pi * 2.0) * 0.25
            let beat2 = sin(t * 2.0 * .pi * 4.0) * 0.12
            let beat3 = sin(t * 2.0 * .pi * 1.3) * 0.08
            let noise = sin(t * 17.3) * sin(t * 23.7) * 0.08
            let target = 0.55 + beat + beat2 + beat3 + noise
            energy += (max(0.15, min(1.0, target)) - energy) * 0.15
        } else {
            energy += (0.0 - energy) * 0.05
        }
    }

    private func cyclePreset(forward: Bool) {
        let all = VisualizerPreset.allCases
        guard let idx = all.firstIndex(of: preset) else { return }
        let next = forward
            ? all[(idx + 1) % all.count]
            : all[(idx - 1 + all.count) % all.count]
        presetName = next.rawValue
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }
}
