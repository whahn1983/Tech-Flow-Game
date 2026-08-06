//
//  LegacyPaidAppEligibility.swift
//  Tech Flow Runner
//
//  Grandfathering for original paying customers. Tech Flow Runner was first sold
//  as a one-time paid app ($0.99). It is moving to a free download with an
//  optional $2.99 non-consumable "Unlimited Lives" purchase. Anyone who PAID for
//  the app must receive Unlimited Lives permanently, for free.
//
//  ───────────────────────────────────────────────────────────────────────────
//  WHY THIS IS DATE-BASED, NOT VERSION-BASED
//  ───────────────────────────────────────────────────────────────────────────
//  StoreKit 2's app-level transaction (`AppTransaction.shared`) records how the
//  customer first acquired the app: `originalAppVersion` (on iOS, the
//  `CFBundleVersion` build number) and `originalPurchaseDate`. There is NO
//  "price paid" field — free downloads and paid downloads are indistinguishable
//  by any receipt field except WHEN they happened.
//
//  We can't use the build number here because THIS app resets its build number
//  per marketing version: paid 1.0 shipped as build 7, while the free 1.1 build
//  is 2 (and climbs to 3, 4, … as Apple requests changes). So the free build's
//  number (2) is LOWER than the paid build's (7) — any "original build ≤ cutoff"
//  test would wrongly grandfather every new free user, and it breaks further
//  every time a re-review bumps the build.
//
//  The reliable signal is the purchase DATE. The app was paid from launch until
//  the moment its App Store price is dropped to free. So:
//
//      paid  ⇔  originalPurchaseDate < freeTransitionDate
//
//  This grandfathers EVERY paying customer on ANY build — the whole $0.99 1.0
//  era AND anyone who buys the 1.1 build for $0.99 during the window before the
//  price actually drops — and excludes everyone who downloads free afterward.
//  Because it keys on a date, it is completely immune to the build-number churn
//  from Apple's re-review cycles.
//
//  ───────────────────────────────────────────────────────────────────────────
//  ⚠️  SET freeTransitionDate — THE ONE VALUE THAT MATTERS
//  ───────────────────────────────────────────────────────────────────────────
//  See the constant below. Set it to the instant the price becomes free. The
//  clean way to make reality match it exactly, despite Apple's unpredictable
//  review timing, is an App Store Connect SCHEDULED price change (price changes
//  don't require review): schedule the price → Free effective on date D, and set
//  `freeTransitionDate` to that same D. Whatever build number finally ships
//  (2, 3, 4 …), the date is unchanged.
//

import Foundation
import StoreKit

/// Where an active "Unlimited Lives" entitlement came from. This is the single
/// model the whole app uses to reason about Unlimited Lives — see
/// `StoreManager.entitlementSource` / `hasUnlimitedLives`.
///
///   - `.none`          No Unlimited Lives entitlement.
///   - `.purchasedIAP`  The $2.99 non-consumable was purchased (or restored).
///   - `.legacyPaidApp` The user paid for the app itself (before it became free)
///                      and was grandfathered in — no IAP required.
enum UnlimitedLivesSource: String, Codable {
    case none
    case purchasedIAP
    case legacyPaidApp
}

/// Decides whether the current user paid for the app, from the verified
/// StoreKit app transaction.
enum LegacyPaidAppEligibility {

    /// The instant the App Store price is dropped from $0.99 to free. Anyone
    /// whose app was first acquired STRICTLY BEFORE this paid for it — the entire
    /// paid era plus anyone who buys the free-model build at $0.99 before the
    /// price actually changes — and is grandfathered. Anyone who acquires it
    /// at/after this got it free and is not.
    ///
    /// Configured to **2026-08-15 00:00 America/Chicago (CDT, UTC−5)** — local
    /// midnight at the END of the changeover day (Aug 14), when the App Store
    /// price → Free change and the version's auto-release (NET) are scheduled.
    ///
    /// Why midnight, not the release time: App Store price changes are
    /// DATE-granular — you can't specify a time, and Apple doesn't confirm the
    /// exact instant the new price takes effect. So we deliberately set the
    /// cutoff to the end of the changeover day and err GENEROUS: everyone who
    /// buys at any point during Aug 14 stays grandfathered even if Apple flips
    /// the price earlier in the day. It is far better to let a few people get
    /// the app free on the changeover day than to make a paying customer buy
    /// Unlimited Lives again. (This is the later of the two possible midnights;
    /// 00:00 CDT = 05:00 UTC.)
    ///
    /// Built from the `America/Chicago` IANA zone (not a fixed offset) so the
    /// daylight-saving offset is correct by construction. To change it, edit the
    /// components below (or set `nil` to disable grandfathering entirely — no one
    /// is granted, so it must stay set for the free release).
    static let freeTransitionDate: Date? = {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/Chicago")  // CDT in August
        return Calendar(identifier: .gregorian).date(from: components)
    }()

    /// Reference only: the `CFBundleVersion` the paid marketing-1.0 release
    /// shipped as. NOT used to decide eligibility (build numbers reset per
    /// marketing version here, so they can't separate paid from free — see the
    /// file header). Kept for DEBUG diagnostics and documentation.
    static let lastPaidBuildNumber = "7"

    /// The result of the app-transaction eligibility check. We deliberately
    /// distinguish "verified not eligible" from "couldn't verify", because a
    /// transient verification failure must never revoke an entitlement that was
    /// already granted and cached (see `StoreManager.refreshEntitlements`).
    enum Result {
        /// Verified app transaction that qualifies as a paid acquisition.
        case qualified
        /// Verified app transaction that does not qualify (a free-era download).
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
                let purchaseDate = appTransaction.originalPurchaseDate
                let qualifies = isLegacyPaidPurchase(purchaseDate: purchaseDate)
                log("app transaction verified; originalAppVersion=\(appTransaction.originalAppVersion) (paid-era ref build \(lastPaidBuildNumber)), originalPurchaseDate=\(purchaseDate), freeTransitionDate=\(String(describing: freeTransitionDate)), legacyPaid=\(qualifies)")
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

    /// True when the user paid for the app: they acquired it before the price
    /// dropped to free. Returns false when `freeTransitionDate` is unset.
    static func isLegacyPaidPurchase(purchaseDate: Date) -> Bool {
        guard let transition = freeTransitionDate else { return false }
        return purchaseDate < transition
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[LegacyPaid] \(message)")
        #endif
    }
}

#if DEBUG
/// DEBUG-ONLY entitlement simulation. StoreKit's sandbox `originalPurchaseDate`
/// won't match real production history, so developers need a way to exercise
/// every entitlement path deterministically. Selected from the hidden
/// "Developer" section in Settings and persisted so it survives relaunch.
///
/// This entire type is compiled out of Release builds — it can never affect a
/// shipped app.
enum EntitlementTestScenario: String, CaseIterable, Identifiable {
    /// No override — use the real StoreKit checks.
    case disabled
    /// Paid customer (pre-free) who has NOT yet seen the Early Supporter message.
    case legacyNotAcknowledged
    /// Paid customer (pre-free) who has already acknowledged the message.
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
