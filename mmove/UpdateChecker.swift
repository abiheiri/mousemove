import Foundation

/// Checks GitHub for a newer mmove release.
struct UpdateChecker {
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
