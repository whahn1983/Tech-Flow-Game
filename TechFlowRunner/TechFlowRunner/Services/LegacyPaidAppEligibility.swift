//
//  LegacyPaidAppEligibility.swift
//  Tech Flow Runner
//
//  Grandfathering for original paying customers. Tech Flow Runner was first sold
//  as a one-time paid app ($0.99). It has since moved to a free download with an
//  optional $2.99 non-consumable "Unlimited Lives" purchase. Anyone who bought
//  the original paid app must receive Unlimited Lives permanently, for free.
//
//  ───────────────────────────────────────────────────────────────────────────
//  HOW WE TELL A LEGACY PAYER FROM A NEW FREE USER
//  ───────────────────────────────────────────────────────────────────────────
//  StoreKit 2 exposes an *app-level* transaction — `AppTransaction.shared` —
//  that records the version of the app the customer ORIGINALLY acquired. On iOS
//  `AppTransaction.originalAppVersion` is the `CFBundleVersion` (the build
//  number) of that first-acquired build.
//
//  We CANNOT simply check "does an app transaction / receipt exist?" — free
//  downloads have an app transaction too. Instead we compare the original build
//  number against a fixed cutoff: the final build that was ever distributed
//  while the app cost money. A user whose original build is at or before that
//  cutoff paid for the app; anyone whose original build is after it downloaded
//  the free version.
//
//  ───────────────────────────────────────────────────────────────────────────
//  ⚠️  TWO VALUES YOU MUST GET RIGHT BEFORE SHIPPING
//  ───────────────────────────────────────────────────────────────────────────
//  1. `lastPaidBuildNumber` below MUST equal the actual final `CFBundleVersion`
//     that was live on the App Store while Tech Flow Runner cost $0.99. Confirm
//     it in App Store Connect (the paid version's Build number). The repository
//     history shows the paid era shipped at build `1` (marketing 1.0), so the
//     cutoff is set to `"1"`.
//
//  2. The FREE-TO-PLAY build's `CURRENT_PROJECT_VERSION` MUST be STRICTLY
//     GREATER than `lastPaidBuildNumber`. If the free build shipped with the
//     same build number as the cutoff, a brand-new free downloader's
//     `originalAppVersion` would also satisfy "<= cutoff" and be wrongly
//     grandfathered. The project's `CURRENT_PROJECT_VERSION` is therefore
//     bumped to `2` for the free release (see project.pbxproj /
//     generate_project.py). Keep every future build number above the cutoff.
//
//  If the free-to-play version had ALREADY been released to the App Store under
//  a build number <= this cutoff, those free users would incorrectly qualify;
//  in that case raise the cutoff below the free build and re-verify.
//

import Foundation
import StoreKit

/// Where an active "Unlimited Lives" entitlement came from. This is the single
/// model the whole app uses to reason about Unlimited Lives — see
/// `StoreManager.entitlementSource` / `hasUnlimitedLives`.
///
///   - `.none`          No Unlimited Lives entitlement.
///   - `.purchasedIAP`  The $2.99 non-consumable was purchased (or restored).
///   - `.legacyPaidApp` The user owned the original paid ($0.99) app and was
///                      grandfathered in — no purchase required.
enum UnlimitedLivesSource: String, Codable {
    case none
    case purchasedIAP
    case legacyPaidApp
}

/// The paid-app cutoff and the StoreKit app-transaction check that decides
/// whether the current user is an original paying customer.
enum LegacyPaidAppEligibility {

    /// The final `CFBundleVersion` (build number) distributed while Tech Flow
    /// Runner was a paid ($0.99) download. Any user whose originally-acquired
    /// build is at or before this value paid for the app and is grandfathered
    /// into Unlimited Lives for free.
    ///
    /// ⚠️ Verify against App Store Connect before release (see file header). The
    /// free-to-play build number MUST be strictly greater than this.
    static let lastPaidBuildNumber = "1"

    /// The result of the app-transaction eligibility check. We deliberately
    /// distinguish "verified not eligible" from "couldn't verify", because a
    /// transient verification failure must never revoke an entitlement that was
    /// already granted and cached (see `StoreManager.refreshEntitlements`).
    enum Result {
        /// Verified app transaction whose original build is at/before the cutoff.
        case qualified
        /// Verified app transaction whose original build is after the cutoff
        /// (a genuine free-era download).
        case notQualified
        /// The app transaction was unavailable or failed verification, so
        /// eligibility can't be determined right now (e.g. offline first run).
        case indeterminate
    }

    /// Asynchronously retrieves and verifies the StoreKit app transaction and
    /// decides whether the current user is an original paid-app owner. Only the
    /// verified transaction is trusted; unverified or failed lookups return
    /// `.indeterminate` so callers can preserve any previously-granted state.
    static func check() async -> Result {
        do {
            let verification = try await AppTransaction.shared
            switch verification {
            case .verified(let appTransaction):
                // On iOS this is the CFBundleVersion (build number) of the build
                // the customer first acquired.
                let originalBuild = appTransaction.originalAppVersion
                let qualifies = isLegacyPaidVersion(originalBuild)
                log("app transaction verified; originalAppVersion=\(originalBuild), legacyPaid=\(qualifies)")
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
