import Foundation

public struct AccountInfo: Equatable {
    public let emailAddress: String?
    public let planLabel: String?
}

/// Reads only non-sensitive account profile fields (email, plan tier) from
/// Claude Code's local config file. Deliberately narrow: it decodes just
/// the two fields it needs from `oauthAccount` and ignores everything
/// else in that object — in particular, this never touches the OAuth
/// token itself (which lives in the Keychain, not this file) or any other
/// credential material.
public enum AccountInfoReader {
    public static func read() -> AccountInfo {
        let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")

        guard let data = try? Data(contentsOf: configURL) else {
            return AccountInfo(emailAddress: nil, planLabel: nil)
        }

        struct OAuthAccount: Decodable {
            let emailAddress: String?
            let seatTier: String?
        }
        struct Config: Decodable {
            let oauthAccount: OAuthAccount?
        }

        guard let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return AccountInfo(emailAddress: nil, planLabel: nil)
        }

        return AccountInfo(
            emailAddress: config.oauthAccount?.emailAddress,
            planLabel: config.oauthAccount?.seatTier.map(formatSeatTier)
        )
    }

    private static func formatSeatTier(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("team") {
            return "Team plan"
        }
        if lower.contains("max") {
            if lower.contains("20x") { return "Max 20x plan" }
            if lower.contains("5x") { return "Max 5x plan" }
            return "Max plan"
        }
        if lower.contains("pro") {
            return "Pro plan"
        }
        return raw.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
