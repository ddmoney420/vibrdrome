import SwiftUI

/// One third-party component shown on the Acknowledgements screen. The license
/// text itself is a verbatim bundled resource (`<resource>.txt`) — never
/// summarized in code.
struct Acknowledgement: Identifiable {
    let id = UUID()
    let title: String
    let license: String
    let linkage: String
    let resource: String      // bundled .txt basename
    let note: String?         // shown above the license text (e.g. projectM LGPL/source/relink)

    init(_ title: String, license: String, linkage: String, resource: String, note: String? = nil) {
        self.title = title
        self.license = license
        self.linkage = linkage
        self.resource = resource
        self.note = note
    }
}

/// Settings ▸ About ▸ Acknowledgements. Lists all bundled third-party code and
/// opens each component's verbatim license text. Phase 2E.
struct AcknowledgementsView: View {
    private let projectMNote = """
    Vibrdrome uses projectM under the GNU Lesser General Public License v2.1, \
    dynamically linked (the engine is a separate, replaceable @rpath dynamic \
    library). projectM source: https://github.com/projectM-visualizer/projectm \
    (pinned commit 4d28493). The build — including the GLES compatibility patch — \
    is reproducible via scripts/build-projectm.sh in the public Vibrdrome \
    repository, satisfying the LGPL relink/source provisions.
    """

    private var acknowledgements: [Acknowledgement] {
        [
            Acknowledgement("projectM", license: "LGPL-2.1", linkage: "Dynamically linked",
                            resource: "projectM-LGPL-2.1", note: projectMNote),
            Acknowledgement("MetalANGLE / ANGLE", license: "BSD-3-Clause", linkage: "Dynamically linked",
                            resource: "ANGLE-BSD"),
            Acknowledgement("GLM", license: "MIT / Happy Bunny", linkage: "Bundled in projectM",
                            resource: "glm"),
            Acknowledgement("glad", license: "WTFPL / CC0-1.0 / Apache-2.0", linkage: "Bundled in projectM",
                            resource: "glad"),
            Acknowledgement("stb_image", license: "MIT / Public Domain", linkage: "Bundled in projectM",
                            resource: "stb_image"),
            Acknowledgement("projectM-eval", license: "MIT", linkage: "Bundled in projectM",
                            resource: "projectm-eval-MIT"),
            Acknowledgement("hlslparser", license: "MIT", linkage: "Bundled in projectM",
                            resource: "hlslparser-MIT"),
            Acknowledgement("Nuke", license: "MIT", linkage: "Swift Package",
                            resource: "Nuke-MIT"),
            Acknowledgement("KeychainAccess", license: "MIT", linkage: "Swift Package",
                            resource: "KeychainAccess-MIT"),
            Acknowledgement("Vibrdrome MilkDrop presets", license: "Original (Vibrdrome)", linkage: "Bundled resources",
                            resource: "Vibrdrome-presets"),
        ]
    }

    var body: some View {
        List(acknowledgements) { ack in
            NavigationLink {
                LicenseDetailView(acknowledgement: ack)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ack.title)
                    Text("\(ack.license) · \(ack.linkage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Acknowledgements")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Shows a component's verbatim bundled license text (read-only, selectable).
struct LicenseDetailView: View {
    let acknowledgement: Acknowledgement

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: acknowledgement.resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text unavailable."
        }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let note = acknowledgement.note {
                    Text(note)
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                Text(licenseText)
                    .font(.footnote)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(acknowledgement.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
