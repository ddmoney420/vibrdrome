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

    func shader(size: CGSize, input: ShaderInput) -> Shader {
        if self == .spectrum {
            return ShaderLibrary.spectrumVis(
                .float2(Float(size.width), Float(size.height)),
                .float(input.time), .float(input.energy),
                .float(input.bass), .float(input.mid), .float(input.treble),
                .floatArray(input.bands),
                .floatArray(input.peaks)
            )
        }
        return shaderFunction(
            .float2(Float(size.width), Float(size.height)),
            .float(input.time), .float(input.energy),
            .float(input.bass), .float(input.mid), .float(input.treble),
            .floatArray(input.bands)
        )
    }
}

// MARK: - Visualizer Mode

/// The two visualizer backends. Classic = SwiftUI Metal shaders (default);
/// MilkDrop = projectM (Phase 2). Persisted via `UserDefaultsKeys.visualizerMode`.
enum VisualizerMode: String, CaseIterable, Identifiable {
    case classic
    case milkdrop
    var id: String { rawValue }
    var title: String { self == .classic ? "Classic" : "MilkDrop" }
    var icon: String { self == .classic ? "waveform" : "waveform.circle" }
}

/// Pure mode-gating logic, factored out of the view so it is unit-testable
/// without UI or a GL context (see `VisualizerModeResolverTests`).
enum VisualizerModeResolver {
    /// Whether MilkDrop may be chosen right now. MilkDrop is hard-gated off on the
    /// iOS simulator (ANGLE GLES-on-Metal is unreliable there) and suppressed by
    /// Reduce Motion / Disable Visualizer.
    static func milkdropSelectable(reduceMotion: Bool, disableVisualizer: Bool, isSimulator: Bool) -> Bool {
        if isSimulator { return false }
        return !reduceMotion && !disableVisualizer
    }

    /// What actually renders: MilkDrop only if selected AND currently selectable;
    /// otherwise Classic (covers "MilkDrop was chosen earlier but is now gated").
    static func effectiveMode(selected: VisualizerMode, reduceMotion: Bool,
                              disableVisualizer: Bool, isSimulator: Bool) -> VisualizerMode {
        let selectable = milkdropSelectable(
            reduceMotion: reduceMotion, disableVisualizer: disableVisualizer, isSimulator: isSimulator)
        return (selected == .milkdrop && selectable) ? .milkdrop : .classic
    }
}

/// Grouped audio-reactive parameters for shader rendering
struct ShaderInput {
    let time: Float
    let energy: Float
    let bass: Float
    let mid: Float
    let treble: Float
    /// Per-band FFT magnitudes (count = AudioSpectrum.bandCount). Available to every shader;
    /// most currently ignore it and animate from the scalar bass/mid/treble values.
    let bands: [Float]
    /// Per-band peak-hold values — instant-attack, slow-decay. Consumed only by the Spectrum preset.
    let peaks: [Float]
}

// MARK: - Visualizer View

struct VisualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserDefaultsKeys.visualizerPreset) private var presetName: String = "Plasma"
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    @AppStorage(UserDefaultsKeys.visualizerWarningShown) private var warningShown = false
    @AppStorage(UserDefaultsKeys.disableVisualizer) private var disableVisualizer = false
    @AppStorage(UserDefaultsKeys.visualizerMode) private var selectedModeRaw = VisualizerMode.classic.rawValue
    @AppStorage(UserDefaultsKeys.visualizerMilkdropWarningShown) private var milkdropWarningShown = false
    @AppStorage(UserDefaultsKeys.milkdropPresetName) private var milkdropPresetName = "vibrdrome_plasma"
    @AppStorage(UserDefaultsKeys.milkdropShuffle) private var milkdropShuffle = true
    @AppStorage(UserDefaultsKeys.milkdropPresetDuration) private var milkdropPresetDuration = 20

    @State private var time: Float = 0
    @State private var energy: Float = 0.5
    @State private var bass: Float = 0
    @State private var mid: Float = 0
    @State private var treble: Float = 0
    @State private var bands: [Float] = Array(repeating: 0, count: AudioSpectrum.bandCount)
    @State private var peaks: [Float] = Array(repeating: 0, count: AudioSpectrum.bandCount)
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showPresetPicker = false
    @State private var showWarning = false
    @State private var showMilkdropWarning = false
    @State private var milkdropElapsed: Double = 0
    #if os(macOS)
    @State private var nsWindow: NSWindow?
    #endif

    private var engine: AudioEngine { AudioEngine.shared }
    private let audioSpectrum = AudioSpectrum.shared

    private var preset: VisualizerPreset {
        VisualizerPreset(rawValue: presetName) ?? .plasma
    }

    private var selectedMode: VisualizerMode { VisualizerMode(rawValue: selectedModeRaw) ?? .classic }

    private let milkdropLibrary = ProjectMPresetLibrary()
    private var currentMilkdropPreset: ProjectMPreset? {
        milkdropLibrary.preset(id: milkdropPresetName) ?? milkdropLibrary.presets.first
    }

    private var isSimulatorBuild: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private var milkdropSelectable: Bool {
        VisualizerModeResolver.milkdropSelectable(
            reduceMotion: reduceMotion, disableVisualizer: disableVisualizer, isSimulator: isSimulatorBuild)
    }

    private var effectiveMode: VisualizerMode {
        VisualizerModeResolver.effectiveMode(
            selected: selectedMode, reduceMotion: reduceMotion,
            disableVisualizer: disableVisualizer, isSimulator: isSimulatorBuild)
    }

    private var milkdropUnavailableReason: String? {
        if isSimulatorBuild { return "Device only (not in Simulator)" }
        if disableVisualizer { return "Visualizer is disabled in Settings" }
        if reduceMotion { return "Unavailable with Reduce Motion" }
        return nil
    }

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Visualizer canvas — Classic (Metal shaders) or MilkDrop (projectM).
                if effectiveMode == .milkdrop {
                    ProjectMVisualizerSurface(presetURL: currentMilkdropPreset?.url)
                        .ignoresSafeArea()
                } else {
                    TimelineView(.animation(paused: !engine.isPlaying && energy < 0.01)) { _ in
                        Rectangle()
                            .colorEffect(preset.shader(
                                size: geo.size,
                                input: ShaderInput(
                                    time: time, energy: energy,
                                    bass: bass, mid: mid, treble: treble,
                                    bands: bands, peaks: peaks)))
                    }
                    .ignoresSafeArea()
                }

                // Controls overlay
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
            #if os(macOS)
            // Capture the window in both modes (Classic + MilkDrop) for the
            // fullscreen toggle.
            .background { WindowReader { nsWindow = $0 }.allowsHitTesting(false) }
            #endif
        }
        #if os(iOS)
        .statusBarHidden(true)
        #endif
        .onReceive(timer) { _ in
            if effectiveMode == .milkdrop {
                // Swift-managed preset auto-advance. Only while playing; duration 0 = off.
                guard milkdropPresetDuration > 0, engine.isPlaying else { return }
                milkdropElapsed += 1.0 / 60.0
                if milkdropElapsed >= Double(milkdropPresetDuration) {
                    milkdropElapsed = 0
                    advanceMilkdropPreset()
                }
            } else if !reduceMotion {
                // MilkDrop drives its own PCM ring; only Classic needs the FFT/time pump.
                updateTime()
                updateSpectrum()
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.5)) {
                showControls.toggle()
            }
            // Only auto-hide when showing controls; tapping to hide is instant (user intent)
            if showControls {
                scheduleHideControls()
            } else {
                hideControlsTask?.cancel()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else if abs(value.translation.width) > 50 {
                        if effectiveMode == .classic {
                            cyclePreset(forward: value.translation.width < 0)
                        } else {
                            cycleMilkdropPreset(forward: value.translation.width < 0)
                        }
                    }
                }
        )
        .onAppear {
            engine.visualizerActive = true
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
        .alert("MilkDrop Visualizer", isPresented: $showMilkdropWarning) {
            Button("Enable MilkDrop") {
                milkdropWarningShown = true
                selectedModeRaw = VisualizerMode.milkdrop.rawValue
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("""
            MilkDrop renders intense, rapidly-changing visuals that may be more \
            likely to trigger discomfort or seizures in people with photosensitive \
            epilepsy. You can switch back to Classic anytime, or disable the \
            visualizer in Settings > Accessibility.
            """)
        }
        .onChange(of: showPresetPicker) { _, isOpen in
            if isOpen {
                hideControlsTask?.cancel()
            } else if showControls {
                scheduleHideControls()
            }
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
                .accessibilityIdentifier("visualizerCloseButton")

                Spacer()

                Button { showPresetPicker.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: effectiveMode == .milkdrop ? VisualizerMode.milkdrop.icon : preset.icon)
                        Text(effectiveMode == .milkdrop ? "MilkDrop" : preset.rawValue)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("visualizerPresetPicker")
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
                        Text(song.displayArtist ?? "")
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
                    Button { engine.previous(); scheduleHideControls() } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("visualizerPreviousButton")
                    .disabled(engine.queue.isEmpty)

                    Button { engine.togglePlayPause(); scheduleHideControls() } label: {
                        Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                    }
                    .accessibilityIdentifier("visualizerPlayPauseButton")

                    Button { engine.next(); scheduleHideControls() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .accessibilityIdentifier("visualizerNextButton")
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
                // Mode section (Classic / MilkDrop)
                modeRow(.classic)
                modeRow(.milkdrop)
                Divider().padding(.leading, 52)

                // Preset list (Classic) or a MilkDrop note (single preset in 2C)
                if effectiveMode == .classic {
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
                } else {
                    milkdropControls
                }
            }
        }
        .frame(width: 220)
        .frame(maxHeight: 500)
        .presentationCompactAdaptation(.popover)
    }

    private func modeRow(_ mode: VisualizerMode) -> some View {
        let disabled = (mode == .milkdrop) && !milkdropSelectable
        return Button {
            selectMode(mode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .frame(width: 24)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .foregroundColor(disabled ? .secondary : .primary)
                    if disabled, let reason = milkdropUnavailableReason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if mode == selectedMode && !disabled {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier(mode == .milkdrop ? "visualizerModeMilkDrop" : "visualizerModeClassic")
    }

    /// Switch visualizer mode. The first MilkDrop selection routes through the
    /// photosensitivity re-warning; subsequent selections switch directly.
    private func selectMode(_ mode: VisualizerMode) {
        guard mode != selectedMode else { showPresetPicker = false; return }
        if mode == .milkdrop {
            guard milkdropSelectable else { return }   // disabled row can't reach here anyway
            if !milkdropWarningShown {
                showPresetPicker = false
                showMilkdropWarning = true             // gate the FIRST switch
                return
            }
            selectedModeRaw = VisualizerMode.milkdrop.rawValue
        } else {
            selectedModeRaw = VisualizerMode.classic.rawValue
        }
        showPresetPicker = false
    }

    // MARK: - MilkDrop preset controls (Phase 2D)

    @ViewBuilder
    private var milkdropControls: some View {
        Toggle("Shuffle", isOn: $milkdropShuffle)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityIdentifier("milkdropShuffleToggle")

        HStack {
            Text("Duration")
            Spacer()
            Picker("Duration", selection: $milkdropPresetDuration) {
                Text("Off").tag(0)
                Text("10s").tag(10)
                Text("20s").tag(20)
                Text("30s").tag(30)
                Text("60s").tag(60)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityIdentifier("milkdropDurationPicker")

        Divider().padding(.leading, 52)

        VStack(spacing: 0) {
            ForEach(milkdropLibrary.presets) { p in
                Button {
                    selectMilkdropPreset(p.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle")
                            .frame(width: 24)
                            .foregroundColor(.accentColor)
                        Text(p.displayName)
                            .foregroundColor(.primary)
                        Spacer()
                        if p.id == currentMilkdropPreset?.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if p != milkdropLibrary.presets.last {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .accessibilityIdentifier("milkdropPresetList")
    }

    private func selectMilkdropPreset(_ id: String) {
        milkdropPresetName = id
        milkdropElapsed = 0          // reset the auto-advance clock on manual choice
        showPresetPicker = false
    }

    /// Auto-advance target: random (shuffle) or sequential next.
    private func advanceMilkdropPreset() {
        let nextPreset = milkdropShuffle
            ? milkdropLibrary.random(excluding: milkdropPresetName)
            : milkdropLibrary.next(after: milkdropPresetName)
        if let nextPreset { milkdropPresetName = nextPreset.id }
    }

    /// Manual swipe cycle — always sequential (predictable direction), regardless
    /// of shuffle. Resets the auto-advance clock.
    private func cycleMilkdropPreset(forward: Bool) {
        let target = forward
            ? milkdropLibrary.next(after: milkdropPresetName)
            : milkdropLibrary.previous(before: milkdropPresetName)
        if let target { milkdropPresetName = target.id }
        milkdropElapsed = 0
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

            // Always copy the real per-band array — the Spectrum preset renders
            // one bar per band directly. If the tap is not delivering (bands all
            // zero) the bars flatline, which is the correct diagnostic.
            bands = audioSpectrum.bands
            // Peak-hold: instant attack, slow linear decay (0.006 / frame ≈ 0.36/s).
            for i in peaks.indices {
                if bands[i] > peaks[i] {
                    peaks[i] = bands[i]
                } else {
                    peaks[i] = max(0, peaks[i] - 0.006)
                }
            }
        } else {
            energy += (0.0 - energy) * 0.05
            bass += (0.0 - bass) * 0.05
            mid += (0.0 - mid) * 0.05
            treble += (0.0 - treble) * 0.05
            for i in bands.indices { bands[i] *= 0.95 }
            for i in peaks.indices { peaks[i] *= 0.9 }
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
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            // Don't auto-hide while a popover or menu is open
            guard !showPresetPicker else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                showControls = false
            }
        }
    }
}
