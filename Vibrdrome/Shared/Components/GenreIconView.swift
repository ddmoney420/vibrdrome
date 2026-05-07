import SwiftUI
import NukeUI

struct GenreIconView: View {
    let genre: String
    let coverArtId: String?
    @Environment(AppState.self) private var appState

    init(genre: String, coverArtId: String? = nil) {
        self.genre = genre
        self.coverArtId = coverArtId
    }

    private var style: (icon: String, colors: [Color]) {
        let key = genre.lowercased()

        // --- Rock family (check before "alternative"/"indie" so "Alt Rock" stays rock) ---
        if key.contains("rock") || key.contains("grunge") || key.contains("shoegaze")
            || key.contains("krautrock") {
            return ("guitars.fill", [.init(red: 0.8, green: 0.2, blue: 0.2),
                                     .init(red: 0.5, green: 0.1, blue: 0.1)])
        }

        // --- Metal / Hardcore ---
        if key.contains("metal") || key.contains("hardcore") || key.contains("nwobhm")
            || key.contains("sludge") || key.contains("stoner") {
            return ("bolt.fill", [.init(red: 0.3, green: 0.3, blue: 0.3),
                                  .init(red: 0.1, green: 0.1, blue: 0.1)])
        }

        // --- Punk (after rock/metal so "punk rock" matches rock, standalone punk matches here) ---
        if key.contains("punk") {
            return ("guitars.fill", [.init(red: 0.9, green: 0.3, blue: 0.1),
                                     .init(red: 0.5, green: 0.15, blue: 0.05)])
        }

        // --- Hip-Hop / Rap (before "alternative" so "Alt Hip Hop" matches hip-hop) ---
        if key.contains("hip") || key.contains("rap") || key.contains("boom bap")
            || key.contains("crunk") || key.contains("grime") || key.contains("turntablism") {
            return ("music.mic", [.init(red: 0.9, green: 0.6, blue: 0.1),
                                  .init(red: 0.6, green: 0.3, blue: 0.0)])
        }

        // --- R&B / Soul / Motown ---
        if key.contains("r&b") || key.contains("rnb") || key.contains("soul")
            || key.contains("motown") || key.contains("quiet storm")
            || key.contains("new jack swing") || key.contains("minneapolis sound") {
            return ("heart.fill", [.init(red: 0.8, green: 0.2, blue: 0.4),
                                   .init(red: 0.4, green: 0.1, blue: 0.2)])
        }

        // --- Funk / Boogie ---
        if key.contains("funk") || key.contains("boogie") {
            return ("waveform.path.ecg", [.init(red: 1.0, green: 0.5, blue: 0.0),
                                          .init(red: 0.6, green: 0.2, blue: 0.0)])
        }

        // --- Alternative / Indie ---
        if key.contains("alternative") || key.contains("indie") {
            return ("sparkle", [.init(red: 0.6, green: 0.4, blue: 0.8),
                                .init(red: 0.3, green: 0.2, blue: 0.5)])
        }

        // --- Electronic (broad) ---
        if key.contains("electronic") || key.contains("electro") || key.contains("edm")
            || key.contains("techno") || key.contains("idm") || key.contains("glitch")
            || key.contains("synthwave") || key.contains("synth") || key.contains("leftfield")
            || key.contains("breakcore") || key.contains("complextro")
            || key.contains("deconstructed") || key.contains("hyperpop")
            || key.contains("minimal synth") {
            return ("waveform", [.init(red: 0.0, green: 0.8, blue: 0.8),
                                 .init(red: 0.0, green: 0.3, blue: 0.6)])
        }

        // --- House / Dance / Disco / Club ---
        if key.contains("house") || key.contains("dance") || key.contains("disco")
            || key.contains("club") || key.contains("rave") || key.contains("garage")
            || key.contains("2-step") || key.contains("bassline")
            || key.contains("jersey") || key.contains("moombahton") || key.contains("twerk") {
            return ("figure.dance", [.init(red: 0.9, green: 0.4, blue: 0.7),
                                     .init(red: 0.5, green: 0.1, blue: 0.4)])
        }

        // --- Trance / Ambient / Chill / Downtempo ---
        if key.contains("trance") || key.contains("ambient") || key.contains("chill")
            || key.contains("downtempo") || key.contains("lo-fi") || key.contains("lounge")
            || key.contains("easy listening") || key.contains("dream pop")
            || key.contains("new age") || key.contains("drone")
            || key.contains("psybient") || key.contains("illbient") {
            return ("moon.stars.fill", [.init(red: 0.2, green: 0.2, blue: 0.6),
                                        .init(red: 0.1, green: 0.05, blue: 0.3)])
        }

        // --- Drum & Bass / Jungle / Breakbeat ---
        if key.contains("drum and bass") || key.contains("dnb") || key.contains("jungle")
            || key.contains("breakbeat") || key.contains("breaks") || key.contains("big beat")
            || key.contains("broken beat") || key.contains("jazzstep") {
            return ("bolt.horizontal.fill", [.init(red: 0.0, green: 0.7, blue: 0.3),
                                             .init(red: 0.0, green: 0.3, blue: 0.2)])
        }

        // --- Dubstep / Trap / Bass ---
        if key.contains("dubstep") || key.contains("trap") || key.contains("bass")
            || key.contains("wonky") || key.contains("future") {
            return ("speaker.wave.3.fill", [.init(red: 0.5, green: 0.0, blue: 0.8),
                                            .init(red: 0.2, green: 0.0, blue: 0.4)])
        }

        // --- Jazz ---
        if key.contains("jazz") || key.contains("big band") || key.contains("bop")
            || key.contains("third stream") {
            return ("pianokeys", [.init(red: 0.2, green: 0.3, blue: 0.6),
                                  .init(red: 0.1, green: 0.15, blue: 0.35)])
        }

        // --- Blues ---
        if key.contains("blues") || key.contains("delta") {
            return ("guitar", [.init(red: 0.1, green: 0.3, blue: 0.7),
                               .init(red: 0.05, green: 0.15, blue: 0.4)])
        }

        // --- Classical / Orchestral / Baroque ---
        if key.contains("classical") || key.contains("orchestra") || key.contains("symphony")
            || key.contains("opera") || key.contains("baroque") || key.contains("minimalism")
            || key.contains("impressionism") || key.contains("chamber")
            || key.contains("modern classical") {
            return ("music.quarternote.3", [.init(red: 0.6, green: 0.5, blue: 0.3),
                                            .init(red: 0.3, green: 0.25, blue: 0.15)])
        }

        // --- Country / Americana / Bluegrass ---
        if key.contains("country") || key.contains("americana") || key.contains("bluegrass") {
            return ("leaf.fill", [.init(red: 0.6, green: 0.5, blue: 0.2),
                                  .init(red: 0.4, green: 0.3, blue: 0.1)])
        }

        // --- Folk / Acoustic / Singer-Songwriter ---
        if key.contains("folk") || key.contains("acoustic") || key.contains("singer-songwriter") {
            return ("leaf.fill", [.init(red: 0.3, green: 0.6, blue: 0.3),
                                  .init(red: 0.15, green: 0.35, blue: 0.15)])
        }

        // --- Pop (after specific sub-genres) ---
        if key.contains("pop") {
            return ("star.fill", [.init(red: 1.0, green: 0.3, blue: 0.5),
                                  .init(red: 0.8, green: 0.1, blue: 0.3)])
        }

        // --- Reggae / Ska / Dub / Dancehall / Ragga ---
        if key.contains("reggae") || key.contains("ska") || key.contains("dub")
            || key.contains("dancehall") || key.contains("ragga") {
            return ("sun.max.fill", [.init(red: 0.2, green: 0.7, blue: 0.2),
                                     .init(red: 0.8, green: 0.6, blue: 0.0)])
        }

        // --- Latin / World / Afro ---
        if key.contains("latin") || key.contains("salsa") || key.contains("bossa")
            || key.contains("samba") || key.contains("cumbia") || key.contains("mambo")
            || key.contains("merengue") || key.contains("bolero") || key.contains("bomba")
            || key.contains("pagode") || key.contains("dabke") || key.contains("indian")
            || key.contains("afro") || key.contains("world") || key.contains("african")
            || key.contains("asian") {
            return ("globe", [.init(red: 0.9, green: 0.3, blue: 0.1),
                              .init(red: 0.7, green: 0.1, blue: 0.0)])
        }

        // --- Soundtrack / Score / Film ---
        if key.contains("soundtrack") || key.contains("score") || key.contains("film")
            || key.contains("game") {
            return ("film", [.init(red: 0.4, green: 0.4, blue: 0.5),
                             .init(red: 0.2, green: 0.2, blue: 0.25)])
        }

        // --- Spoken / Poetry / Comedy ---
        if key.contains("spoken") || key.contains("podcast") || key.contains("comedy")
            || key.contains("audiobook") || key.contains("poetry") || key.contains("slam")
            || key.contains("sketch") {
            return ("quote.bubble.fill", [.init(red: 0.4, green: 0.6, blue: 0.8),
                                          .init(red: 0.2, green: 0.3, blue: 0.5)])
        }

        // --- Gospel / Religious ---
        if key.contains("gospel") || key.contains("christian") || key.contains("worship")
            || key.contains("religious") || key.contains("christmas") {
            return ("sparkles", [.init(red: 0.7, green: 0.6, blue: 0.3),
                                 .init(red: 0.4, green: 0.3, blue: 0.15)])
        }

        // --- Experimental / Avant-Garde / Noise / Industrial ---
        if key.contains("experimental") || key.contains("avant") || key.contains("noise")
            || key.contains("industrial") || key.contains("sound collage")
            || key.contains("musique") || key.contains("plunderphonics")
            || key.contains("electroacoustic") || key.contains("field recording")
            || key.contains("non-music") || key.contains("free improvisation") {
            return ("waveform.badge.exclamationmark",
                    [.init(red: 0.4, green: 0.3, blue: 0.7),
                     .init(red: 0.2, green: 0.15, blue: 0.4)])
        }

        // --- Progressive (standalone) ---
        if key.contains("progressive") {
            return ("waveform.circle.fill", [.init(red: 0.3, green: 0.5, blue: 0.7),
                                             .init(red: 0.15, green: 0.25, blue: 0.4)])
        }

        // --- Instrumental ---
        if key.contains("instrumental") {
            return ("music.note.list", [.init(red: 0.4, green: 0.5, blue: 0.6),
                                        .init(red: 0.2, green: 0.25, blue: 0.3)])
        }

        // --- Ballad ---
        if key == "ballad" {
            return ("music.note", [.init(red: 0.5, green: 0.3, blue: 0.6),
                                   .init(red: 0.3, green: 0.15, blue: 0.35)])
        }

        // --- Psychedelic (standalone, after rock/pop subgenres matched above) ---
        if key.contains("psychedelic") || key.contains("psych") {
            return ("eye.fill", [.init(red: 0.7, green: 0.3, blue: 0.9),
                                 .init(red: 0.3, green: 0.1, blue: 0.5)])
        }

        // Default
        return ("music.note", [.init(red: 0.4, green: 0.4, blue: 0.5),
                               .init(red: 0.2, green: 0.2, blue: 0.3)])
    }

    var body: some View {
        if let coverArtId {
            LazyImage(url: appState.subsonicClient.coverArtURL(id: coverArtId, size: 300)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        let s = style
        return ZStack {
            LinearGradient(colors: s.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: s.icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
