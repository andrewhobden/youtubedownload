import Foundation

enum Sanitize {

    /// Port of `sanitize_filename` from download.py — strips characters that
    /// are illegal on common filesystems, collapses whitespace, trims, and
    /// caps length.
    static func filename(_ input: String, maxLength: Int = 200) -> String {
        // Drop the Windows-illegal characters and control characters.
        let illegal = CharacterSet(charactersIn: "<>:\"/\\|?*")
        let controls = CharacterSet.controlCharacters
        var out = input.unicodeScalars.filter {
            !illegal.contains($0) && !controls.contains($0)
        }.reduce(into: "") { $0.unicodeScalars.append($1) }

        // Collapse runs of whitespace.
        out = out.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: " ."))

        if out.count > maxLength {
            out = String(out.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        }
        return out.isEmpty ? "video" : out
    }

    /// Port of `is_valid_youtube_url`. Matches single-video, embed, short,
    /// and playlist URLs (incl. music.youtube.com).
    static func isValidYouTubeURL(_ url: String) -> Bool {
        let patterns = [
            #"(?:https?://)?(?:www\.)?youtube\.com/watch\?v=[\w-]+"#,
            #"(?:https?://)?(?:www\.)?youtu\.be/[\w-]+"#,
            #"(?:https?://)?(?:www\.)?youtube\.com/embed/[\w-]+"#,
            #"(?:https?://)?(?:www\.)?youtube\.com/v/[\w-]+"#,
            #"(?:https?://)?(?:www\.)?youtube\.com/playlist\?list=[\w-]+"#,
            #"(?:https?://)?music\.youtube\.com/playlist\?list=[\w-]+"#,
        ]
        for p in patterns {
            if url.range(of: p, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// Returns the playlist id from a URL if it contains `list=…`.
    static func playlistID(in url: String) -> String? {
        let pattern = #"[?&]list=([\w-]+)"#
        guard let range = url.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let match = String(url[range])
        // strip the leading "?list=" or "&list="
        return String(match.dropFirst(6))
    }

    /// True if the URL is a pure `/playlist?list=…` URL (no `/watch?v=`).
    static func isPlaylistOnlyURL(_ url: String) -> Bool {
        return url.range(of: #"/playlist\?list="#, options: .regularExpression) != nil
    }

    /// True if the URL is a `/watch?v=…&list=…` form (both a video id and a list).
    static func isWatchWithList(_ url: String) -> Bool {
        let hasWatch = url.range(of: #"/watch\?"#, options: .regularExpression) != nil
        let hasList = url.range(of: #"[?&]list="#, options: .regularExpression) != nil
        return hasWatch && hasList
    }
}
