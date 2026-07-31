//
//  StoreManager.swift
//  Tech Flow Runner
//
//  Owns the single in-app purchase — "Unlimited Lives Forever" — using
//  StoreKit 2. The purchase is a non-consumable: once owned it never expires and
//  can be restored on any device signed in to the same Apple Account.
//
//  ───────────────────────────────────────────────────────────────────────────
//  SOURCE OF TRUTH
//  ───────────────────────────────────────────────────────────────────────────
//  Ownership is derived from StoreKit's `Transaction.currentEntitlements`, which
//  StoreKit caches locally so it resolves correctly even offline once the
//  purchase has been made. The result is mirrored into a cached
//  `PersistenceManager.unlimitedLives` flag (so the UI reflects ownership
//  instantly at launch, before the async check completes) and pushed into
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
        case failed(String)
    }

    /// The loaded Unlimited Lives product, or nil until StoreKit returns it.
    @Published private(set) var product: Product?
    /// True when the Unlimited Lives non-consumable is owned.
    @Published private(set) var isUnlimitedUnlocked: Bool
    /// Drives spinners / error text on the paywall.
    @Published private(set) var phase: Phase = .idle

    private let persistence = PersistenceManager.shared
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Seed from the cached flag so the UI is correct before the async
        // entitlement check in start() completes.
        isUnlimitedUnlocked = persistence.unlimitedLives
    }

    /// Localized price string for the UI (e.g. "$2.99"), falling back to the
    /// intended tier price until StoreKit returns the localized product.
    var displayPrice: String { product?.displayPrice ?? "$2.99" }

    /// True while a purchase or restore is in flight (buttons disable on this).
    var isBusy: Bool { phase == .purchasing || phase == .restoring }

    // MARK: - Lifecycle

    /// Starts the transaction listener and loads the product + current
    /// entitlements. Call once at launch.
    func start() {
        if updatesTask == nil {
            // Listen for transactions that arrive outside an explicit purchase:
            // Ask-to-Buy approvals, purchases/restores made on another device,
            // and refunds/revocations.
            updatesTask = Task.detached { [weak self] in
                for await update in Transaction.updates {
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

    /// Re-evaluates App Store entitlements to determine current ownership. This
    /// is the authoritative check and corrects the cached flag either way.
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == StoreProductID.unlimitedLives,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
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
    /// Review Guideline 3.1.1).
    func restore() async {
        phase = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            phase = .idle
        } catch {
            log("restore failed: \(error.localizedDescription)")
            phase = .failed("Restore couldn't be completed. Please try again.")
        }
    }

    // MARK: - Transaction handling

    private func handle(_ verification: VerificationResult<Transaction>) async {
        switch verification {
        case .verified(let transaction):
            if transaction.productID == StoreProductID.unlimitedLives {
                setUnlocked(transaction.revocationDate == nil)
            }
            // Always finish so the transaction leaves the queue.
            await transaction.finish()
        case .unverified:
            // Failed StoreKit's signature check — don't grant anything.
            log("received an unverified transaction; ignoring")
        }
    }

    private func setUnlocked(_ value: Bool) {
        isUnlimitedUnlocked = value
        persistence.unlimitedLives = value
        LivesManager.shared.setUnlimited(value)
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[Store] \(message)")
        #endif
    }
}
