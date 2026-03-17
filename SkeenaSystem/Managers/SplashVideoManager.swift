// Bend Fly Shop

import Foundation

enum SplashVideoManager {

    private static let videoExtensions: Set<String> = ["mp4", "mov"]

    /// Discovers all .mp4 and .mov splash videos in the app bundle.
    ///
    /// First checks for a "Media" folder reference in the bundle. If that
    /// isn't found (e.g. files were added as a group rather than a folder
    /// reference), falls back to scanning the entire bundle for video files.
    static func discoverVideos() -> [URL] {
        // Approach 1: folder reference named "Media"
        if let mediaURL = Bundle.main.url(forResource: "Media", withExtension: nil) {
            AppLogging.log("[SplashVideo] Media folder reference URL: \(mediaURL.path)", level: .debug, category: .auth)
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                AppLogging.log("[SplashVideo] Media folder contents count: \(contents.count)", level: .debug, category: .auth)
                let videos = contents.filter { videoExtensions.contains($0.pathExtension.lowercased()) }
                if videos.isEmpty {
                    AppLogging.log("[SplashVideo] Media folder found but contains 0 matching videos (.mp4/.mov)", level: .debug, category: .auth)
                } else {
                    let names = videos.map { $0.lastPathComponent }.joined(separator: ", ")
                    AppLogging.log("[SplashVideo] Found \(videos.count) video(s) in Media folder: [\(names)]", level: .debug, category: .auth)
                    return videos
                }
            } catch {
                AppLogging.log("[SplashVideo] Failed reading Media folder contents: \(error.localizedDescription)", level: .error, category: .auth)
            }
        } else {
            AppLogging.log("[SplashVideo] Media folder reference NOT found in bundle", level: .debug, category: .auth)
        }

        // Approach 2: scan the bundle for any .mp4 / .mov files
        AppLogging.log("[SplashVideo] Fallback scan across bundle starting", level: .debug, category: .auth)
        var videos: [URL] = []
        for ext in videoExtensions {
            let found = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            if found.isEmpty {
                AppLogging.log("[SplashVideo] No files with extension .\(ext) found in bundle", level: .debug, category: .auth)
            } else {
                let names = found.map { $0.lastPathComponent }.joined(separator: ", ")
                AppLogging.log("[SplashVideo] Found \(found.count) .\(ext) file(s): [\(names)]", level: .debug, category: .auth)
                videos.append(contentsOf: found)
            }
        }

        AppLogging.log("[SplashVideo] Found \(videos.count) video(s) in bundle", level: .debug, category: .auth)
        return videos
    }

    /// Returns a random video URL from the bundle, or nil if none are available.
    static func randomVideo() -> URL? {
        let vids = discoverVideos()
        let chosen = vids.randomElement()
        if let chosen {
            AppLogging.log("[SplashVideo] Randomly selected video: \(chosen.lastPathComponent)", level: .debug, category: .auth)
        } else {
            AppLogging.log("[SplashVideo] No videos available to select", level: .debug, category: .auth)
        }
        return chosen
    }
}
