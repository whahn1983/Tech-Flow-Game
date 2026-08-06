//
//  LegacyPaidAppEligibility.swift
//  Tech Flow Runner
//
//  Grandfathering for original paying customers. Tech Flow Runner was first sold
//  as a one-time paid app ($0.99). It has since moved to a free download with an
//  optional $2.99 non-consumable "Unlimited Lives" purchase. Anyone who PAID for
//  the app must receive Unlimited Lives permanently, for free.
//
//  ───────────────────────────────────────────────────────────────────────────
//  HOW WE TELL A PAYER FROM A FREE DOWNLOADER
//  ───────────────────────────────────────────────────────────────────────────
//  StoreKit 2 exposes an *app-level* transaction — `AppTransaction.shared` —
//  that records how the customer first acquired the app. On iOS
//  `AppTransaction.originalAppVersion` is the `CFBundleVersion` (the build
//  number) of that first-acquired build, and `originalPurchaseDate` is when it
//  was acquired.
//
//  We CANNOT simply check "does an app transaction / receipt exist?" — free
//  downloads have one too. Nor is a "price paid" field available. Instead we
//  decide a user PAID if EITHER of these holds:
//
//    1. Build cutoff — they first acquired a build at or before the last build
//       that ever shipped while the app was paid (`lastPaidBuildNumber`). This
//       cleanly covers everyone from the paid ($0.99) era.
//
//    2. Transition window — they first acquired the app BEFORE the App Store
//       price was actually dropped to free (`freeTransitionDate`). This covers
//       the gap where the free-model build is already live but still priced
//       $0.99: those buyers download the SAME build as later free users, so the
//       build number can't distinguish them, but their purchase date can.
//
//  ───────────────────────────────────────────────────────────────────────────
//  ⚠️  VALUES YOU MUST GET RIGHT BEFORE SHIPPING
//  ───────────────────────────────────────────────────────────────────────────
//  • `lastPaidBuildNumber` MUST equal the final `CFBundleVersion` that was live
//    on the App Store while the app cost $0.99. Marketing 1.0 shipped at build
//    `7`, so the cutoff is "7". (Marketing version — 1.0, 1.1 — is NOT what iOS
//    compares; it compares the build number.)
//
//  • The FREE-model release's `CURRENT_PROJECT_VERSION` MUST be STRICTLY GREATER
//    than `lastPaidBuildNumber`. It is `8` (see project.pbxproj /
//    generate_project.py). The App Store also enforces monotonically increasing
//    builds, so build 8 is the next valid build after the paid build 7.
//
//  • `freeTransitionDate` should be set to (at or before) the moment you change
//    the App Store price to free, to grandfather transition-window buyers. Until
//    you know that date it is `nil`, which disables the date rule and relies on
//    the build cutoff alone — the safe default (it can never grandfather a free
//    user). See the constant below.
//

import Foundation
import StoreKit

/// Where an active "Unlimited Lives" entitlement came from. This is the single
/// model the whole app uses to reason about Unlimited Lives — see
/// `StoreManager.entitlementSource` / `hasUnlimitedLives`.
///
///   - `.none`          No Unlimited Lives entitlement.
///   - `.purchasedIAP`  The $2.99 non-consumable was purchased (or restored).
///   - `.legacyPaidApp` The user paid for the app itself (the paid $0.99 era, or
///                      during the transition window before the price dropped)
///                      and was grandfathered in — no IAP required.
enum UnlimitedLivesSource: String, Codable {
    case none
    case purchasedIAP
    case legacyPaidApp
}

/// The paid-app cutoffs and the StoreKit app-transaction check that decides
/// whether the current user paid for the app.
enum LegacyPaidAppEligibility {

    /// The final `CFBundleVersion` (build number) distributed while Tech Flow
    /// Runner was a paid ($0.99) download. Any user whose originally-acquired
    /// build is at or before this value paid for the app and is grandfathered
    /// into Unlimited Lives for free.
    ///
    /// ⚠️ Marketing 1.0 shipped at build 7 — verify against App Store Connect
    /// before release. The free-model build number MUST be strictly greater.
    static let lastPaidBuildNumber = "7"

    /// The moment the App Store price was (or will be) dropped from $0.99 to
    /// free. Anyone who first acquired the app strictly BEFORE this paid for it —
    /// including buyers of the free-model build (build 8) during the window
    /// where its price hadn't been removed yet — and is grandfathered.
    ///
    /// Set this to at/before the instant you actually change the price to free:
    ///   • Set it earlier than the real price drop → a few late paid buyers are
    ///     missed (they can still Restore Purchases).
    ///   • Set it later than the real price drop → a few free downloaders would
    ///     be wrongly grandfathered.
    /// `nil` disables the date rule entirely, relying on `lastPaidBuildNumber`
    /// alone — the safe default that can never grandfather a free user.
    ///
    /// Example (grandfather everyone who bought before 1 Sep 2026, 00:00 UTC):
    ///   static let freeTransitionDate: Date? = isoDate("2026-09-01T00:00:00Z")
    static let freeTransitionDate: Date? = nil

    /// The result of the app-transaction eligibility check. We deliberately
    /// distinguish "verified not eligible" from "couldn't verify", because a
    /// transient verification failure must never revoke an entitlement that was
    /// already granted and cached (see `StoreManager.refreshEntitlements`).
    enum Result {
        /// Verified app transaction that qualifies as a paid acquisition.
        case qualified
        /// Verified app transaction that does not qualify (a genuine free-era
        /// download).
        case notQualified
        /// The app transaction was unavailable or failed verification, so
        /// eligibility can't be determined right now (e.g. offline first run).
        case indeterminate
    }

    /// Asynchronously retrieves and verifies the StoreKit app transaction and
    /// decides whether the current user paid for the app. Only the verified
    /// transaction is trusted; unverified or failed lookups return
    /// `.indeterminate` so callers can preserve any previously-granted state.
    static func check() async -> Result {
        do {
            let verification = try await AppTransaction.shared
            switch verification {
            case .verified(let appTransaction):
                // On iOS `originalAppVersion` is the CFBundleVersion (build
                // number) of the build the customer first acquired.
                let originalBuild = appTransaction.originalAppVersion
                let purchaseDate = appTransaction.originalPurchaseDate
                let qualifies = isLegacyPaidPurchase(originalBuild: originalBuild,
                                                     purchaseDate: purchaseDate)
                log("app transaction verified; originalAppVersion=\(originalBuild), originalPurchaseDate=\(purchaseDate), legacyPaid=\(qualifies)")
                return qualifies ? .qualified : .notQualified
            case .unverified(_, let error):
                // Never grant an entitlement from unverified data.
                log("app transaction unverified: \(error.localizedDescription)")
                return .indeterminate
            }
        } catch {
            // No network on first run, StoreKit unavailable, etc. Can't decide.
            log("app transaction lookup failed: \(error.localizedDescription)")
            return .indeterminate
        }
    }

    /// True when the user paid for the app: either they first acquired a paid-era
    /// build (build cutoff), or they acquired it before the price dropped to free
    /// (transition window). Either path means they paid.
    static func isLegacyPaidPurchase(originalBuild: String, purchaseDate: Date) -> Bool {
        if isLegacyPaidVersion(originalBuild) { return true }
        if let transition = freeTransitionDate, purchaseDate < transition { return true }
        return false
    }

    /// True when `originalAppVersion` is at or before the last paid build — i.e.
    /// the user originally acquired a build that was sold for money.
    ///
    /// Build numbers can have multiple numeric components ("1", "1.2",
    /// "1.2.3"), so this uses a component-wise numeric comparison rather than a
    /// naive string compare (which would order "10" before "2").
    static func isLegacyPaidVersion(_ originalAppVersion: String) -> Bool {
        compareBuildNumbers(originalAppVersion, lastPaidBuildNumber) != .orderedDescending
    }

    /// Compares two dotted build numbers component-by-component as integers.
    /// Missing trailing components are treated as 0 (so "1" == "1.0" == "1.0.0").
    static func compareBuildNumbers(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = numericComponents(lhs)
        let r = numericComponents(rhs)
        let count = max(l.count, r.count)
        for index in 0..<count {
            let a = index < l.count ? l[index] : 0
            let b = index < r.count ? r[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Splits a build number on "." and parses each component as an integer,
    /// tolerating stray non-digit characters (a malformed component becomes 0).
    private static func numericComponents(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { component in
                let digits = String(component.filter(\.isNumber))
                return Int(digits) ?? 0
            }
    }

    /// Parses an ISO 8601 timestamp (e.g. "2026-09-01T00:00:00Z"). Convenience
    /// for configuring `freeTransitionDate` without hand-building DateComponents.
    static func isoDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[LegacyPaid] \(message)")
        #endif
    }
}

#if DEBUG
/// DEBUG-ONLY entitlement simulation. StoreKit's sandbox `originalAppVersion`
/// often doesn't match real production history, so developers need a way to
/// exercise every entitlement path deterministically. Selected from the
/// hidden "Developer" section in Settings and persisted so it survives relaunch.
///
/// This entire type is compiled out of Release builds — it can never affect a
/// shipped app.
enum EntitlementTestScenario: String, CaseIterable, Identifiable {
    /// No override — use the real StoreKit checks.
    case disabled
    /// Original paid-app owner who has NOT yet seen the Early Supporter message.
    case legacyNotAcknowledged
    /// Original paid-app owner who has already acknowledged the message.
    case legacyAcknowledged
    /// Owner of the $2.99 Unlimited Lives non-consumable.
    case iapOwner
    /// Free user with no entitlement.
    case freeUser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .disabled: return "Off (use StoreKit)"
        case .legacyNotAcknowledged: return "Legacy — needs message"
        case .legacyAcknowledged: return "Legacy — message seen"
        case .iapOwner: return "IAP owner"
        case .freeUser: return "Free user"
        }
    }
}
#endif
