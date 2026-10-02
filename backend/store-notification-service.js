import { InputError, sha256 } from "./security-core.js";
import {
  buildEntitlementRecord,
  buildGoogleLineageEntitlementRecord,
  buildLifecycleEntitlementRecord,
  buildStoreEntitlementId,
  deriveStoreAccountToken,
} from "./store-purchase-core.js";
import { buildStoreEventRecord } from "./store-notification-core.js";

function callback(value, code = "STORE_NOTIFICATION_SERVICE_UNAVAILABLE") {
  if (typeof value !== "function") throw new InputError(code);
  return value;
}

async function uniqueEntitlementByCurrentHash(
  findEntitlementsByCurrentTransactionHash,
  currentTransactionHash,
) {
  if (!currentTransactionHash) return null;
  if (typeof findEntitlementsByCurrentTransactionHash !== "function") return null;
  const matches = await callback(findEntitlementsByCurrentTransactionHash)(
    { currentTransactionHash },
  );
  if (!Array.isArray(matches)) throw new InputError("INVALID_ENTITLEMENT");
  if (matches.length > 1) throw new InputError("STORE_PURCHASE_LINEAGE_AMBIGUOUS");
  return matches[0] ?? null;
}

async function uniqueCheckoutByAccountReference({
  event,
  findCheckoutsByAccountReference,
  productId,
}) {
  if (typeof findCheckoutsByAccountReference !== "function") return null;
  const store = event.purchase.provider === "apple" ? "app_store" : "google_play";
  let matches = await findCheckoutsByAccountReference({
    accountReferenceHash: sha256(event.accountToken),
    store,
    ...(productId ? { productId } : {}),
  });
  if (!Array.isArray(matches)) throw new InputError("INVALID_STORE_CHECKOUT");
  if (matches.length === 0 && productId) {
    matches = await findCheckoutsByAccountReference({
      accountReferenceHash: sha256(event.accountToken),
      store,
    });
    if (!Array.isArray(matches)) throw new InputError("INVALID_STORE_CHECKOUT");
  }
  if (matches.length > 1) throw new InputError("STORE_ACCOUNT_REFERENCE_AMBIGUOUS");
  return matches[0] ?? null;
}

async function resolveGoogleContext({
  event,
  findEntitlement,
  findCheckout,
  findEntitlementsByCurrentTransactionHash,
  findCheckoutsByAccountReference,
}) {
  const purchase = event.purchase;
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
  if (!linked && purchase.linkedTransactionHash) {
    const legacyId = buildStoreEntitlementId({
      provider: "google",
      originalTransactionHash: purchase.linkedTransactionHash,
    });
    const legacy = await callback(findEntitlement)(legacyId);
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
  if (current) {
    const checkout = await callback(findCheckout)(current.checkoutId);
    if (!checkout) throw new InputError("STORE_PURCHASE_NOT_REGISTERED");
    return { existingEntitlement: current, checkout, superseded: false };
  }
  if (purchase.linkedTransactionHash) {
    if (!linked) {
      const staleCheckout = await uniqueCheckoutByAccountReference({
        event,
        findCheckoutsByAccountReference,
        productId: purchase.pendingProductId || purchase.productId,
      });
      if (staleCheckout?.entitlementId) {
        const staleEntitlement = await callback(findEntitlement)(staleCheckout.entitlementId);
        if (
          staleEntitlement?.provider === "google"
          && staleEntitlement.currentTransactionHash !== purchase.currentTransactionHash
          && staleEntitlement.checkoutId !== staleCheckout._id
        ) {
          return {
            existingEntitlement: staleEntitlement,
            checkout: staleCheckout,
            superseded: true,
          };
        }
      }
      throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
    }
    const checkout = await uniqueCheckoutByAccountReference({
      event,
      findCheckoutsByAccountReference,
      productId: purchase.pendingProductId || purchase.productId,
    });
    if (!checkout) throw new InputError("STORE_PURCHASE_NOT_REGISTERED");
    if (checkout.entitlementId && checkout.entitlementId !== linked._id) {
      throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
    }
    return { existingEntitlement: linked, checkout, superseded: false };
  }

  const rootId = buildStoreEntitlementId(purchase);
  const root = await callback(findEntitlement)(rootId);
  if (
    root
    && root.provider === "google"
    && (root.currentTransactionHash ?? root.originalTransactionHash)
      === purchase.currentTransactionHash
  ) {
    const checkout = await callback(findCheckout)(root.checkoutId);
    if (!checkout) throw new InputError("STORE_PURCHASE_NOT_REGISTERED");
    return { existingEntitlement: root, checkout, superseded: false };
  }

  const checkout = await uniqueCheckoutByAccountReference({
    event,
    findCheckoutsByAccountReference,
    productId: purchase.productId,
  });
  if (!checkout?.entitlementId) {
    return { existingEntitlement: null, checkout, superseded: false };
  }
  const checkoutEntitlement = await callback(findEntitlement)(checkout.entitlementId);
  if (!checkoutEntitlement || checkoutEntitlement.provider !== "google") {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  if (checkoutEntitlement.currentTransactionHash === purchase.currentTransactionHash) {
    return {
      existingEntitlement: checkoutEntitlement,
      checkout,
      superseded: false,
    };
  }
  if (checkoutEntitlement.checkoutId !== checkout._id) {
    return {
      existingEntitlement: checkoutEntitlement,
      checkout,
      superseded: true,
    };
  }
  throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
}

export async function processStoreLifecycleEvent({
  event,
  signingSecret,
  signingKeyring,
  nowMs = Date.now(),
  beginEvent,
  completeEvent,
  findEntitlement,
  findEntitlementsByCurrentTransactionHash,
  findCheckout,
  findCheckoutsByAccountReference,
  persistEntitlement,
  projectProfessional,
  projectReplacementProfessional,
  acknowledgeGoogle,
  allowSandbox = false,
}) {
  if (event?.purchase?.environment === "sandbox" && allowSandbox !== true) {
    throw new InputError("STORE_ENVIRONMENT_MISMATCH");
  }
  let existingEntitlement;
  let checkout;
  let superseded = false;
  if (event?.purchase?.provider === "google") {
    const context = await resolveGoogleContext({
      event,
      findEntitlement,
      findCheckout,
      findEntitlementsByCurrentTransactionHash,
      findCheckoutsByAccountReference,
    });
    ({ existingEntitlement, checkout, superseded } = context);
  } else {
    const possibleEntitlementId = buildStoreEntitlementId(event?.purchase);
    existingEntitlement = await callback(findEntitlement)(possibleEntitlementId);
    if (existingEntitlement) {
      checkout = await callback(findCheckout)(existingEntitlement.checkoutId);
    } else {
      checkout = await uniqueCheckoutByAccountReference({
        event,
        findCheckoutsByAccountReference,
        productId: event.purchase.productId,
      });
    }
  }
  const entitlementId = existingEntitlement?._id ?? buildStoreEntitlementId(event?.purchase);
  const eventDraft = buildStoreEventRecord(event, entitlementId, nowMs);
  const begun = await callback(beginEvent)(eventDraft);
  if (!begun?.item || begun.item._id !== eventDraft._id) {
    throw new InputError("INVALID_STORE_EVENT");
  }
  if (["processed", "ignored"].includes(begun.item.status)) {
    return Object.freeze({
      received: true,
      idempotent: true,
      ignored: begun.item.status === "ignored",
      event: begun.item,
    });
  }

  if (!checkout) {
    const completed = await callback(completeEvent)(begun.item, {
      status: "ignored",
      outcome: "entitlement_not_registered",
      processedAt: new Date(nowMs).toISOString(),
    });
    return Object.freeze({
      received: true,
      idempotent: Boolean(begun.idempotent),
      ignored: true,
      event: completed,
    });
  }
  const expectedAccountToken = deriveStoreAccountToken(
    checkout,
    signingKeyring ?? signingSecret,
  );
  if (event.accountToken !== expectedAccountToken) {
    throw new InputError("STORE_ACCOUNT_MISMATCH");
  }
  if (superseded) {
    const completed = await callback(completeEvent)(begun.item, {
      status: "ignored",
      outcome: "superseded_purchase_token",
      processedAt: new Date(nowMs).toISOString(),
    });
    return Object.freeze({
      received: true,
      idempotent: Boolean(begun.idempotent),
      ignored: true,
      event: completed,
    });
  }
  if (
    existingEntitlement
    && (
      existingEntitlement._id !== entitlementId
      || existingEntitlement.provider !== event.purchase.provider
      || (
        event.purchase.provider !== "google"
        && existingEntitlement.originalTransactionHash !== event.purchase.originalTransactionHash
      )
    )
  ) {
    throw new InputError("STORE_PURCHASE_ALREADY_USED");
  }

  const replacingGoogleCheckout = event.purchase.provider === "google"
    && existingEntitlement
    && existingEntitlement.checkoutId !== checkout._id;
  const entitlementDraft = event.purchase.provider === "google"
    ? existingEntitlement
      ? buildGoogleLineageEntitlementRecord(
        checkout,
        event.purchase,
        existingEntitlement,
        nowMs,
      )
      : buildEntitlementRecord(checkout, event.purchase, nowMs)
    : buildLifecycleEntitlementRecord(
      checkout,
      event.purchase,
      existingEntitlement,
      nowMs,
    );
  const persisted = await callback(persistEntitlement)(entitlementDraft);
  if (!persisted?.item || persisted.item._id !== entitlementId) {
    throw new InputError("INVALID_ENTITLEMENT");
  }
  const projector = replacingGoogleCheckout
    ? callback(projectReplacementProfessional)
    : callback(projectProfessional);
  const projection = await projector({
    checkout,
    entitlement: persisted.item,
    previousEntitlement: existingEntitlement,
  });
  if (!projection?.professional || projection.professional._id !== persisted.item.professionalId) {
    throw new InputError("INVALID_STORE_FINALIZATION");
  }

  if (event.provider === "google" && event.purchase.needsAcknowledgement) {
    await callback(acknowledgeGoogle)({
      purchaseToken: event.verificationData,
      productId: event.acknowledgementProductId ?? event.purchase.productId,
    });
  }
  const completed = await callback(completeEvent)(begun.item, {
    status: "processed",
    outcome: persisted.item.status,
    processedAt: new Date(nowMs).toISOString(),
  });
  return Object.freeze({
    received: true,
    idempotent: Boolean(begun.idempotent && persisted.idempotent),
    ignored: false,
    entitlement: persisted.item,
    professional: projection.professional,
    event: completed,
  });
}
