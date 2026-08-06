//
//  StoreManager.swift
//  Tech Flow Runner
//
//  Owns the "Unlimited Lives" entitlement. Unlimited Lives can be active for two
//  reasons, unified under a single `UnlimitedLivesSource`:
//
//    • `.purchasedIAP`   — the $2.99 non-consumable was bought (or restored).
//    • `.legacyPaidApp`  — the user owned the ORIGINAL paid ($0.99) app and was
//                          grandfathered in for free (see LegacyPaidAppEligibility).
//
//  The rest of the app never cares which source it is; it asks
//  `hasUnlimitedLives`. Where it matters (the store screen, Settings, the
//  one-time Early Supporter message), the source is surfaced explicitly.
//
//  ───────────────────────────────────────────────────────────────────────────
//  SOURCE OF TRUTH & PRIORITY
//  ───────────────────────────────────────────────────────────────────────────
//  Ownership is derived from StoreKit's verified transactions, resolved in this
//  priority order:
//    1. Verified Unlimited Lives IAP (`Transaction.currentEntitlements`).
//    2. Verified legacy paid-app ownership (`AppTransaction.shared`).
//    3. Locally cached, previously-verified entitlement (offline / transient
//       StoreKit failure) — never revoked just because a later check can't run.
//    4. No entitlement.
//  The resolved source is cached in `PersistenceManager.unlimitedLivesSource`
//  (so the UI is correct instantly at launch and offline) and mirrored into
//  `LivesManager` so the lives pool becomes unlimited.
//
//  ───────────────────────────────────────────────────────────────────────────
//  APP STORE CONNECT SETUP
//  ───────────────────────────────────────────────────────────────────────────
//  Create a single Non-Consumable in-app purchase (My Apps → your app → Features
//  → In-App Purchases) with this EXACT Product ID, or edit `StoreProductID`
//  below to match the ID you create. Suggested price: Tier 3 ($2.99).
//
//    com.whahn1983.techflowrunner.unlimitedlives   Unlimited Lives Forever
//
//  For local testing without App Store Connect, the Xcode scheme references
//  `Products.storekit`, a StoreKit configuration file that defines the same
//  product so the purchase and restore flows work in the simulator.
//

import StoreKit
import SwiftUI

/// Single source of truth for every StoreKit product identifier.
///
/// IMPORTANT: each value MUST exactly match the Product ID configured in App
/// Store Connect (and in `Products.storekit`). A mismatch makes the product
/// fail to load and the purchase unavailable at runtime.
enum StoreProductID {
    static let unlimitedLives = "com.whahn1983.techflowrunner.unlimitedlives"
}

/// Apple's standard Licensed Application End User License Agreement (the
/// "Terms of Use" for the in-app purchase). The App Store applies this EULA to
/// every app that does not supply a custom one, so the paywall links to it. If
/// you configure a custom EULA in App Store Connect, point this at that URL
/// instead so the two stay in lockstep.
enum TermsOfUse {
    static let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    /// Coarse state of the store, surfaced to the paywall UI.
    enum Phase: Equatable {
        case idle
        case purchasing
        case restoring
        /// An error to show in danger styling (purchase/restore couldn't run).
        case failed(String)
        /// A neutral/success message to show after a completed restore.
        case info(String)
    }

    /// The loaded Unlimited Lives product, or nil until StoreKit returns it.
    @Published private(set) var product: Product?
    /// Where the active Unlimited Lives entitlement comes from (`.none` when
    /// there is no entitlement). The unified model the whole app reasons about.
    @Published private(set) var entitlementSource: UnlimitedLivesSource
    /// Drives spinners / error text on the paywall.
    @Published private(set) var phase: Phase = .idle
    /// Set true exactly once, after a legacy paid-app entitlement is first
    /// granted, to present the one-time "Early Supporter Upgrade" message.
    /// RootView binds an alert to this.
    @Published var presentEarlySupporterMessage = false

    private let persistence = PersistenceManager.shared
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Seed from the cached source so the UI is correct before the async
        // reconciliation in start() completes — and so a previously-verified
        // entitlement (IAP or legacy) keeps working offline.
        entitlementSource = persistence.unlimitedLivesSource
    }

    // MARK: - Derived state

    /// The single flag the life system and UI use: Unlimited Lives is active
    /// when it comes from EITHER the IAP or legacy paid-app ownership.
    var hasUnlimitedLives: Bool { entitlementSource != .none }

    /// Back-compat alias for existing call sites that asked whether Unlimited
    /// Lives is unlocked, regardless of source.
    var isUnlimitedUnlocked: Bool { hasUnlimitedLives }

    /// Localized price string for the UI (e.g. "$2.99"), falling back to the
    /// intended tier price until StoreKit returns the localized product.
    var displayPrice: String { product?.displayPrice ?? "$2.99" }

    /// True while a purchase or restore is in flight (buttons disable on this).
    var isBusy: Bool { phase == .purchasing || phase == .restoring }

    // MARK: - Lifecycle

    /// Starts the transaction listener and reconciles ownership. Call once at
    /// launch. Never blocks launch — all work runs in detached/async tasks.
    func start() {
        if updatesTask == nil {
            // Listen for transactions that arrive outside an explicit purchase:
            // Ask-to-Buy approvals, purchases/restores made on another device,
            // and refunds/revocations.
            updatesTask = Task.detached { [weak self] in
                // Fully qualified as `StoreKit.Transaction` because SwiftUI also
                // declares a `Transaction` type; importing both makes the bare
                // name ambiguous.
                for await update in StoreKit.Transaction.updates {
                    await self?.handle(update)
                }
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Products & entitlements

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [StoreProductID.unlimitedLives])
            product = products.first { $0.id == StoreProductID.unlimitedLives }
            if product == nil { log("product not found: \(StoreProductID.unlimitedLives)") }
        } catch {
            log("product load failed: \(error.localizedDescription)")
        }
    }

    /// Re-evaluates entitlements and resolves the Unlimited Lives source using
    /// the documented priority: verified IAP → verified legacy paid app →
    /// cached (kept on transient failure) → none. This is the authoritative
    /// check and corrects the cached source.
    func refreshEntitlements() async {
        #if DEBUG
        // Developer override short-circuits real StoreKit so every entitlement
        // path can be exercised deterministically. Compiled out of Release.
        let scenario = persistence.entitlementTestScenario
        if scenario != .disabled {
            applyDebugScenario(scenario)
            return
        }
        #endif

        // 1. Verified Unlimited Lives IAP — highest priority. `currentEntitlements`
        //    is served from the on-device receipt, so it resolves offline once
        //    the non-consumable has been purchased.
        var iapOwned = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == StoreProductID.unlimitedLives,
               transaction.revocationDate == nil {
                iapOwned = true
            }
        }
        if iapOwned {
            setSource(.purchasedIAP)
            return
        }

        // 2. Verified legacy paid-app ownership.
        switch await LegacyPaidAppEligibility.check() {
        case .qualified:
            grantLegacyPaidEntitlement()
        case .notQualified:
            // Verified: neither a current IAP owner nor an original paid-app
            // owner. Safe to clear any stale cached entitlement.
            setSource(.none)
        case .indeterminate:
            // 3. Couldn't verify legacy ownership (offline first run, StoreKit
            //    failure). Do NOT downgrade — preserve whatever was previously
            //    verified and cached (seeded into `entitlementSource` at init).
            log("legacy check indeterminate; preserving cached source: \(entitlementSource.rawValue)")
        }
    }

    // MARK: - Buy / restore

    /// Initiates the Unlimited Lives purchase flow.
    func purchase() async {
        guard let product else {
            // Products may not have loaded yet (slow network at launch).
            await loadProducts()
            guard product != nil else {
                phase = .failed("Store is unavailable right now. Please try again.")
                return
            }
            return await purchase()
        }

        phase = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
                phase = .idle
            case .userCancelled:
                phase = .idle
            case .pending:
                // Deferred (e.g. Ask to Buy). The entitlement lands later via
                // the Transaction.updates listener once it is approved.
                phase = .idle
            @unknown default:
                phase = .idle
            }
        } catch {
            log("purchase failed: \(error.localizedDescription)")
            phase = .failed("Purchase couldn't be completed. Please try again.")
        }
    }

    /// Restores previous purchases. Non-consumables must offer this (App Store
    /// Review Guideline 3.1.1). Syncs with the App Store, then rechecks BOTH the
    /// Unlimited Lives IAP and legacy paid-app eligibility, and reports a clear
    /// outcome for the source that resolved.
    func restore() async {
        phase = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            switch entitlementSource {
            case .purchasedIAP:
                phase = .info("Unlimited Lives restored.")
            case .legacyPaidApp:
                phase = .info("Your Early Supporter Unlimited Lives access has been restored.")
            case .none:
                phase = .info("No previous Unlimited Lives purchase or eligible paid-app ownership was found for this Apple Account.")
            }
        } catch {
            log("restore failed: \(error.localizedDescription)")
            phase = .failed("Restore couldn't be completed. Please try again.")
        }
    }

    // MARK: - Early Supporter message

    /// Records that the user acknowledged the one-time Early Supporter message
    /// and persists it immediately so it never appears again.
    func acknowledgeEarlySupporterMessage() {
        presentEarlySupporterMessage = false
        persistence.legacySupporterMessageShown = true
    }

    // MARK: - Transaction handling

    private func handle(_ verification: VerificationResult<StoreKit.Transaction>) async {
        switch verification {
        case .verified(let transaction):
            if transaction.productID == StoreProductID.unlimitedLives,
               transaction.revocationDate == nil {
                // A verified, live IAP is the top-priority source. If it was
                // revoked/refunded, fall through to a full re-resolution so a
                // legacy owner keeps Unlimited Lives via the legacy source.
                setSource(.purchasedIAP)
            } else if transaction.productID == StoreProductID.unlimitedLives {
                await refreshEntitlements()
            }
            // Always finish so the transaction leaves the queue.
            await transaction.finish()
        case .unverified:
            // Failed StoreKit's signature check — don't grant anything.
            log("received an unverified transaction; ignoring")
        }
    }

    /// Grants the legacy paid-app entitlement and queues the one-time Early
    /// Supporter message if it hasn't been acknowledged yet. Never downgrades a
    /// verified IAP entitlement to legacy (the IAP is higher priority).
    private func grantLegacyPaidEntitlement() {
        guard entitlementSource != .purchasedIAP else { return }
        setSource(.legacyPaidApp)
        // Present the welcome message once, only after the entitlement has been
        // granted — and only if it has never been acknowledged. The message
        // flag is tracked separately from the entitlement itself.
        if !persistence.legacySupporterMessageShown {
            presentEarlySupporterMessage = true
        }
    }

    /// Applies a resolved source everywhere: published state, local cache, and
    /// the lives pool. This is the only place the source changes.
    private func setSource(_ source: UnlimitedLivesSource) {
        if entitlementSource != source { entitlementSource = source }
        persistence.unlimitedLivesSource = source
        LivesManager.shared.setUnlimited(source != .none)
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[Store] \(message)")
        #endif
    }

    #if DEBUG
    /// Applies a developer-selected entitlement scenario (DEBUG builds only).
    private func applyDebugScenario(_ scenario: EntitlementTestScenario) {
        log("applying DEBUG entitlement scenario: \(scenario.rawValue)")
        switch scenario {
        case .disabled:
            break
        case .iapOwner:
            setSource(.purchasedIAP)
        case .freeUser:
            setSource(.none)
        case .legacyNotAcknowledged:
            persistence.legacySupporterMessageShown = false
            grantLegacyPaidEntitlement()
        case .legacyAcknowledged:
            persistence.legacySupporterMessageShown = true
            grantLegacyPaidEntitlement()
        }
    }
    #endif
}
