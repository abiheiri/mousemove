import Foundation

/// Checks GitHub for a newer mmove release.
struct UpdateChecker {
    /// A newer release than the one running.
    struct LatestRelease: Equatable {
        let version: String
        let url: URL
    }

    enum CheckResult: Equatable {
        case updateAvailable(LatestRelease)
        case upToDate
        case failed(String)
    }

    private static let releasesURL = URL(string: "https://api.github.com/repos/abiheiri/mousemove/releases/latest")!

    /// The running app's marketing version, e.g. "1.3.2".
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Injectable for tests: returns the response body for the releases URL.
    var fetchData: (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "UpdateChecker", code: code, userInfo: [
                NSLocalizedDescriptionKey: "GitHub returned HTTP \(code)",
            ])
        }
        return data
    }

    /// Version to compare against; injectable for tests.
    var currentVersion: String = UpdateChecker.appVersion

    /// Queries the latest GitHub release and compares it to currentVersion.
    func check() async -> CheckResult {
        do {
            let data = try await fetchData(Self.releasesURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let urlString = json["html_url"] as? String,
                  let url = URL(string: urlString) else {
                return .failed("Unexpected response from GitHub")
            }
            let latest = String(tag.drop(while: { $0 == "v" || $0 == "V" }))
            guard Self.compare(latest, currentVersion) == .orderedDescending else {
                return .upToDate
            }
            return .updateAvailable(LatestRelease(version: latest, url: url))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Component-wise numeric version comparison. A leading "v"/"V" is
    /// ignored, missing components count as 0, so "v1.4.0" == "1.4.0",
    /// "1.4" == "1.4.0", and "1.10.0" > "1.3.2".
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = components(a), pb = components(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version
            .drop(while: { $0 == "v" || $0 == "V" })
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
