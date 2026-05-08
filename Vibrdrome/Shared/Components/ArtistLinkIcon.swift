#if os(macOS)
import SwiftUI

struct ArtistLinkIcon: View {
    let link: ArtistExternalLink

    var body: some View {
        Group {
            if let asset = link.asset, !asset.isEmpty {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else if let badge = link.badge, !badge.isEmpty {
                Text(badge.prefix(2))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16, height: 16)
            }
        }
        .padding(9)
        .background(.ultraThinMaterial, in: Circle())
        .foregroundStyle(.white)
    }
}
#endif
