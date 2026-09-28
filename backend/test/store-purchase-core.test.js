import assert from "node:assert/strict";
import test from "node:test";

import {
  InputError,
  buildPersistedCheckoutDraft,
  buildProfessionalRecord,
} from "../security-core.js";
import {
  APP_BUNDLE_ID,
  buildEntitlementRecord,
  buildGoogleLineageEntitlementRecord,
  buildLifecycleEntitlementRecord,
  buildStoreEntitlementId,
  createStoreCheckoutDraft,
  createStoreSigningKeyring,
  deriveStoreAccountToken,
  identifyGooglePurchase,
  normalizeApplePurchase,
  normalizeGooglePurchase,
  reconcileEntitlement,
  selectGoogleSubscriptionLineItem,
  selectLatestStoreEntitlement,
  validateStoreCheckout,
  validateStoreConfirmation,
  validateStoreRestoration,
} from "../store-purchase-core.js";
import {
  confirmStorePurchaseWithDependencies,
  restoreStorePurchaseWithDependencies,
} from "../store-purchase-service.js";

const NOW = Date.UTC(2026, 8, 25, 15, 0, 0);
const SIGNING_SECRET = "test-only-store-signing-secret-with-more-than-32-characters";
const ROTATED_SIGNING_SECRET = "test-only-rotated-store-signing-secret-with-more-than-32-characters";
const PREMIUM_PRODUCT = "ca.indexcanada.app.premium.annual";
const PROFESSIONAL_PRODUCT = "ca.indexcanada.app.professional.annual";

function registration(overrides = {}) {
  return {
    professionalId: "temp_1758812400000",
    email: "owner@example.ca",
    businessName: "Cabinet Exemple",
    categoryId: "legal-services",
    ville: "Montréal",
    phone: "+1 514 555 0101",
    address: "100 rue Exemple, Montréal",
    description: "Conseils pour les nouveaux arrivants",
    ...overrides,
  };
}

function persistedStoreCheckout(store = "app_store") {
  const transient = createStoreCheckoutDraft({
    ...registration(),
    planId: "premium",
    store,
  }, SIGNING_SECRET, NOW);
  return buildPersistedCheckoutDraft(transient, { profile: "", gallery: [] });
}

function expectInputError(callback, code) {
  assert.throws(callback, (error) => error instanceof InputError && error.code === code);
}

test("le checkout magasin est déterministe et ne persiste jamais le jeton de compte", () => {
  const first = createStoreCheckoutDraft({
    ...registration(),
    planId: "premium",
    store: "app_store",
  }, SIGNING_SECRET, NOW);
  const retry = createStoreCheckoutDraft({
    ...registration(),
    planId: "premium",
    store: "app_store",
  }, SIGNING_SECRET, NOW + 10_000);
  const google = createStoreCheckoutDraft({
    ...registration(),
    planId: "premium",
    store: "google_play",
  }, SIGNING_SECRET, NOW);

  assert.equal(first._id, retry._id);
  assert.notEqual(first._id, google._id);
  assert.equal(first.paymentProvider, "apple");
  assert.equal(google.paymentProvider, "google");
  assert.equal(first.storeProductId, PREMIUM_PRODUCT);
  assert.match(first.accountReferenceHash, /^[a-f0-9]{64}$/u);
  assert.equal(validateStoreCheckout(first).id, "premium");

  const token = deriveStoreAccountToken(first, SIGNING_SECRET);
  assert.match(token, /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/u);
  assert.equal(JSON.stringify(first).includes(token), false);
  assert.equal(JSON.stringify(first).includes("appAccountToken"), false);
  assert.equal(JSON.stringify(first).includes("obfuscatedExternalAccountId"), false);

  expectInputError(() => createStoreCheckoutDraft({
    ...registration(),
    planId: "basic",
    store: "app_store",
  }, SIGNING_SECRET, NOW), "STORE_PAYMENT_NOT_REQUIRED");
});

test("la rotation conserve les jetons des checkouts existants sans persister de secret", () => {
  const originalKeyring = createStoreSigningKeyring(SIGNING_SECRET, []);
  const checkout = createStoreCheckoutDraft({
    ...registration(),
    planId: "premium",
    store: "app_store",
  }, originalKeyring, NOW);
  const originalToken = deriveStoreAccountToken(checkout, originalKeyring);
  const rotatedKeyring = createStoreSigningKeyring(
    ROTATED_SIGNING_SECRET,
    [SIGNING_SECRET],
  );

  assert.equal(deriveStoreAccountToken(checkout, rotatedKeyring), originalToken);
  assert.equal(JSON.stringify(rotatedKeyring).includes(SIGNING_SECRET), false);
  assert.equal(JSON.stringify(rotatedKeyring).includes(ROTATED_SIGNING_SECRET), false);
  assert.match(checkout.accountSigningKeyId, /^ssk_[a-f0-9]{16}$/u);
  assert.equal(JSON.stringify(checkout).includes(SIGNING_SECRET), false);
  assert.equal(JSON.stringify(checkout).includes(ROTATED_SIGNING_SECRET), false);

  const newCheckout = createStoreCheckoutDraft({
    ...registration({ professionalId: "temp_1758812400001" }),
    planId: "premium",
    store: "app_store",
  }, rotatedKeyring, NOW);
  assert.notEqual(newCheckout.accountSigningKeyId, checkout.accountSigningKeyId);
  assert.notEqual(
    deriveStoreAccountToken(newCheckout, rotatedKeyring),
    originalToken,
  );
});

test("la rotation résout les checkouts historiques sans version et échoue si l'ancienne clé manque", () => {
  const original = createStoreCheckoutDraft({
    ...registration(),
    planId: "premium",
    store: "google_play",
  }, SIGNING_SECRET, NOW);
  const legacyCheckout = { ...original };
  delete legacyCheckout.accountSigningKeyId;
  const originalToken = deriveStoreAccountToken(legacyCheckout, SIGNING_SECRET);
  const rotatedKeyring = createStoreSigningKeyring(
    ROTATED_SIGNING_SECRET,
    [SIGNING_SECRET],
  );

  assert.equal(deriveStoreAccountToken(legacyCheckout, rotatedKeyring), originalToken);
  expectInputError(
    () => deriveStoreAccountToken(
      legacyCheckout,
      createStoreSigningKeyring(ROTATED_SIGNING_SECRET, []),
    ),
    "STORE_SIGNING_KEY_UNAVAILABLE",
  );
  expectInputError(
    () => createStoreSigningKeyring(ROTATED_SIGNING_SECRET, "not-an-array"),
    "INVALID_SIGNING_KEYRING",
  );
});

test("la confirmation est liée au checkout, au magasin et au produit attendus", () => {
  const checkout = persistedStoreCheckout();
  const confirmation = validateStoreConfirmation({
    checkoutId: checkout._id,
    store: "app_store",
    productId: PREMIUM_PRODUCT,
    verificationData: "header.payload.signature",
    purchaseId: "2000000912345678",
  }, checkout);

  assert.equal(confirmation.checkoutId, checkout._id);
  assert.equal(confirmation.verificationData, "header.payload.signature");
  expectInputError(() => validateStoreConfirmation({
    ...confirmation,
    productId: "ca.indexcanada.app.professional.annual",
  }, checkout), "STORE_PURCHASE_MISMATCH");
  expectInputError(() => validateStoreConfirmation({
    ...confirmation,
    store: "google_play",
  }, checkout), "STORE_PURCHASE_MISMATCH");
});

test("Apple exige le bundle, le produit, le compte, une échéance future et aucune révocation", () => {
  const checkout = persistedStoreCheckout("app_store");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const decoded = {
    bundleId: APP_BUNDLE_ID,
    productId: PREMIUM_PRODUCT,
    appAccountToken: accountToken,
    environment: "Sandbox",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: NOW - 1_000,
    expiresDate: NOW + 365 * 24 * 60 * 60 * 1000,
    type: "Auto-Renewable Subscription",
  };

  const purchase = normalizeApplePurchase(decoded, {
    checkout,
    accountToken,
    verificationData: "signed-jws-never-persisted",
    purchaseId: decoded.transactionId,
    nowMs: NOW,
  });

  assert.equal(purchase.provider, "apple");
  assert.equal(purchase.status, "active");
  assert.equal(purchase.environment, "sandbox");
  assert.match(purchase.originalTransactionHash, /^[a-f0-9]{64}$/u);
  assert.equal(JSON.stringify(purchase).includes(decoded.transactionId), false);
  assert.equal(JSON.stringify(purchase).includes(accountToken), false);
  assert.equal(JSON.stringify(purchase).includes("signed-jws-never-persisted"), false);

  for (const [patch, code] of [
    [{ bundleId: "ca.example.other" }, "STORE_APP_MISMATCH"],
    [{ productId: "ca.indexcanada.app.professional.annual" }, "STORE_PRODUCT_MISMATCH"],
    [{ appAccountToken: "00000000-0000-4000-8000-000000000000" }, "STORE_ACCOUNT_MISMATCH"],
    [{ expiresDate: NOW }, "STORE_PURCHASE_EXPIRED"],
    [{ revocationDate: NOW - 1 }, "STORE_PURCHASE_REVOKED"],
    [{ isUpgraded: true }, "STORE_PURCHASE_REPLACED"],
  ]) {
    expectInputError(() => normalizeApplePurchase({ ...decoded, ...patch }, {
      checkout,
      accountToken,
      verificationData: "signed-jws-never-persisted",
      purchaseId: decoded.transactionId,
      nowMs: NOW,
    }), code);
  }
});

test("Google contrôle package, produit, compte obscurci, état, échéance et révocation", () => {
  const checkout = persistedStoreCheckout("google_play");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const response = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    startTime: new Date(NOW - 5_000).toISOString(),
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    etag: "opaque-etag",
  };

  const purchase = normalizeGooglePurchase(response, {
    checkout,
    accountToken,
    verificationData: "google-purchase-token-never-persisted",
    purchaseId: "GPA.1234-5678-9012-34567",
    nowMs: NOW,
  });

  assert.equal(purchase.provider, "google");
  assert.equal(purchase.status, "active");
  assert.equal(purchase.environment, "production");
  assert.equal(purchase.needsAcknowledgement, true);
  assert.equal(JSON.stringify(purchase).includes("google-purchase-token-never-persisted"), false);
  assert.equal(JSON.stringify(purchase).includes(accountToken), false);

  const grace = normalizeGooglePurchase({
    ...response,
    subscriptionState: "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  }, {
    checkout,
    accountToken,
    verificationData: "another-token",
    nowMs: NOW,
  });
  assert.equal(grace.status, "grace_period");

  const indicativeOrderId = normalizeGooglePurchase(response, {
    checkout,
    accountToken,
    verificationData: "another-token",
    purchaseId: "client-order-id-is-only-a-hint",
    nowMs: NOW,
  });
  assert.equal(indicativeOrderId.status, "active");

  const canceled = normalizeGooglePurchase({
    ...response,
    subscriptionState: "SUBSCRIPTION_STATE_CANCELED",
  }, {
    checkout,
    accountToken,
    verificationData: "another-token",
    nowMs: NOW,
  });
  assert.equal(canceled.status, "active");

  for (const [patch, code] of [
    [{ packageName: "ca.example.other" }, "STORE_APP_MISMATCH"],
    [{ lineItems: [{ ...response.lineItems[0], productId: "other" }] }, "STORE_PRODUCT_MISMATCH"],
    [{ externalAccountIdentifiers: { obfuscatedExternalAccountId: "other" } }, "STORE_ACCOUNT_MISMATCH"],
    [{ subscriptionState: "SUBSCRIPTION_STATE_PENDING" }, "STORE_PURCHASE_NOT_ACTIVE"],
    [{ subscriptionState: "SUBSCRIPTION_STATE_ON_HOLD" }, "STORE_PURCHASE_NOT_ACTIVE"],
    [{ lineItems: [{ ...response.lineItems[0], expiryTime: new Date(NOW).toISOString() }] }, "STORE_PURCHASE_EXPIRED"],
    [{ revoked: true }, "STORE_PURCHASE_REVOKED"],
  ]) {
    expectInputError(() => normalizeGooglePurchase({ ...response, ...patch }, {
      checkout,
      accountToken,
      verificationData: "google-purchase-token-never-persisted",
      nowMs: NOW,
    }), code);
  }
});

test("Google dérive le produit RTDN depuis subscriptionsv2 sans subscriptionId", () => {
  const current = {
    productId: PREMIUM_PRODUCT,
    expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
    latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
    autoRenewingPlan: { autoRenewEnabled: true },
  };
  const single = selectGoogleSubscriptionLineItem({ lineItems: [current] }, {
    expectedRole: "effective",
    allowExpired: true,
    nowMs: NOW,
  });
  assert.equal(single.effectiveItem.productId, PREMIUM_PRODUCT);

  const historical = {
    productId: PROFESSIONAL_PRODUCT,
    expiryTime: new Date(NOW - 1_000).toISOString(),
    latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
    autoRenewingPlan: { autoRenewEnabled: false },
  };
  const transitioned = selectGoogleSubscriptionLineItem({
    lineItems: [historical, current],
  }, {
    expectedRole: "effective",
    allowExpired: true,
    nowMs: NOW,
  });
  assert.equal(transitioned.effectiveItem.productId, PREMIUM_PRODUCT);

  expectInputError(() => selectGoogleSubscriptionLineItem({
    lineItems: [
      current,
      {
        ...current,
        productId: PROFESSIONAL_PRODUCT,
        latestSuccessfulOrderId: "GPA.2222-2222-2222-22222",
      },
    ],
  }, {
    expectedRole: "effective",
    allowExpired: true,
    nowMs: NOW,
  }), "STORE_PRODUCT_MISMATCH");
});

test("l'Entitlement est distinct de la modération et ne contient que des références hachées", () => {
  const checkout = persistedStoreCheckout("app_store");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const purchase = normalizeApplePurchase({
    bundleId: APP_BUNDLE_ID,
    productId: PREMIUM_PRODUCT,
    appAccountToken: accountToken,
    environment: "Production",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: NOW - 1_000,
    expiresDate: NOW + 365 * 24 * 60 * 60 * 1000,
    type: "Auto-Renewable Subscription",
  }, {
    checkout,
    accountToken,
    verificationData: "signed-jws-never-persisted",
    nowMs: NOW,
  });
  const entitlement = buildEntitlementRecord(checkout, purchase, NOW);

  assert.match(entitlement._id, /^ent_[a-f0-9]{32}$/u);
  assert.equal(entitlement.status, "active");
  assert.equal(entitlement.professionalId.startsWith("idx_"), true);
  assert.equal(Object.hasOwn(entitlement, "registrationStatus"), false);
  assert.equal(Object.hasOwn(entitlement, "isActive"), false);
  assert.equal(JSON.stringify(entitlement).includes("owner@example.ca"), false);
  assert.equal(JSON.stringify(entitlement).includes("+1 514"), false);
  assert.equal(JSON.stringify(entitlement).includes("signed-jws-never-persisted"), false);
  assert.equal(JSON.stringify(entitlement).includes("2000000912345678"), false);

  assert.deepEqual(reconcileEntitlement(entitlement, { ...entitlement }), {
    action: "unchanged",
    item: entitlement,
    idempotent: true,
  });
  const renewed = {
    ...entitlement,
    expiresAt: new Date(NOW + 400 * 24 * 60 * 60 * 1000).toISOString(),
    sourceEventHash: "f".repeat(64),
    lastProviderEventAt: new Date(NOW + 1_000).toISOString(),
  };
  assert.equal(reconcileEntitlement(entitlement, renewed).action, "update");
  expectInputError(() => reconcileEntitlement(
    entitlement,
    { ...entitlement, checkoutId: "chk_00000000000000000000000000000000" },
  ), "STORE_PURCHASE_ALREADY_USED");
});

test("un droit actif ne contourne jamais la modération de la fiche professionnelle", () => {
  const checkout = persistedStoreCheckout("app_store");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const purchase = normalizeApplePurchase({
    bundleId: APP_BUNDLE_ID,
    productId: PREMIUM_PRODUCT,
    appAccountToken: accountToken,
    environment: "Production",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: NOW - 1_000,
    expiresDate: NOW + 365 * 24 * 60 * 60 * 1000,
    type: "Auto-Renewable Subscription",
  }, {
    checkout,
    accountToken,
    verificationData: "signed-jws-never-persisted",
    nowMs: NOW,
  });
  const entitlement = buildEntitlementRecord(checkout, purchase, NOW);
  const professional = buildProfessionalRecord(
    checkout,
    `store:apple:${purchase.lastTransactionHash}`,
    NOW,
    { entitlement },
  );

  assert.equal(professional.isActive, false);
  assert.equal(professional.registrationStatus, "pending_review");
  assert.equal(professional.entitlementStatus, "active");
  assert.equal(professional.entitlementId, entitlement._id);
  assert.equal(professional.entitlementExpiresAt, entitlement.expiresAt);
  assert.equal(professional.expiryDate, entitlement.expiresAt);
  assert.equal(professional.paymentProvider, "apple");
  assert.equal(JSON.stringify(professional).includes("2000000912345678"), false);
});

test("la livraison persiste le droit avant la fiche et acquitte Google en dernier", async () => {
  const checkout = persistedStoreCheckout("google_play");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const calls = [];
  const result = await confirmStorePurchaseWithDependencies({
    checkout,
    rawConfirmation: {
      checkoutId: checkout._id,
      store: "google_play",
      productId: PREMIUM_PRODUCT,
      verificationData: "purchase-token",
      purchaseId: "GPA.1234-5678-9012-34567",
    },
    signingSecret: SIGNING_SECRET,
    nowMs: NOW,
    verifyGoogle: async (token) => {
      calls.push(`verify:${token}`);
      return {
        packageName: APP_BUNDLE_ID,
        subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
        acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
        startTime: new Date(NOW - 1_000).toISOString(),
        lineItems: [{
          productId: PREMIUM_PRODUCT,
          expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
          latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
          autoRenewingPlan: { autoRenewEnabled: true },
        }],
        externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
      };
    },
    persistEntitlement: async (record) => {
      calls.push(`entitlement:${record._id}`);
      assert.equal(JSON.stringify(record).includes("purchase-token"), false);
      return { item: record, idempotent: false };
    },
    finalizeProfessional: async ({ entitlement, paymentReference }) => {
      calls.push(`professional:${entitlement.professionalId}`);
      assert.match(paymentReference, /^store:google:[a-f0-9]{64}$/u);
      return {
        checkout: { ...checkout, status: "finalized", entitlementId: entitlement._id },
        professional: {
          _id: entitlement.professionalId,
          registrationStatus: "pending_review",
          isActive: false,
        },
        idempotent: false,
      };
    },
    acknowledgeGoogle: async ({ purchaseToken, productId }) => {
      calls.push(`ack:${productId}:${purchaseToken}`);
    },
  });

  assert.deepEqual(calls.map((entry) => entry.split(":")[0]), [
    "verify",
    "entitlement",
    "professional",
    "ack",
  ]);
  assert.equal(result.completePurchase, true);
  assert.equal(result.professional.isActive, false);
  assert.equal(result.professional.registrationStatus, "pending_review");
});

test("la restauration retrouve le droit par preuve hachée sans checkout temporaire", async () => {
  const checkout = persistedStoreCheckout("google_play");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const rotatedKeyring = createStoreSigningKeyring(
    ROTATED_SIGNING_SECRET,
    [SIGNING_SECRET],
  );
  const providerResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(NOW - 1_000).toISOString(),
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    etag: "restore-etag",
  };
  const restoration = validateStoreRestoration({
    store: "google_play",
    productId: PREMIUM_PRODUCT,
    verificationData: "restored-purchase-token",
    purchaseId: "GPA.1234-5678-9012-34567",
  });
  const identified = identifyGooglePurchase(providerResponse, {
    productId: restoration.productId,
    verificationData: restoration.verificationData,
    purchaseId: restoration.purchaseId,
    nowMs: NOW,
  });
  const entitlement = buildEntitlementRecord(checkout, identified.purchase, NOW);
  assert.equal(buildStoreEntitlementId(identified.purchase), entitlement._id);

  const calls = [];
  const result = await restoreStorePurchaseWithDependencies({
    rawRestoration: restoration,
    signingKeyring: rotatedKeyring,
    nowMs: NOW,
    verifyGoogle: async (token) => {
      calls.push(`verify:${token}`);
      return providerResponse;
    },
    findEntitlement: async (id) => {
      calls.push(`entitlement:${id}`);
      return id === entitlement._id ? entitlement : null;
    },
    findCheckout: async (id) => {
      calls.push(`checkout:${id}`);
      return id === checkout._id ? checkout : null;
    },
    persistEntitlement: async (record) => ({ item: record, idempotent: true }),
    finalizeProfessional: async ({ entitlement: restored }) => ({
      checkout: { ...checkout, status: "finalized", entitlementId: restored._id },
      professional: {
        _id: restored.professionalId,
        registrationStatus: "pending_review",
        isActive: false,
      },
      idempotent: true,
    }),
    acknowledgeGoogle: async () => assert.fail("un achat déjà acquitté ne doit pas être acquitté de nouveau"),
  });

  assert.deepEqual(calls.map((entry) => entry.split(":")[0]), [
    "verify",
    "entitlement",
    "checkout",
  ]);
  assert.equal(result.restored, true);
  assert.equal(result.entitlement._id, entitlement._id);
  assert.equal(result.checkout._id, checkout._id);
  assert.equal(result.professional.isActive, false);
  assert.equal(JSON.stringify(result).includes("restored-purchase-token"), false);
  assert.equal(JSON.stringify(result).includes(accountToken), false);

  await assert.rejects(() => restoreStorePurchaseWithDependencies({
    rawRestoration: restoration,
    signingKeyring: rotatedKeyring,
    nowMs: NOW,
    verifyGoogle: async () => ({
      ...providerResponse,
      externalAccountIdentifiers: {
        obfuscatedExternalAccountId: "00000000-0000-4000-8000-000000000000",
      },
    }),
    findEntitlement: async () => entitlement,
    findCheckout: async () => checkout,
  }), (error) => error instanceof InputError && error.code === "STORE_ACCOUNT_MISMATCH");
});

test("la restauration Apple retrouve le même droit par originalTransactionId haché", async () => {
  const checkout = persistedStoreCheckout("app_store");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const decoded = {
    bundleId: APP_BUNDLE_ID,
    productId: PREMIUM_PRODUCT,
    appAccountToken: accountToken,
    environment: "Sandbox",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: NOW - 1_000,
    expiresDate: NOW + 365 * 24 * 60 * 60 * 1000,
    type: "Auto-Renewable Subscription",
  };
  const purchase = normalizeApplePurchase(decoded, {
    checkout,
    accountToken,
    verificationData: "header.payload.signature",
    purchaseId: decoded.transactionId,
    nowMs: NOW,
  });
  const entitlement = buildEntitlementRecord(checkout, purchase, NOW);

  const result = await restoreStorePurchaseWithDependencies({
    rawRestoration: {
      store: "app_store",
      productId: PREMIUM_PRODUCT,
      verificationData: "header.payload.signature",
      purchaseId: decoded.transactionId,
    },
    signingSecret: SIGNING_SECRET,
    nowMs: NOW,
    verifyApple: async () => decoded,
    allowSandbox: true,
    findEntitlement: async (id) => id === entitlement._id ? entitlement : null,
    findCheckout: async (id) => id === checkout._id ? checkout : null,
    persistEntitlement: async (record) => ({ item: record, idempotent: true }),
    finalizeProfessional: async ({ entitlement: restored }) => ({
      checkout: { ...checkout, status: "finalized", entitlementId: restored._id },
      professional: {
        _id: restored.professionalId,
        registrationStatus: "pending_review",
        isActive: false,
      },
      idempotent: true,
    }),
  });

  assert.equal(result.restored, true);
  assert.equal(result.entitlement._id, entitlement._id);
  assert.equal(result.professional.isActive, false);
});

test("la restauration récupère un premier achat interrompu par le compte signé, puis rejoue sans doublon", async () => {
  const checkout = persistedStoreCheckout("google_play");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const providerResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(NOW - 1_000).toISOString(),
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    etag: "interrupted-confirmation-etag",
  };
  const rawRestoration = {
    store: "google_play",
    productId: PREMIUM_PRODUCT,
    verificationData: "interrupted-purchase-token",
    purchaseId: "GPA.1234-5678-9012-34567",
  };
  let entitlement = null;
  let professional = null;
  let checkoutLookupCount = 0;
  const dependencies = {
    rawRestoration,
    signingSecret: SIGNING_SECRET,
    nowMs: NOW,
    verifyGoogle: async () => providerResponse,
    findEntitlement: async (id) => entitlement?._id === id ? entitlement : null,
    findCheckout: async (id) => checkout._id === id ? checkout : null,
    findCheckoutsByAccountReference: async (binding) => {
      checkoutLookupCount += 1;
      assert.deepEqual(binding, {
        accountReferenceHash: checkout.accountReferenceHash,
        store: "google_play",
        productId: PREMIUM_PRODUCT,
      });
      return [checkout];
    },
    persistEntitlement: async (record) => {
      if (entitlement) return { item: entitlement, idempotent: true };
      entitlement = record;
      return { item: record, idempotent: false };
    },
    finalizeProfessional: async ({ entitlement: restored }) => {
      if (!professional) {
        professional = {
          _id: restored.professionalId,
          registrationStatus: "pending_review",
          isActive: false,
        };
        return {
          checkout: { ...checkout, status: "finalized", entitlementId: restored._id },
          professional,
          idempotent: false,
        };
      }
      return {
        checkout: { ...checkout, status: "finalized", entitlementId: restored._id },
        professional,
        idempotent: true,
      };
    },
    acknowledgeGoogle: async () => assert.fail("la preuve est déjà acquittée"),
  };

  const first = await restoreStorePurchaseWithDependencies(dependencies);
  const replay = await restoreStorePurchaseWithDependencies(dependencies);

  assert.equal(first.restored, true);
  assert.equal(first.idempotent, false);
  assert.equal(first.completePurchase, true);
  assert.equal(replay.idempotent, true);
  assert.equal(checkoutLookupCount, 1);
  assert.equal(entitlement.checkoutId, checkout._id);
  assert.equal(JSON.stringify(entitlement).includes(accountToken), false);
  assert.equal(JSON.stringify(entitlement).includes(rawRestoration.verificationData), false);
});

test("la récupération sans droit rejette toute ambiguïté de checkout", async () => {
  const checkout = persistedStoreCheckout("google_play");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  await assert.rejects(() => restoreStorePurchaseWithDependencies({
    rawRestoration: {
      store: "google_play",
      productId: PREMIUM_PRODUCT,
      verificationData: "ambiguous-purchase-token",
    },
    signingSecret: SIGNING_SECRET,
    nowMs: NOW,
    verifyGoogle: async () => ({
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      startTime: new Date(NOW - 1_000).toISOString(),
      lineItems: [{
        productId: PREMIUM_PRODUCT,
        expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
        autoRenewingPlan: { autoRenewEnabled: true },
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    }),
    findEntitlement: async () => null,
    findCheckoutsByAccountReference: async () => [checkout, { ...checkout }],
  }), (error) => error instanceof InputError && error.code === "STORE_ACCOUNT_REFERENCE_AMBIGUOUS");
});

test("Google conserve le droit racine pendant un remplacement différé puis bascule au renouvellement", async () => {
  const initialCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...registration({ professionalId: "temp_1758812400101" }),
    planId: "professional",
    store: "google_play",
  }, SIGNING_SECRET, NOW), { profile: "", gallery: [] });
  const initialAccountToken = deriveStoreAccountToken(initialCheckout, SIGNING_SECRET);
  const initialToken = "google-initial-token-never-persisted";
  const initialPurchase = normalizeGooglePurchase({
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(NOW - 60_000).toISOString(),
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: initialAccountToken },
    etag: "initial-etag",
  }, {
    checkout: initialCheckout,
    accountToken: initialAccountToken,
    verificationData: initialToken,
    nowMs: NOW,
  });
  const initialEntitlement = buildEntitlementRecord(
    initialCheckout,
    initialPurchase,
    NOW,
  );

  const replacementCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...registration({ professionalId: "temp_1758812400102" }),
    planId: "premium",
    store: "google_play",
  }, SIGNING_SECRET, NOW), { profile: "", gallery: [] });
  const replacementAccountToken = deriveStoreAccountToken(
    replacementCheckout,
    SIGNING_SECRET,
  );
  const replacementToken = "google-replacement-token-never-persisted";
  const deferredResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    linkedPurchaseToken: initialToken,
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: false },
      deferredItemReplacement: { productId: PREMIUM_PRODUCT },
    }, {
      productId: PREMIUM_PRODUCT,
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: replacementAccountToken },
    etag: "deferred-etag",
  };
  const deferredPurchase = normalizeGooglePurchase(deferredResponse, {
    checkout: replacementCheckout,
    accountToken: replacementAccountToken,
    verificationData: replacementToken,
    nowMs: NOW,
  });
  assert.equal(deferredPurchase.productId, PROFESSIONAL_PRODUCT);
  assert.equal(deferredPurchase.pendingProductId, PREMIUM_PRODUCT);
  assert.equal(deferredPurchase.replacementMode, "DEFERRED");
  assert.notEqual(deferredPurchase.currentTransactionHash, initialPurchase.currentTransactionHash);
  assert.equal(deferredPurchase.linkedTransactionHash, initialPurchase.currentTransactionHash);

  const deferredEntitlement = buildGoogleLineageEntitlementRecord(
    replacementCheckout,
    deferredPurchase,
    initialEntitlement,
    NOW + 1_000,
  );
  assert.equal(deferredEntitlement._id, initialEntitlement._id);
  assert.equal(deferredEntitlement.professionalId, initialEntitlement.professionalId);
  assert.equal(deferredEntitlement.checkoutId, replacementCheckout._id);
  assert.equal(deferredEntitlement.planId, "professional");
  assert.equal(deferredEntitlement.pendingPlanId, "premium");
  assert.equal(reconcileEntitlement(initialEntitlement, deferredEntitlement).action, "update");

  const renewedPurchase = normalizeGooglePurchase({
    ...deferredResponse,
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(NOW - 60_000).toISOString(),
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW - 1_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: false },
    }, {
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.2222-2222-2222-22222",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    etag: "effective-etag",
  }, {
    checkout: replacementCheckout,
    accountToken: replacementAccountToken,
    verificationData: replacementToken,
    nowMs: NOW,
  });
  const renewedEntitlement = buildGoogleLineageEntitlementRecord(
    replacementCheckout,
    renewedPurchase,
    deferredEntitlement,
    NOW + 2_000,
  );
  assert.equal(renewedEntitlement._id, initialEntitlement._id);
  assert.equal(renewedEntitlement.planId, "premium");
  assert.equal(renewedEntitlement.pendingPlanId, "");
  assert.equal(renewedEntitlement.pendingProductId, "");
  assert.equal(renewedEntitlement.pendingEffectiveAt, "");
  assert.equal(reconcileEntitlement(deferredEntitlement, renewedEntitlement).action, "update");

  const serialized = JSON.stringify({ deferredEntitlement, renewedEntitlement });
  assert.equal(serialized.includes(initialToken), false);
  assert.equal(serialized.includes(replacementToken), false);
  expectInputError(() => normalizeGooglePurchase({
    ...deferredResponse,
    linkedPurchaseToken: undefined,
  }, {
    checkout: replacementCheckout,
    accountToken: replacementAccountToken,
    verificationData: replacementToken,
    nowMs: NOW,
  }), "STORE_PURCHASE_LINEAGE_INVALID");
  expectInputError(() => buildGoogleLineageEntitlementRecord(
    replacementCheckout,
    deferredPurchase,
    { ...initialEntitlement, currentTransactionHash: "f".repeat(64) },
    NOW + 1_000,
  ), "STORE_PURCHASE_LINEAGE_INVALID");

  await assert.rejects(() => confirmStorePurchaseWithDependencies({
    checkout: replacementCheckout,
    rawConfirmation: {
      checkoutId: replacementCheckout._id,
      store: "google_play",
      productId: PREMIUM_PRODUCT,
      verificationData: replacementToken,
    },
    signingSecret: SIGNING_SECRET,
    nowMs: NOW,
    verifyGoogle: async () => deferredResponse,
    findEntitlementsByCurrentTransactionHash: async ({ currentTransactionHash }) => (
      currentTransactionHash === deferredPurchase.linkedTransactionHash
        ? [initialEntitlement, { ...initialEntitlement }]
        : []
    ),
  }), (error) => error instanceof InputError
    && error.code === "STORE_PURCHASE_LINEAGE_AMBIGUOUS");
});

test("Google impose la direction commerciale et le mode exact de chaque remplacement", () => {
  const professionalCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...registration({ professionalId: "temp_1758812400201" }),
    planId: "professional",
    store: "google_play",
  }, SIGNING_SECRET, NOW), { profile: "", gallery: [] });
  const professionalAccountToken = deriveStoreAccountToken(
    professionalCheckout,
    SIGNING_SECRET,
  );
  const immediateUpgrade = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    linkedPurchaseToken: "premium-predecessor-token",
    startTime: new Date(NOW - 60_000).toISOString(),
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.3333-3333-3333-33333",
      autoRenewingPlan: { autoRenewEnabled: true },
      itemReplacement: {
        productId: PREMIUM_PRODUCT,
        replacementMode: "WITH_TIME_PRORATION",
      },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: professionalAccountToken },
  };
  const upgraded = normalizeGooglePurchase(immediateUpgrade, {
    checkout: professionalCheckout,
    accountToken: professionalAccountToken,
    verificationData: "professional-upgrade-token",
    nowMs: NOW,
  });
  assert.equal(upgraded.productId, PROFESSIONAL_PRODUCT);
  assert.equal(upgraded.replacesProductId, PREMIUM_PRODUCT);
  assert.equal(upgraded.replacementMode, "WITH_TIME_PRORATION");

  expectInputError(() => normalizeGooglePurchase({
    ...immediateUpgrade,
    lineItems: [{
      ...immediateUpgrade.lineItems[0],
      itemReplacement: {
        productId: PREMIUM_PRODUCT,
        replacementMode: "WITHOUT_PRORATION",
      },
    }],
  }, {
    checkout: professionalCheckout,
    accountToken: professionalAccountToken,
    verificationData: "without-proration-token",
    nowMs: NOW,
  }), "STORE_REPLACEMENT_POLICY_MISMATCH");

  const premiumCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...registration({ professionalId: "temp_1758812400202" }),
    planId: "premium",
    store: "google_play",
  }, SIGNING_SECRET, NOW), { profile: "", gallery: [] });
  const premiumAccountToken = deriveStoreAccountToken(premiumCheckout, SIGNING_SECRET);
  expectInputError(() => normalizeGooglePurchase({
    ...immediateUpgrade,
    linkedPurchaseToken: "professional-predecessor-token",
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.4444-4444-4444-44444",
      autoRenewingPlan: { autoRenewEnabled: true },
      itemReplacement: {
        productId: PROFESSIONAL_PRODUCT,
        replacementMode: "WITH_TIME_PRORATION",
      },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: premiumAccountToken },
  }, {
    checkout: premiumCheckout,
    accountToken: premiumAccountToken,
    verificationData: "wrong-direction-immediate-token",
    nowMs: NOW,
  }), "STORE_REPLACEMENT_POLICY_MISMATCH");

  expectInputError(() => normalizeGooglePurchase({
    ...immediateUpgrade,
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.5555-5555-5555-55555",
      autoRenewingPlan: { autoRenewEnabled: false },
      deferredItemReplacement: { productId: PROFESSIONAL_PRODUCT },
    }, {
      productId: PROFESSIONAL_PRODUCT,
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: professionalAccountToken },
  }, {
    checkout: professionalCheckout,
    accountToken: professionalAccountToken,
    verificationData: "wrong-direction-deferred-token",
    nowMs: NOW,
  }), "STORE_REPLACEMENT_POLICY_MISMATCH");

  expectInputError(() => normalizeGooglePurchase({
    ...immediateUpgrade,
    lineItems: [{
      ...immediateUpgrade.lineItems[0],
      itemReplacement: {
        productId: PREMIUM_PRODUCT,
        replacementMode: "DEFERRED",
      },
    }],
  }, {
    checkout: professionalCheckout,
    accountToken: professionalAccountToken,
    verificationData: "malformed-deferred-token",
    nowMs: NOW,
  }), "STORE_REPLACEMENT_POLICY_MISMATCH");

  const initialPremiumToken = "policy-initial-premium-token";
  const initialPremiumPurchase = normalizeGooglePurchase({
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(NOW - 60_000).toISOString(),
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.6666-6666-6666-66666",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: premiumAccountToken },
  }, {
    checkout: premiumCheckout,
    accountToken: premiumAccountToken,
    verificationData: initialPremiumToken,
    nowMs: NOW,
  });
  const initialPremiumEntitlement = buildEntitlementRecord(
    premiumCheckout,
    initialPremiumPurchase,
    NOW,
  );
  const unprovenUpgrade = normalizeGooglePurchase({
    ...immediateUpgrade,
    linkedPurchaseToken: initialPremiumToken,
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.7777-7777-7777-77777",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
  }, {
    checkout: professionalCheckout,
    accountToken: professionalAccountToken,
    verificationData: "unproven-upgrade-token",
    nowMs: NOW,
  });
  expectInputError(() => buildGoogleLineageEntitlementRecord(
    professionalCheckout,
    unprovenUpgrade,
    initialPremiumEntitlement,
    NOW + 1_000,
  ), "STORE_REPLACEMENT_POLICY_MISMATCH");

  const initialProfessionalToken = "policy-initial-professional-token";
  const initialProfessionalPurchase = normalizeGooglePurchase({
    ...immediateUpgrade,
    linkedPurchaseToken: undefined,
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    lineItems: [{
      productId: PROFESSIONAL_PRODUCT,
      expiryTime: new Date(NOW + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.8888-8888-8888-88888",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
  }, {
    checkout: professionalCheckout,
    accountToken: professionalAccountToken,
    verificationData: initialProfessionalToken,
    nowMs: NOW,
  });
  const initialProfessionalEntitlement = buildEntitlementRecord(
    professionalCheckout,
    initialProfessionalPurchase,
    NOW,
  );
  const unprovenDowngrade = normalizeGooglePurchase({
    ...immediateUpgrade,
    linkedPurchaseToken: initialProfessionalToken,
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.9999-9999-9999-99999",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: premiumAccountToken },
  }, {
    checkout: premiumCheckout,
    accountToken: premiumAccountToken,
    verificationData: "unproven-downgrade-token",
    nowMs: NOW,
  });
  expectInputError(() => buildGoogleLineageEntitlementRecord(
    premiumCheckout,
    unprovenDowngrade,
    initialProfessionalEntitlement,
    NOW + 1_000,
  ), "STORE_REPLACEMENT_POLICY_MISMATCH");
});

test("Google autorise un réabonnement même produit lié seulement après expiration du droit", () => {
  const originalCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...registration({ professionalId: "temp_1758812400203" }),
    planId: "premium",
    store: "google_play",
  }, SIGNING_SECRET, NOW), { profile: "", gallery: [] });
  const originalAccountToken = deriveStoreAccountToken(originalCheckout, SIGNING_SECRET);
  const originalToken = "expired-resubscribe-predecessor-token";
  const originalPurchase = normalizeGooglePurchase({
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(NOW - 365 * 24 * 60 * 60 * 1000).toISOString(),
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1212-1212-1212-12121",
      autoRenewingPlan: { autoRenewEnabled: false },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: originalAccountToken },
  }, {
    checkout: originalCheckout,
    accountToken: originalAccountToken,
    verificationData: originalToken,
    nowMs: NOW,
  });
  const activeEntitlement = buildEntitlementRecord(
    originalCheckout,
    originalPurchase,
    NOW,
  );

  const resubscribeCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...registration({ professionalId: "temp_1758812400204" }),
    planId: "premium",
    store: "google_play",
  }, SIGNING_SECRET, NOW), { profile: "", gallery: [] });
  assert.notEqual(resubscribeCheckout._id, originalCheckout._id);
  const resubscribeAccountToken = deriveStoreAccountToken(
    resubscribeCheckout,
    SIGNING_SECRET,
  );
  const resubscribeToken = "same-product-resubscribe-current-token";
  const response = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    linkedPurchaseToken: originalToken,
    startTime: new Date(NOW + 1_000).toISOString(),
    lineItems: [{
      productId: PREMIUM_PRODUCT,
      expiryTime: new Date(NOW + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.1313-1313-1313-13131",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: resubscribeAccountToken },
  };
  const resubscribePurchase = normalizeGooglePurchase(response, {
    checkout: resubscribeCheckout,
    accountToken: resubscribeAccountToken,
    verificationData: resubscribeToken,
    nowMs: NOW,
  });

  expectInputError(() => buildGoogleLineageEntitlementRecord(
    resubscribeCheckout,
    resubscribePurchase,
    activeEntitlement,
    NOW + 2_000,
  ), "STORE_REPLACEMENT_POLICY_MISMATCH");

  const expiredEntitlement = {
    ...activeEntitlement,
    status: "active",
    expiresAt: new Date(NOW - 1).toISOString(),
  };
  const renewed = buildGoogleLineageEntitlementRecord(
    resubscribeCheckout,
    resubscribePurchase,
    expiredEntitlement,
    NOW + 2_000,
  );
  assert.equal(renewed._id, activeEntitlement._id);
  assert.equal(renewed.professionalId, activeEntitlement.professionalId);
  assert.equal(renewed.checkoutId, resubscribeCheckout._id);
  assert.equal(renewed.planId, "premium");
  assert.equal(renewed.currentTransactionHash, resubscribePurchase.currentTransactionHash);
  assert.equal(renewed.pendingPlanId, "");
  assert.equal(JSON.stringify(renewed).includes(originalToken), false);
  assert.equal(JSON.stringify(renewed).includes(resubscribeToken), false);

  expectInputError(() => normalizeGooglePurchase({
    ...response,
    externalAccountIdentifiers: { obfuscatedExternalAccountId: originalAccountToken },
  }, {
    checkout: resubscribeCheckout,
    accountToken: resubscribeAccountToken,
    verificationData: "wrong-account-resubscribe-token",
    nowMs: NOW,
  }), "STORE_ACCOUNT_MISMATCH");
});

test("le sandbox est refusé par défaut et exige une politique explicite", async () => {
  const checkout = persistedStoreCheckout("app_store");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const decoded = {
    bundleId: APP_BUNDLE_ID,
    productId: PREMIUM_PRODUCT,
    appAccountToken: accountToken,
    environment: "Sandbox",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: NOW - 1_000,
    expiresDate: NOW + 365 * 24 * 60 * 60 * 1000,
    type: "Auto-Renewable Subscription",
  };
  await assert.rejects(() => confirmStorePurchaseWithDependencies({
    checkout,
    rawConfirmation: {
      checkoutId: checkout._id,
      store: "app_store",
      productId: PREMIUM_PRODUCT,
      verificationData: "sandbox.header.signature",
    },
    signingSecret: SIGNING_SECRET,
    nowMs: NOW,
    verifyApple: async () => decoded,
  }), (error) => error instanceof InputError && error.code === "STORE_ENVIRONMENT_MISMATCH");
});

test("un changement de produit vérifié met à jour le forfait sans changer l'identité du droit", () => {
  const checkout = persistedStoreCheckout("app_store");
  const accountToken = deriveStoreAccountToken(checkout, SIGNING_SECRET);
  const base = {
    bundleId: APP_BUNDLE_ID,
    productId: PREMIUM_PRODUCT,
    appAccountToken: accountToken,
    environment: "Production",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: NOW - 1_000,
    expiresDate: NOW + 365 * 24 * 60 * 60 * 1000,
    type: "Auto-Renewable Subscription",
  };
  const initialPurchase = normalizeApplePurchase(base, {
    checkout,
    accountToken,
    verificationData: "initial.header.signature",
    nowMs: NOW,
  });
  const entitlement = buildEntitlementRecord(checkout, initialPurchase, NOW);
  const upgradedPurchase = {
    ...initialPurchase,
    productId: "ca.indexcanada.app.professional.annual",
    lastTransactionHash: "a".repeat(64),
    sourceEventHash: "b".repeat(64),
    providerEventAt: new Date(NOW + 1_000).toISOString(),
  };
  const upgraded = buildLifecycleEntitlementRecord(
    checkout,
    upgradedPurchase,
    entitlement,
    NOW + 1_000,
  );

  assert.equal(upgraded._id, entitlement._id);
  assert.equal(upgraded.planId, "professional");
  assert.equal(upgraded.productId, "ca.indexcanada.app.professional.annual");
  assert.equal(reconcileEntitlement(entitlement, upgraded).action, "update");

  const downgraded = buildLifecycleEntitlementRecord(checkout, {
    ...upgradedPurchase,
    productId: PREMIUM_PRODUCT,
    lastTransactionHash: "c".repeat(64),
    sourceEventHash: "d".repeat(64),
    providerEventAt: new Date(NOW + 2_000).toISOString(),
  }, upgraded, NOW + 2_000);
  assert.equal(downgraded.planId, "premium");
  assert.equal(reconcileEntitlement(upgraded, downgraded).action, "update");
});

test("la projection choisit toujours l'événement fournisseur maximal malgré un replay inverse", () => {
  const base = {
    _id: `ent_${"a".repeat(32)}`,
    professionalId: "idx_professional",
    checkoutId: `chk_${"b".repeat(32)}`,
    planId: "premium",
    provider: "apple",
    productId: PREMIUM_PRODUCT,
    environment: "production",
    startsAt: new Date(NOW - 60_000).toISOString(),
    expiresAt: new Date(NOW + 60_000).toISOString(),
    originalTransactionHash: "c".repeat(64),
    lastTransactionHash: "d".repeat(64),
    sourceEventHash: "e".repeat(64),
    lastProviderEventAt: new Date(NOW).toISOString(),
  };
  const obsoleteActive = { ...base, status: "active" };
  const laterRevocation = {
    ...base,
    status: "revoked",
    sourceEventHash: "f".repeat(64),
    lastProviderEventAt: new Date(NOW + 1_000).toISOString(),
  };

  assert.equal(
    selectLatestStoreEntitlement([laterRevocation, obsoleteActive]),
    laterRevocation,
  );
  assert.equal(
    selectLatestStoreEntitlement([obsoleteActive, laterRevocation]),
    laterRevocation,
  );
});
