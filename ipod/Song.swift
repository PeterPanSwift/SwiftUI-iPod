import AVFoundation

struct Song: Identifiable, Hashable, Sendable {
    static let unknownArtist = "Unknown Artist"
    static let unknownAlbum = "Unknown Album"

    let id: String
    let url: URL
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval

    /// Reads every MP3 bundled with the app and pulls title / artist / album from its ID3 tags,
    /// falling back to the file name when a tag is missing.
    static func loadBundled() async -> [Song] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil) ?? []
        var songs: [Song] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            let metadata = (try? await asset.load(.commonMetadata)) ?? []

            func string(_ identifier: AVMetadataIdentifier) async -> String? {
                let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first
                guard let value = try? await item?.load(.stringValue) else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            let fileName = url.deletingPathExtension().lastPathComponent
            let duration = (try? await asset.load(.duration))?.seconds ?? 0
            songs.append(Song(
                id: url.lastPathComponent,
                url: url,
                title: await string(.commonIdentifierTitle) ?? fileName,
                artist: await string(.commonIdentifierArtist) ?? unknownArtist,
                album: await string(.commonIdentifierAlbumName) ?? unknownAlbum,
                duration: duration.isFinite ? duration : 0
            ))
        }
        return songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
