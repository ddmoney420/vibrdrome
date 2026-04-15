import SwiftData
import SwiftUI

// MARK: - Filter UI & Logic

extension SearchView {
    var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    label: selectedGenre ?? "Genre",
                    isActive: selectedGenre != nil,
                    showPicker: $showGenrePicker,
                    onClear: { selectedGenre = nil }
                )
                .popover(isPresented: $showGenrePicker) {
                    filterPickerList(
                        title: "Genre",
                        options: availableGenres,
                        selection: $selectedGenre,
                        isPresented: $showGenrePicker
                    )
                }

                filterChip(
                    label: selectedYear.map { "\($0)" } ?? "Year",
                    isActive: selectedYear != nil,
                    showPicker: $showYearPicker,
                    onClear: { selectedYear = nil }
                )
                .popover(isPresented: $showYearPicker) {
                    filterPickerList(
                        title: "Year",
                        options: yearOptions,
                        selection: Binding(
                            get: { selectedYear.map { "\($0)" } },
                            set: { selectedYear = $0.flatMap { Int($0) } }
                        ),
                        isPresented: $showYearPicker
                    )
                }

                filterChip(
                    label: selectedFormat ?? "Format",
                    isActive: selectedFormat != nil,
                    showPicker: $showFormatPicker,
                    onClear: { selectedFormat = nil }
                )
                .popover(isPresented: $showFormatPicker) {
                    filterPickerList(
                        title: "Format",
                        options: formatOptions,
                        selection: $selectedFormat,
                        isPresented: $showFormatPicker
                    )
                }

                if hasActiveFilters {
                    Button {
                        withAnimation {
                            selectedGenre = nil
                            selectedYear = nil
                            selectedFormat = nil
                        }
                    } label: {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    func filterChip(label: String, isActive: Bool, showPicker: Binding<Bool>,
                    onClear: @escaping () -> Void) -> some View {
        Button {
            showPicker.wrappedValue = true
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
                if isActive {
                    Button {
                        withAnimation { onClear() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
            .foregroundColor(isActive ? .accentColor : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func filterPickerList(title: String, options: [String], selection: Binding<String?>,
                          isPresented: Binding<Bool>) -> some View {
        NavigationStack {
            List(options, id: \.self) { option in
                Button {
                    withAnimation {
                        selection.wrappedValue = option
                        isPresented.wrappedValue = false
                    }
                } label: {
                    HStack {
                        Text(option)
                            .foregroundColor(.primary)
                        Spacer()
                        if selection.wrappedValue == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented.wrappedValue = false
                    }
                }
            }
        }
        .frame(minWidth: 250, idealHeight: 400)
    }

    var yearOptions: [String] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (1950...currentYear).reversed().map { "\($0)" }
    }

    func applyFilters(to results: SearchResult3) -> SearchResult3 {
        guard hasActiveFilters else { return results }

        let filteredSongs = results.song?.filter { song in
            if let genre = selectedGenre, song.genre?.caseInsensitiveCompare(genre) != .orderedSame {
                return false
            }
            if let year = selectedYear, song.year != year {
                return false
            }
            if let format = selectedFormat,
               song.suffix?.caseInsensitiveCompare(format) != .orderedSame {
                return false
            }
            return true
        }

        let filteredAlbums = results.album?.filter { album in
            if let genre = selectedGenre, album.genre?.caseInsensitiveCompare(genre) != .orderedSame {
                return false
            }
            if let year = selectedYear, album.year != year {
                return false
            }
            // Format filter does not apply to albums
            return selectedFormat == nil
        }

        // Artists are not filtered (no genre/year/format on the Artist model)
        let filteredArtists = (selectedGenre != nil || selectedYear != nil || selectedFormat != nil)
            ? nil : results.artist

        return SearchResult3(
            artist: filteredArtists,
            album: filteredAlbums?.isEmpty == true ? nil : filteredAlbums,
            song: filteredSongs?.isEmpty == true ? nil : filteredSongs
        )
    }

    func loadGenres() async {
        // Try local SwiftData first
        let allSongs = (try? modelContext.fetch(FetchDescriptor<CachedSong>())) ?? []
        let localGenres = Set(allSongs.compactMap(\.genre).filter { !$0.isEmpty })
        if !localGenres.isEmpty {
            availableGenres = localGenres.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return
        }

        // Fall back to API
        do {
            let genres = try await appState.subsonicClient.getGenres()
            availableGenres = genres
                .map(\.value)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            // Non-critical — filter just won't have genre options
        }
    }
}
