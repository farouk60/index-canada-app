import assert from "node:assert/strict";
import test from "node:test";

import {
  InputError,
  buildPersistedCheckoutDraft,
} from "../security-core.js";
import {
  APP_BUNDLE_ID,
  buildEntitlementRecord,
  createStoreCheckoutDraft,
  createStoreSigningKeyring,
  deriveStoreAccountToken,
  normalizeGooglePurchase,
} from "../store-purchase-core.js";
import {
  buildStoreEventRecord,
  decodeGoogleRtdnEnvelope,
  normalizeAppleLifecycleEvent,
  normalizeGoogleLifecycleEvent,
  validateGooglePendingPurchaseCanceled,
} from "../store-notification-core.js";
import { processStoreLifecycleEvent } from "../store-notification-service.js";
import {
  StoreProviderError,
  createGooglePushTokenVerifier,
} from "../store-purchase-verifiers.js";

const NOW = Date.UTC(2026, 8, 25, 18, 0, 0);
const SIGNING_SECRET = "test-only-notification-signing-secret-with-at-least-32-characters";
const ROTATED_SIGNING_SECRET = "test-only-rotated-notification-secret-with-at-least-32-characters";
const PRODUCT = "ca.indexcanada.app.premium.annual";
const PROFESSIONAL_PRODUCT = "ca.indexcanada.app.professional.annual";
const ACCOUNT_TOKEN = "123e4567-e89b-42d3-a456-426614174000";

function registration() {
  return {
    professionalId: "temp_1758812400000",
    email: "owner@example.ca",
    businessName: "Cabinet Exemple",
    categoryId: "legal-services",
    ville: "Montréal",
    phone: "+1 514 555 0101",
    address: "100 rue Exemple, Montréal",
    description: "Conseils pour les nouveaux arrivants",
  };
}

function checkout(store = "google_play") {
  const draft = createStoreCheckoutDraft({
    ...registration(),
    planId: "premium",
    store,
  }, SIGNING_SECRET, NOW - 60_000);
  return buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
}

function googleResponse(accountToken, overrides = {}) {
  return {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(NOW - 30 * 24 * 60 * 60 * 1000).toISOString(),
    lineItems: [{
      productId: PRODUCT,
      expiryTime: new Date(NOW + 335 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    etag: "notification-etag",
    ...overrides,
  };
}

function googleRtdnEnvelope(notification, messageId = "1234567890123456") {
  const data = Buffer.from(JSON.stringify({
    version: "1.0",
    packageName: APP_BUNDLE_ID,
    eventTimeMillis: String(NOW - 1_000),
    ...notification,
  }), "utf8").toString("base64");
  return {
    message: {
      data,
      messageId,
      publishTime: new Date(NOW).toISOString(),
    },
    subscription: "projects/index-canada/subscriptions/play-rtdn",
  };
}

function rtdnEnvelope(notificationType = 2) {
  return googleRtdnEnvelope({
    subscriptionNotification: {
      version: "1.0",
      notificationType,
      purchaseToken: "google-token-never-persisted",
    },
  });
}

test("Apple V2 normalise renouvellement, révocation et expiration sans conserver les JWS", () => {
  const notification = {
    notificationType: "DID_RENEW",
    subtype: "BILLING_RECOVERY",
    notificationUUID: "123e4567-e89b-42d3-a456-426614174001",
    version: "2.0",
    signedDate: NOW - 1_000,
    data: {
      bundleId: APP_BUNDLE_ID,
      environment: "Sandbox",
      status: 1,
      signedTransactionInfo: "transaction.header.signature",
    },
  };
  const transaction = {
    bundleId: APP_BUNDLE_ID,
    productId: PRODUCT,
    appAccountToken: ACCOUNT_TOKEN,
    environment: "Sandbox",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: NOW - 30 * 24 * 60 * 60 * 1000,
    expiresDate: NOW + 335 * 24 * 60 * 60 * 1000,
    signedDate: NOW - 900,
    type: "Auto-Renewable Subscription",
  };
  const renewed = normalizeAppleLifecycleEvent(notification, transaction, {
    signedPayload: "notification.header.signature",
    signedTransactionInfo: "transaction.header.signature",
    nowMs: NOW,
  });
  assert.equal(renewed.purchase.status, "active");
  assert.equal(renewed.eventType, "DID_RENEW:BILLING_RECOVERY");
  assert.equal(JSON.stringify(buildStoreEventRecord(renewed, "ent_1234567890abcdef1234567890abcdef", NOW))
    .includes("notification.header.signature"), false);
  assert.equal(JSON.stringify(renewed.purchase).includes(transaction.transactionId), false);

  const revoked = normalizeAppleLifecycleEvent({
    ...notification,
    notificationType: "REFUND",
    subtype: undefined,
    notificationUUID: "123e4567-e89b-42d3-a456-426614174002",
    data: { ...notification.data, status: 5 },
  }, { ...transaction, revocationDate: NOW - 500 }, {
    signedPayload: "refund.header.signature",
    signedTransactionInfo: "refund-transaction.header.signature",
    nowMs: NOW,
  });
  assert.equal(revoked.purchase.status, "revoked");

  const expired = normalizeAppleLifecycleEvent({
    ...notification,
    notificationType: "EXPIRED",
    subtype: "VOLUNTARY",
    notificationUUID: "123e4567-e89b-42d3-a456-426614174003",
    data: { ...notification.data, status: 2 },
  }, { ...transaction, expiresDate: NOW - 1 }, {
    signedPayload: "expired.header.signature",
    signedTransactionInfo: "expired-transaction.header.signature",
    nowMs: NOW,
  });
  assert.equal(expired.purchase.status, "expired");

  assert.throws(() => normalizeAppleLifecycleEvent({
    ...notification,
    data: { ...notification.data, bundleId: "ca.example.other" },
  }, transaction, {
    signedPayload: "notification.header.signature",
    signedTransactionInfo: "transaction.header.signature",
    nowMs: NOW,
  }), (error) => error instanceof InputError && error.code === "STORE_APP_MISMATCH");
});

test("Google RTDN valide l'enveloppe et normalise renouvellement, révocation et expiration", () => {
  const decoded = decodeGoogleRtdnEnvelope(rtdnEnvelope(), {
    expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
    nowMs: NOW,
  });
  assert.equal(decoded.notificationType, 2);
  assert.equal(Object.hasOwn(decoded, "productId"), false);
  assert.equal(decoded.purchaseToken, "google-token-never-persisted");

  const renewed = normalizeGoogleLifecycleEvent(decoded, googleResponse(ACCOUNT_TOKEN), { nowMs: NOW });
  assert.equal(renewed.purchase.status, "active");
  assert.equal(renewed.purchase.productId, PRODUCT);
  assert.equal(renewed.acknowledgementProductId, PRODUCT);
  assert.equal(renewed.eventType, "SUBSCRIPTION_RENEWED");

  for (const [notificationType, eventType] of [
    [17, "SUBSCRIPTION_ITEMS_CHANGED"],
    [18, "SUBSCRIPTION_CANCELLATION_SCHEDULED"],
  ]) {
    const lifecycle = normalizeGoogleLifecycleEvent(
      decodeGoogleRtdnEnvelope(rtdnEnvelope(notificationType), {
        expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
        nowMs: NOW,
      }),
      googleResponse(ACCOUNT_TOKEN),
      { nowMs: NOW },
    );
    assert.equal(lifecycle.eventType, eventType);
    assert.equal(lifecycle.purchase.productId, PRODUCT);
    assert.equal(lifecycle.purchase.status, "active");
  }

  const deferredExpiry = new Date(NOW + 60_000).toISOString();
  const deferred = normalizeGoogleLifecycleEvent({
    ...decoded,
    notificationType: 4,
    eventType: "SUBSCRIPTION_PURCHASED",
    productId: PROFESSIONAL_PRODUCT,
    purchaseToken: "replacement-token-never-persisted",
  }, googleResponse(ACCOUNT_TOKEN, {
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    linkedPurchaseToken: "predecessor-token-never-persisted",
    startTime: undefined,
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: deferredExpiry,
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: false },
      deferredItemReplacement: { productId: PRODUCT },
    }, {
      productId: PRODUCT,
    }],
  }), { nowMs: NOW });
  assert.equal(deferred.purchase.productId, PROFESSIONAL_PRODUCT);
  assert.equal(deferred.purchase.pendingProductId, PRODUCT);
  assert.equal(deferred.purchase.pendingEffectiveAt, deferredExpiry);
  assert.equal(deferred.acknowledgementProductId, PROFESSIONAL_PRODUCT);
  assert.equal(JSON.stringify(deferred.purchase).includes("replacement-token-never-persisted"), false);

  const revokedRtdn = decodeGoogleRtdnEnvelope(rtdnEnvelope(12), {
    expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
    nowMs: NOW,
  });
  assert.equal(normalizeGoogleLifecycleEvent(
    revokedRtdn,
    googleResponse(ACCOUNT_TOKEN),
    { nowMs: NOW },
  ).purchase.status, "revoked");

  const expiredRtdn = decodeGoogleRtdnEnvelope(rtdnEnvelope(13), {
    expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
    nowMs: NOW,
  });
  assert.equal(normalizeGoogleLifecycleEvent(
    expiredRtdn,
    googleResponse(ACCOUNT_TOKEN, {
      subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
      lineItems: [{
        ...googleResponse(ACCOUNT_TOKEN).lineItems[0],
        expiryTime: new Date(NOW - 1).toISOString(),
      }],
    }),
    { nowMs: NOW },
  ).purchase.status, "expired");

  assert.equal(normalizeGoogleLifecycleEvent({
    ...expiredRtdn,
    productId: PRODUCT,
    purchaseToken: "replacement-token-never-persisted",
  }, googleResponse(ACCOUNT_TOKEN, {
    subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
    linkedPurchaseToken: "predecessor-token-never-persisted",
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW - 2_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: false },
    }, {
      productId: PRODUCT,
      expiryTime: new Date(NOW - 1_000).toISOString(),
      latestSuccessfulOrderId: "GPA.2222-2222-2222-22222",
      autoRenewingPlan: { autoRenewEnabled: false },
    }],
  }), { nowMs: NOW }).purchase.status, "expired");

  assert.throws(() => normalizeGoogleLifecycleEvent({
    ...decoded,
    productId: PRODUCT,
    purchaseToken: "premature-effective-token-never-persisted",
  }, googleResponse(ACCOUNT_TOKEN, {
    linkedPurchaseToken: "predecessor-token-never-persisted",
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW + 30_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: false },
    }, {
      productId: PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.2222-2222-2222-22222",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
  }), { nowMs: NOW }), (error) => error instanceof InputError
    && error.code === "STORE_PRODUCT_MISMATCH");

  assert.throws(() => decodeGoogleRtdnEnvelope(rtdnEnvelope(), {
    expectedSubscription: "projects/other/subscriptions/wrong",
    nowMs: NOW,
  }), (error) => error instanceof InputError && error.code === "GOOGLE_RTDN_SUBSCRIPTION_MISMATCH");

  const unsupportedVersion = rtdnEnvelope();
  const payload = JSON.parse(Buffer.from(unsupportedVersion.message.data, "base64").toString("utf8"));
  payload.subscriptionNotification.version = "2.0";
  unsupportedVersion.message.data = Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
  assert.throws(() => decodeGoogleRtdnEnvelope(unsupportedVersion, {
    expectedSubscription: unsupportedVersion.subscription,
    nowMs: NOW,
  }), (error) => error instanceof InputError && error.code === "INVALID_GOOGLE_RTDN");
});

test("Google RTDN type 20 valide l'annulation en attente sans normaliser de lineItem", () => {
  const rtdn = decodeGoogleRtdnEnvelope(rtdnEnvelope(20), {
    expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
    nowMs: NOW,
  });
  const initial = validateGooglePendingPurchaseCanceled(rtdn, {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED",
  });
  assert.deepEqual(initial, { ignored: true });

  const replacement = validateGooglePendingPurchaseCanceled({
    ...rtdn,
    purchaseToken: "current-pending-token-never-persisted",
  }, {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED",
    linkedPurchaseToken: "linked-predecessor-token-never-persisted",
  });
  assert.deepEqual(replacement, { ignored: true });
  assert.equal(
    JSON.stringify(replacement).includes("linked-predecessor-token-never-persisted"),
    false,
  );

  assert.throws(() => validateGooglePendingPurchaseCanceled(rtdn, {
    packageName: "ca.example.other",
    subscriptionState: "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED",
  }), (error) => error instanceof InputError && error.code === "STORE_APP_MISMATCH");
  assert.throws(() => validateGooglePendingPurchaseCanceled(rtdn, {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
  }), (error) => error instanceof InputError && error.code === "UNTRUSTED_STORE_NOTIFICATION");
  assert.throws(() => validateGooglePendingPurchaseCanceled(rtdn, {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED",
    linkedPurchaseToken: "",
  }), (error) => error instanceof InputError && error.code === "UNTRUSTED_STORE_NOTIFICATION");
  assert.throws(() => validateGooglePendingPurchaseCanceled(rtdn, {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED",
    linkedPurchaseToken: rtdn.purchaseToken,
  }), (error) => error instanceof InputError && error.code === "STORE_PURCHASE_LINEAGE_INVALID");
});

test("Google RTDN acquitte sans mutation les familles non-abonnement validées", () => {
  const expectedSubscription = "projects/index-canada/subscriptions/play-rtdn";
  const fixtures = [{
    notification: {
      oneTimeProductNotification: {
        version: "1.0",
        notificationType: 1,
        purchaseToken: "one-time-token-never-persisted",
        sku: "one.time.product",
      },
    },
    family: "one_time_product",
    eventType: "ONE_TIME_PRODUCT_PURCHASED",
  }, {
    notification: {
      voidedPurchaseNotification: {
        purchaseToken: "voided-token-never-persisted",
        orderId: "GPA.1234-5678-9012-34567",
        productType: 1,
        refundType: 1,
      },
    },
    family: "voided_purchase",
    eventType: "VOIDED_SUBSCRIPTION_FULL_REFUND",
  }, {
    notification: {
      pendingRefundReviewNotification: {
        version: "1.0",
        pendingRefundToken: "pending-refund-token-never-persisted",
        orderId: "GPA.1234-5678-9012-34567",
        refundReason: 7,
        obfuscatedAccountId: ACCOUNT_TOKEN,
      },
    },
    family: "pending_refund_review",
    eventType: "PENDING_REFUND_REVIEW",
  }];

  for (const [index, fixture] of fixtures.entries()) {
    const decoded = decodeGoogleRtdnEnvelope(
      googleRtdnEnvelope(fixture.notification, `ignored-${index}-1234567890`),
      { expectedSubscription, nowMs: NOW },
    );
    assert.equal(decoded.ignored, true);
    assert.equal(decoded.notificationFamily, fixture.family);
    assert.equal(decoded.eventType, fixture.eventType);
    const serialized = JSON.stringify(decoded);
    assert.equal(serialized.includes("token-never-persisted"), false);
    assert.equal(serialized.includes("GPA.1234-5678-9012-34567"), false);
    assert.equal(serialized.includes(ACCOUNT_TOKEN), false);
  }

  const mutuallyExclusive = googleRtdnEnvelope({
    subscriptionNotification: {
      version: "1.0",
      notificationType: 2,
      purchaseToken: "subscription-token-never-persisted",
    },
    oneTimeProductNotification: {
      version: "1.0",
      notificationType: 1,
      purchaseToken: "one-time-token-never-persisted",
      sku: "one.time.product",
    },
  });
  assert.throws(() => decodeGoogleRtdnEnvelope(mutuallyExclusive, {
    expectedSubscription,
    nowMs: NOW,
  }), (error) => error instanceof InputError && error.code === "INVALID_GOOGLE_RTDN");
});

test("le traitement d'un événement est idempotent et projette la révocation sans activer la fiche", async () => {
  const storedCheckout = checkout("google_play");
  const accountToken = deriveStoreAccountToken(storedCheckout, SIGNING_SECRET);
  const activePurchase = normalizeGooglePurchase(googleResponse(accountToken), {
    checkout: storedCheckout,
    accountToken,
    verificationData: "google-token-never-persisted",
    nowMs: NOW - 5_000,
  });
  const entitlement = buildEntitlementRecord(storedCheckout, activePurchase, NOW - 5_000);
  const decoded = decodeGoogleRtdnEnvelope(rtdnEnvelope(12), {
    expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
    nowMs: NOW,
  });
  const event = normalizeGoogleLifecycleEvent(
    decoded,
    googleResponse(accountToken),
    { nowMs: NOW },
  );
  const calls = [];
  let completedEvent;
  const result = await processStoreLifecycleEvent({
    event,
    signingKeyring: createStoreSigningKeyring(
      ROTATED_SIGNING_SECRET,
      [SIGNING_SECRET],
    ),
    allowSandbox: true,
    nowMs: NOW,
    beginEvent: async (record) => {
      calls.push("event");
      assert.equal(JSON.stringify(record).includes("google-token-never-persisted"), false);
      return { item: record, idempotent: false };
    },
    findEntitlement: async () => entitlement,
    findCheckout: async () => storedCheckout,
    persistEntitlement: async (record) => {
      calls.push("entitlement");
      assert.equal(record.status, "revoked");
      return { item: record, idempotent: false };
    },
    projectProfessional: async ({ entitlement: updated }) => {
      calls.push("professional");
      assert.equal(updated.status, "revoked");
      return { professional: { _id: updated.professionalId, isActive: false } };
    },
    completeEvent: async (record, patch) => {
      calls.push("complete");
      completedEvent = { ...record, ...patch };
      return completedEvent;
    },
  });
  assert.deepEqual(calls, ["event", "entitlement", "professional", "complete"]);
  assert.equal(result.entitlement.status, "revoked");
  assert.equal(result.professional.isActive, false);
  assert.equal(completedEvent.status, "processed");
});

test("l'authentification Pub/Sub vérifie officiellement audience et compte de service", async () => {
  const calls = [];
  class FakeOAuth2Client {
    async verifyIdToken(options) {
      calls.push(options);
      return {
        getPayload: () => ({
          email: "rtdn-push@index-canada.iam.gserviceaccount.com",
          email_verified: true,
          sub: "1234567890",
        }),
      };
    }
  }
  const verifier = await createGooglePushTokenVerifier({
    audience: "https://www.indexcanada.ca/_functions/googlePlayRtdn",
    serviceAccountEmail: "rtdn-push@index-canada.iam.gserviceaccount.com",
    libraryLoader: async () => ({ OAuth2Client: FakeOAuth2Client }),
  });
  await verifier.verifyAuthorization("Bearer header.payload.signature");
  assert.equal(calls[0].audience, "https://www.indexcanada.ca/_functions/googlePlayRtdn");
  assert.equal(calls[0].idToken, "header.payload.signature");

  const wrongAccount = await createGooglePushTokenVerifier({
    audience: "https://www.indexcanada.ca/_functions/googlePlayRtdn",
    serviceAccountEmail: "expected@index-canada.iam.gserviceaccount.com",
    libraryLoader: async () => ({ OAuth2Client: FakeOAuth2Client }),
  });
  await assert.rejects(
    () => wrongAccount.verifyAuthorization("Bearer secret.jwt.value"),
    (error) => error instanceof StoreProviderError
      && error.code === "GOOGLE_PUSH_UNAUTHORIZED"
      && !error.message.includes("secret.jwt.value"),
  );
});
