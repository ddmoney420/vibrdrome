import SwiftUI

// MARK: - Visualizer Presets

enum VisualizerPreset: String, CaseIterable, Identifiable {
    case plasma = "Plasma"
    case aurora = "Aurora"
    case nebula = "Nebula"
    case waveform = "Waveform"
    case tunnel = "Tunnel"
    case kaleidoscope = "Kaleidoscope"
    case particles = "Particles"
    case fractal = "Fractal"
    case fluid = "Fluid"
    case rings = "Rings"
    case spectrum = "Spectrum"
    case vortex = "Vortex"
    case lavaLamp = "Lava Lamp"
    case starfield = "Starfield"
    case ripple = "Ripple"
    case fireflies = "Fireflies"
    case prism = "Prism"
    case ocean = "Ocean"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .plasma: "flame.fill"
        case .aurora: "sparkles"
        case .nebula: "staroflife.fill"
        case .waveform: "waveform.path"
        case .tunnel: "circle.circle"
        case .kaleidoscope: "hexagon.fill"
        case .particles: "sparkle"
        case .fractal: "camera.filters"
        case .fluid: "drop.fill"
        case .rings: "circles.hexagonpath"
        case .spectrum: "chart.bar.fill"
        case .vortex: "tornado"
        case .lavaLamp: "lamp.desk.fill"
        case .starfield: "star.fill"
        case .ripple: "water.waves"
        case .fireflies: "light.max"
        case .prism: "triangle.fill"
        case .ocean: "cloud.rain.fill"
        }
    }

    private var shaderFunction: ShaderFunction {
        switch self {
        case .plasma: ShaderLibrary.plasma
        case .aurora: ShaderLibrary.aurora
        case .nebula: ShaderLibrary.nebula
        case .waveform: ShaderLibrary.waveform
        case .tunnel: ShaderLibrary.tunnel
        case .kaleidoscope: ShaderLibrary.kaleidoscope
        case .particles: ShaderLibrary.particles
        case .fractal: ShaderLibrary.fractal
        case .fluid: ShaderLibrary.fluid
        case .rings: ShaderLibrary.rings
        case .spectrum: ShaderLibrary.spectrumVis
        case .vortex: ShaderLibrary.vortex
        case .lavaLamp: ShaderLibrary.lavaLamp
        case .starfield: ShaderLibrary.starfield
        case .ripple: ShaderLibrary.ripple
        case .fireflies: ShaderLibrary.fireflies
        case .prism: ShaderLibrary.prism
        case .ocean: ShaderLibrary.ocean
        }
    }

    // swiftlint:disable:next function_parameter_count
    func shader(size: CGSize, time: Float, energy: Float,
                bass: Float, mid: Float, treble: Float) -> Shader {
        shaderFunction(
            .float2(Float(size.width), Float(size.height)),
            .float(time), .float(energy), .float(bass), .float(mid), .float(treble)
        )
    }
}

// MARK: - Visualizer View

struct VisualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserDefaultsKeys.visualizerPreset) private var presetName: String = "Plasma"
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    @AppStorage(UserDefaultsKeys.visualizerWarningShown) private var warningShown = false

    @State private var time: Float = 0
    @State private var energy: Float = 0.5
    @State private var bass: Float = 0
    @State private var mid: Float = 0
    @State private var treble: Float = 0
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showPresetPicker = false
    @State private var showWarning = false
    #if os(macOS)
    @State private var nsWindow: NSWindow?
    #endif

    private var engine: AudioEngine { AudioEngine.shared }
    private let audioSpectrum = AudioSpectrum.shared

    private var preset: VisualizerPreset {
        VisualizerPreset(rawValue: presetName) ?? .plasma
    }

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Shader canvas
                TimelineView(.animation(paused: !engine.isPlaying && energy < 0.01)) { _ in
                    Rectangle()
                        .colorEffect(preset.shader(
                            size: geo.size, time: time, energy: energy,
                            bass: bass, mid: mid, treble: treble))
                }
                .ignoresSafeArea()
                #if os(macOS)
                .background { WindowReader { nsWindow = $0 }.allowsHitTesting(false) }
                #endif

                // Controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            updateTime()
            updateSpectrum()
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
                        cyclePreset(forward: value.translation.width < 0)
                    }
                }
        )
        .onAppear {
            engine.visualizerActive = true
            // Reapply tap if EQ is off but we need FFT data
            if !engine.eqEnabled, let item = engine.activePlayer?.currentItem {
                engine.applyEQTapIfNeeded(to: item)
            }
            scheduleHideControls()
            if !warningShown {
                showWarning = true
            }
        }
        .alert("Photosensitivity Warning", isPresented: $showWarning) {
            Button("Continue") { }
            Button("Don't Show Again") {
                warningShown = true
            }
            Button("Close Visualizer", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("""
            This visualizer contains flashing lights and rapid color changes \
            that may cause discomfort or trigger seizures in people with \
            photosensitive epilepsy. You can disable the visualizer in \
            Settings > Accessibility.
            """)
        }
        .onDisappear {
            engine.visualizerActive = false
            AudioSpectrum.shared.reset()
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

                #if os(macOS)
                Button {
                    nsWindow?.collectionBehavior.insert(.fullScreenPrimary)
                    nsWindow?.toggleFullScreen(nil)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(radius: 4)
                }
                #else
                Color.clear.frame(width: 28, height: 28)
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Bottom playback controls
            VStack(spacing: 12) {
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
        ScrollView {
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
        }
        .frame(width: 220)
        .frame(maxHeight: 500)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Animation

    private func updateTime() {
        if engine.isPlaying {
            time += 1.0 / 60.0
        }
    }

    private func updateSpectrum() {
        if engine.isPlaying {
            // Read real FFT data from the audio tap
            let spectrum = audioSpectrum
            let realBass = spectrum.bass
            let realMid = spectrum.mid
            let realTreble = spectrum.treble
            let realEnergy = spectrum.energy

            // Use real data if available, fall back to simulated
            if realEnergy > 0.001 {
                let lerp: Float = 0.2
                bass += (realBass - bass) * lerp
                mid += (realMid - mid) * lerp
                treble += (realTreble - treble) * lerp
                energy += (realEnergy - energy) * lerp
            } else {
                // Fallback: simulated energy when no FFT data
                let t = time
                let beat = sin(t * 2.0 * .pi * 2.0) * 0.25
                let beat2 = sin(t * 2.0 * .pi * 4.0) * 0.12
                let noise = sin(t * 17.3) * sin(t * 23.7) * 0.08
                let target = 0.55 + beat + beat2 + noise
                energy += (max(0.15, min(1.0, target)) - energy) * 0.15
                bass = energy * 1.2
                mid = energy
                treble = energy * 0.8
            }
        } else {
            energy += (0.0 - energy) * 0.05
            bass += (0.0 - bass) * 0.05
            mid += (0.0 - mid) * 0.05
            treble += (0.0 - treble) * 0.05
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
