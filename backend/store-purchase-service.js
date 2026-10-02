import { InputError, sha256 } from "./security-core.js";
import {
  buildEntitlementRecord,
  buildGoogleLineageEntitlementRecord,
  buildLifecycleEntitlementRecord,
  buildStoreEntitlementId,
  deriveStoreAccountToken,
  identifyApplePurchase,
  identifyGooglePurchase,
  normalizeApplePurchase,
  normalizeGooglePurchase,
  storePaymentReference,
  validateStoreConfirmation,
  validateStoreRestoration,
} from "./store-purchase-core.js";

function requiredCallback(value, code = "STORE_SERVICE_UNAVAILABLE") {
  if (typeof value !== "function") throw new InputError(code);
  return value;
}

async function deliverVerifiedPurchase({
  checkout,
  purchase,
  confirmation,
  persistEntitlement,
  finalizeProfessional,
  finalizeExistingProfessional,
  acknowledgeGoogle,
  restored = false,
  existingEntitlement = null,
  nowMs,
}) {
  const entitlementDraft = existingEntitlement
    ? purchase.provider === "google"
      ? buildGoogleLineageEntitlementRecord(checkout, purchase, existingEntitlement, nowMs)
      : buildLifecycleEntitlementRecord(checkout, purchase, existingEntitlement, nowMs)
    : buildEntitlementRecord(checkout, purchase, nowMs);
  const persisted = await requiredCallback(persistEntitlement)(entitlementDraft);
  if (!persisted?.item || persisted.item._id !== entitlementDraft._id) {
    throw new InputError("INVALID_ENTITLEMENT");
  }

  const isGoogleReplacement = existingEntitlement
    && purchase.provider === "google"
    && checkout._id !== existingEntitlement.checkoutId;
  const finalizer = existingEntitlement
    && purchase.provider === "google"
    && typeof finalizeExistingProfessional === "function"
    ? finalizeExistingProfessional
    : isGoogleReplacement
      ? requiredCallback(finalizeExistingProfessional)
      : requiredCallback(finalizeProfessional);
  const finalized = await finalizer({
    checkout,
    entitlement: persisted.item,
    previousEntitlement: existingEntitlement,
    paymentReference: storePaymentReference(purchase),
  });
  if (!finalized?.professional || finalized.professional._id !== persisted.item.professionalId) {
    throw new InputError("INVALID_STORE_FINALIZATION");
  }

  if (confirmation.store === "google_play" && purchase.needsAcknowledgement) {
    await requiredCallback(acknowledgeGoogle)({
      purchaseToken: confirmation.verificationData,
      productId: purchase.productId,
    });
  }

  return Object.freeze({
    checkout: finalized.checkout,
    professional: finalized.professional,
    entitlement: persisted.item,
    idempotent: Boolean(persisted.idempotent && finalized.idempotent),
    completePurchase: true,
    restored,
  });
}

async function uniqueEntitlementByCurrentHash(
  findEntitlementsByCurrentTransactionHash,
  currentTransactionHash,
) {
  if (!currentTransactionHash) return null;
  const matches = await requiredCallback(findEntitlementsByCurrentTransactionHash)(
    { currentTransactionHash },
  );
  if (!Array.isArray(matches)) throw new InputError("INVALID_ENTITLEMENT");
  if (matches.length > 1) throw new InputError("STORE_PURCHASE_LINEAGE_AMBIGUOUS");
  return matches[0] ?? null;
}

async function resolveGoogleLineage(
  purchase,
  findEntitlementsByCurrentTransactionHash,
  findEntitlement,
) {
  if (typeof findEntitlementsByCurrentTransactionHash !== "function") {
    if (purchase.linkedTransactionHash) {
      throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
    }
    return null;
  }
  const current = await uniqueEntitlementByCurrentHash(
    findEntitlementsByCurrentTransactionHash,
    purchase.currentTransactionHash,
  );
  let linked = purchase.linkedTransactionHash
    ? await uniqueEntitlementByCurrentHash(
      findEntitlementsByCurrentTransactionHash,
      purchase.linkedTransactionHash,
    )
    : null;
  if (!linked && purchase.linkedTransactionHash && typeof findEntitlement === "function") {
    const legacyId = buildStoreEntitlementId({
      provider: "google",
      originalTransactionHash: purchase.linkedTransactionHash,
    });
    const legacy = await findEntitlement(legacyId);
    if (
      legacy
      && legacy.provider === "google"
      && (legacy.currentTransactionHash ?? legacy.originalTransactionHash)
        === purchase.linkedTransactionHash
    ) {
      linked = legacy;
    }
  }
  if (current && linked && current._id !== linked._id) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  if (current) return current;
  if (purchase.linkedTransactionHash) {
    if (!linked) throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
    return linked;
  }
  return null;
}

function assertEnvironmentAllowed(purchase, allowSandbox) {
  if (purchase?.environment === "sandbox" && allowSandbox !== true) {
    throw new InputError("STORE_ENVIRONMENT_MISMATCH");
  }
}

export async function confirmStorePurchaseWithDependencies({
  checkout,
  rawConfirmation,
  signingSecret,
  signingKeyring,
  nowMs = Date.now(),
  verifyApple,
  verifyGoogle,
  persistEntitlement,
  finalizeProfessional,
  finalizeExistingProfessional,
  findEntitlementsByCurrentTransactionHash,
  findEntitlement,
  acknowledgeGoogle,
  allowSandbox = false,
}) {
  const confirmation = validateStoreConfirmation(rawConfirmation, checkout);
  const accountToken = deriveStoreAccountToken(
    checkout,
    signingKeyring ?? signingSecret,
  );
  let purchase;

  if (confirmation.store === "app_store") {
    const decoded = await requiredCallback(verifyApple)(confirmation.verificationData);
    purchase = normalizeApplePurchase(decoded, {
      checkout,
      accountToken,
      verificationData: confirmation.verificationData,
      purchaseId: confirmation.purchaseId,
      nowMs,
    });
  } else {
    const response = await requiredCallback(verifyGoogle)(confirmation.verificationData);
    purchase = normalizeGooglePurchase(response, {
      checkout,
      accountToken,
      verificationData: confirmation.verificationData,
      purchaseId: confirmation.purchaseId,
      nowMs,
    });
  }

  assertEnvironmentAllowed(purchase, allowSandbox);
  const existingEntitlement = purchase.provider === "google"
    ? await resolveGoogleLineage(
      purchase,
      findEntitlementsByCurrentTransactionHash,
      findEntitlement,
    )
    : null;

  return deliverVerifiedPurchase({
    checkout,
    purchase,
    confirmation,
    persistEntitlement,
    finalizeProfessional,
    finalizeExistingProfessional,
    acknowledgeGoogle,
    existingEntitlement,
    nowMs,
  });
}

export async function restoreStorePurchaseWithDependencies({
  rawRestoration,
  signingSecret,
  signingKeyring,
  nowMs = Date.now(),
  verifyApple,
  verifyGoogle,
  findEntitlement,
  findEntitlementsByCurrentTransactionHash,
  findCheckout,
  findCheckoutsByAccountReference,
  persistEntitlement,
  finalizeProfessional,
  finalizeExistingProfessional,
  acknowledgeGoogle,
  allowSandbox = false,
}) {
  const restoration = validateStoreRestoration(rawRestoration);
  let identified;
  if (restoration.store === "app_store") {
    const decoded = await requiredCallback(verifyApple)(restoration.verificationData);
    identified = identifyApplePurchase(decoded, {
      productId: restoration.productId,
      verificationData: restoration.verificationData,
      purchaseId: restoration.purchaseId,
      nowMs,
    });
  } else {
    const response = await requiredCallback(verifyGoogle)(restoration.verificationData);
    identified = identifyGooglePurchase(response, {
      productId: restoration.productId,
      verificationData: restoration.verificationData,
      purchaseId: restoration.purchaseId,
      nowMs,
    });
  }

  assertEnvironmentAllowed(identified.purchase, allowSandbox);

  const entitlementId = buildStoreEntitlementId(identified.purchase);
  let existingEntitlement = restoration.store === "google_play"
    ? await resolveGoogleLineage(
      identified.purchase,
      findEntitlementsByCurrentTransactionHash,
      findEntitlement,
    )
    : await requiredCallback(findEntitlement)(entitlementId);
  if (!existingEntitlement && restoration.store === "google_play") {
    const possibleRoot = await requiredCallback(findEntitlement)(entitlementId);
    if (
      possibleRoot
      && possibleRoot.currentTransactionHash !== identified.purchase.currentTransactionHash
    ) {
      throw new InputError("STORE_PURCHASE_REPLACED");
    }
    existingEntitlement = possibleRoot;
  }
  let checkout;
  if (existingEntitlement) {
    if (
      existingEntitlement.provider !== identified.purchase.provider
      || typeof existingEntitlement.checkoutId !== "string"
    ) {
      throw new InputError("STORE_PURCHASE_NOT_REGISTERED");
    }
    if (
      restoration.store === "google_play"
      && identified.purchase.linkedTransactionHash
      && existingEntitlement.currentTransactionHash === identified.purchase.linkedTransactionHash
    ) {
      const matches = await requiredCallback(findCheckoutsByAccountReference)({
        accountReferenceHash: sha256(identified.accountToken),
        store: restoration.store,
        productId: restoration.productId,
      });
      if (!Array.isArray(matches)) throw new InputError("INVALID_STORE_CHECKOUT");
      if (matches.length > 1) throw new InputError("STORE_ACCOUNT_REFERENCE_AMBIGUOUS");
      [checkout] = matches;
    } else {
      checkout = await requiredCallback(findCheckout)(existingEntitlement.checkoutId);
    }
  } else {
    const matches = await requiredCallback(findCheckoutsByAccountReference)({
      accountReferenceHash: sha256(identified.accountToken),
      store: restoration.store,
      productId: restoration.productId,
    });
    if (!Array.isArray(matches)) throw new InputError("INVALID_STORE_CHECKOUT");
    if (matches.length > 1) throw new InputError("STORE_ACCOUNT_REFERENCE_AMBIGUOUS");
    [checkout] = matches;
  }
  if (!checkout) throw new InputError("STORE_PURCHASE_NOT_REGISTERED");
  const expectedAccountToken = deriveStoreAccountToken(
    checkout,
    signingKeyring ?? signingSecret,
  );
  if (
    checkout.store !== restoration.store
    || checkout.storeProductId !== restoration.productId
    || identified.accountToken !== expectedAccountToken
  ) {
    throw new InputError("STORE_ACCOUNT_MISMATCH");
  }

  return deliverVerifiedPurchase({
    checkout,
    purchase: identified.purchase,
    confirmation: restoration,
    persistEntitlement,
    finalizeProfessional,
    finalizeExistingProfessional,
    acknowledgeGoogle,
    restored: true,
    existingEntitlement,
    nowMs,
  });
}
