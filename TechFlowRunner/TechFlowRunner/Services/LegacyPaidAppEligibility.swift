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

    /// The instant the App Store price is (or will be) dropped from $0.99 to
    /// free. Anyone whose app was first acquired STRICTLY BEFORE this paid for
    /// it — the entire paid era plus anyone who buys the free-model build at
    /// $0.99 before the price actually changes — and is grandfathered. Anyone
    /// who acquires it at/after this got it free and is not.
    ///
    /// ⚠️ REPLACE with your real price-drop date. Recommended: schedule the App
    /// Store price → Free for a specific date/time in App Store Connect (this
    /// needs no app review), and set this constant to that exact date.
    ///   • Too early → real payers who buy during any extended $0.99 period are
    ///     missed (they can still Restore Purchases once this is corrected).
    ///   • Too late  → free downloaders before this date are wrongly grandfathered.
    /// `nil` disables grandfathering entirely (no one is granted) — so this MUST
    /// be set before the free release ships.
    ///
    /// Placeholder below is a stand-in date — change it to your scheduled
    /// price-drop instant.
    static let freeTransitionDate: Date? = isoDate("2026-09-01T00:00:00Z")

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
