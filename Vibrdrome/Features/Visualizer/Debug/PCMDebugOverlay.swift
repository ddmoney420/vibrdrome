#if DEBUG
import SwiftUI

/// DEBUG-only overlay (Phase 1D) showing the visualizer PCM pipeline's health.
/// Mounted on Now Playing behind a triple-tap; not compiled into release.
/// Its appearance drives the whole dev pipeline: `start()` force-enables the PCM
/// source + drains the ring; `stop()` disables + resets it.
struct PCMDebugOverlay: View {
    @State private var monitor = PCMDebugMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PCM DEBUG").font(.caption2.bold())
            row("produced", "\(Int(monitor.producedRate)) fps")
            row("consumed", "\(Int(monitor.consumedRate)) fps")
            row("fill", "\(monitor.fillFrames) / \(monitor.capacityFrames)")
            row("overflow", "\(monitor.overflowFrames)")
            row("underrun", "\(monitor.underrunReads)")
            row("source", "\(Int(monitor.sampleRate)) Hz · \(monitor.channelCount)ch")
            if monitor.overProductionWarning {
                Text("⚠︎ produced > 1.5× sample rate")
                    .foregroundStyle(.red)
                    .font(.caption2.bold())
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .allowsHitTesting(false)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            Text(value)
        }
    }
}
#endif
