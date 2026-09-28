import { createHmac } from "crypto";

import {
  InputError,
  PLAN_CATALOG,
  buildCheckoutId,
  buildProfessionalId,
  createCheckoutDraft,
  getPlan,
  sha256,
} from "./security-core.js";

export const APP_BUNDLE_ID = "ca.indexcanada.app";
export const STORE_BILLING_PERIOD = "P1Y";

export const STORE_PROVIDERS = Object.freeze({
  app_store: "apple",
  google_play: "google",
});

const CHECKOUT_ID_PATTERN = /^chk_[a-f0-9]{32}$/u;
const HASH_PATTERN = /^[a-f0-9]{64}$/u;
const STORE_SIGNING_KEY_ID_PATTERN = /^ssk_[a-f0-9]{16}$/u;
const MAX_PREVIOUS_STORE_SIGNING_KEYS = 8;
const UUID_V4_PATTERN = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/u;
const FORBIDDEN_PERSISTED_FIELDS = Object.freeze([
  "appAccountToken",
  "obfuscatedExternalAccountId",
  "purchaseToken",
  "signedTransactionInfo",
  "signingKeyring",
  "signingSecret",
  "verificationData",
]);
const ENTITLEMENT_LINEAGE = Symbol("store-entitlement-lineage");

function assertRecord(value, code = "INVALID_STORE_PURCHASE") {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError(code);
  }
  return value;
}

function cleanOpaqueString(value, {
  code = "INVALID_STORE_PURCHASE",
  min = 1,
  max = 200,
} = {}) {
  if (typeof value !== "string" || value.length < min || value.length > max || value.trim() !== value) {
    throw new InputError(code);
  }
  return value;
}

function normalizeStore(value) {
  if (typeof value !== "string" || !Object.hasOwn(STORE_PROVIDERS, value)) {
    throw new InputError("INVALID_STORE");
  }
  return value;
}

function productFor(plan, store) {
  const productId = plan?.storeProducts?.[store];
  if (typeof productId !== "string" || !productId) {
    throw new InputError("STORE_PRODUCT_UNAVAILABLE");
  }
  return productId;
}

function storeForProvider(value) {
  if (Object.hasOwn(STORE_PROVIDERS, value)) return value;
  const match = Object.entries(STORE_PROVIDERS)
    .find(([, provider]) => provider === value);
  if (!match) throw new InputError("INVALID_STORE");
  return match[0];
}

export function getStorePlanForProduct(storeOrProvider, productId) {
  const store = storeForProvider(storeOrProvider);
  const matches = Object.values(PLAN_CATALOG).filter(
    (plan) => plan.requiresPayment && plan.storeProducts?.[store] === productId,
  );
  if (matches.length !== 1) throw new InputError("STORE_PRODUCT_MISMATCH");
  return matches[0];
}

function assertSigningSecret(secret) {
  if (typeof secret !== "string" || Buffer.byteLength(secret, "utf8") < 32) {
    throw new InputError("INVALID_SIGNING_SECRET");
  }
  return secret;
}

function signingKeyId(secret) {
  return `ssk_${sha256(`store-signing-key:${secret}`).slice(0, 16)}`;
}

function signingKey(secret) {
  const validatedSecret = assertSigningSecret(secret);
  const key = {
    keyId: signingKeyId(validatedSecret),
  };
  Object.defineProperty(key, "secret", {
    value: validatedSecret,
    enumerable: false,
    writable: false,
    configurable: false,
  });
  return Object.freeze(key);
}

export function createStoreSigningKeyring(currentSecret, previousSecrets = []) {
  if (
    !Array.isArray(previousSecrets)
    || previousSecrets.length > MAX_PREVIOUS_STORE_SIGNING_KEYS
  ) {
    throw new InputError("INVALID_SIGNING_KEYRING");
  }
  let rawKeys;
  try {
    rawKeys = [currentSecret, ...previousSecrets].map(signingKey);
  } catch (error) {
    if (error instanceof InputError) throw new InputError("INVALID_SIGNING_KEYRING");
    throw error;
  }
  const keysById = new Map();
  for (const key of rawKeys) {
    const existing = keysById.get(key.keyId);
    if (existing && existing.secret !== key.secret) {
      throw new InputError("INVALID_SIGNING_KEYRING");
    }
    if (!existing) keysById.set(key.keyId, key);
  }
  const currentKey = rawKeys[0];
  return Object.freeze({
    currentKeyId: currentKey.keyId,
    keys: Object.freeze([...keysById.values()]),
  });
}

function normalizeStoreSigningKeyring(value) {
  if (typeof value === "string") return createStoreSigningKeyring(value);
  if (
    !value
    || typeof value !== "object"
    || Array.isArray(value)
    || !STORE_SIGNING_KEY_ID_PATTERN.test(value.currentKeyId ?? "")
    || !Array.isArray(value.keys)
    || value.keys.length === 0
    || value.keys.length > MAX_PREVIOUS_STORE_SIGNING_KEYS + 1
  ) {
    throw new InputError("INVALID_SIGNING_KEYRING");
  }
  const current = value.keys.find((key) => key?.keyId === value.currentKeyId);
  if (!current) throw new InputError("INVALID_SIGNING_KEYRING");
  const previousSecrets = value.keys
    .filter((key) => key !== current)
    .map((key) => key?.secret);
  const normalized = createStoreSigningKeyring(current.secret, previousSecrets);
  if (
    normalized.currentKeyId !== value.currentKeyId
    || normalized.keys.length !== value.keys.length
    || normalized.keys.some((key) => !value.keys.some(
      (candidate) => candidate?.keyId === key.keyId && candidate?.secret === key.secret,
    ))
  ) {
    throw new InputError("INVALID_SIGNING_KEYRING");
  }
  return normalized;
}

function uuidV4FromDigest(digest) {
  const bytes = Buffer.from(digest.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function storeCheckoutId(baseCheckoutId, store) {
  return buildCheckoutId(`store:${store}:${baseCheckoutId}`);
}

function deriveStoreAccountTokenWithKey(checkoutId, key) {
  return uuidV4FromDigest(
    createHmac("sha256", key.secret).update(`store-account:${checkoutId}`, "utf8").digest(),
  );
}

export function deriveStoreAccountToken(checkoutOrId, signingKeyring) {
  const checkoutId = typeof checkoutOrId === "string" ? checkoutOrId : checkoutOrId?._id;
  if (typeof checkoutId !== "string" || !CHECKOUT_ID_PATTERN.test(checkoutId)) {
    throw new InputError("INVALID_STORE_CHECKOUT");
  }
  const keyring = normalizeStoreSigningKeyring(signingKeyring);
  const storedHash = typeof checkoutOrId === "object" ? checkoutOrId.accountReferenceHash : undefined;
  const storedKeyId = typeof checkoutOrId === "object"
    ? checkoutOrId.accountSigningKeyId
    : undefined;
  let key;
  if (storedKeyId !== undefined) {
    if (!STORE_SIGNING_KEY_ID_PATTERN.test(storedKeyId)) {
      throw new InputError("INVALID_STORE_CHECKOUT");
    }
    key = keyring.keys.find((candidate) => candidate.keyId === storedKeyId);
    if (!key) throw new InputError("STORE_SIGNING_KEY_UNAVAILABLE");
  } else if (storedHash !== undefined) {
    if (!HASH_PATTERN.test(storedHash)) throw new InputError("INVALID_STORE_CHECKOUT");
    const matches = keyring.keys.filter(
      (candidate) => sha256(deriveStoreAccountTokenWithKey(checkoutId, candidate)) === storedHash,
    );
    if (matches.length === 0) throw new InputError("STORE_SIGNING_KEY_UNAVAILABLE");
    if (matches.length > 1) throw new InputError("INVALID_SIGNING_KEYRING");
    [key] = matches;
  } else {
    key = keyring.keys.find((candidate) => candidate.keyId === keyring.currentKeyId);
  }
  if (!key) throw new InputError("INVALID_SIGNING_KEYRING");
  const token = deriveStoreAccountTokenWithKey(checkoutId, key);
  if (storedHash !== undefined && storedHash !== sha256(token)) {
    throw new InputError("STORE_ACCOUNT_MISMATCH");
  }
  return token;
}

export function createStoreCheckoutDraft(rawBody, signingKeyring, nowMs = Date.now()) {
  const store = normalizeStore(rawBody?.store);
  const baseDraft = createCheckoutDraft(rawBody, nowMs);
  const plan = getPlan(baseDraft.planId);
  if (!plan.requiresPayment) throw new InputError("STORE_PAYMENT_NOT_REQUIRED");
  const productId = productFor(plan, store);
  const checkoutId = storeCheckoutId(baseDraft._id, store);
  const keyring = normalizeStoreSigningKeyring(signingKeyring);
  const accountToken = deriveStoreAccountToken(checkoutId, keyring);
  const draft = {
    ...baseDraft,
    _id: checkoutId,
    paymentProvider: STORE_PROVIDERS[store],
    store,
    storeProductId: productId,
    accountSigningKeyId: keyring.currentKeyId,
    accountReferenceHash: sha256(accountToken),
    storeEnvironment: "",
    storeTransactionHash: "",
    entitlementId: "",
    entitlementExpiresAt: "",
    storeAcknowledged: false,
  };
  validateStoreCheckout(draft);
  return Object.freeze(draft);
}

export function validateStoreCheckout(value) {
  const checkout = assertRecord(value, "INVALID_STORE_CHECKOUT");
  const store = normalizeStore(checkout.store);
  const plan = getPlan(checkout.planId);
  if (!plan.requiresPayment) throw new InputError("INVALID_STORE_CHECKOUT");
  const baseCheckoutId = buildCheckoutId(
    `${plan.id}:${checkout.sourceRegistrationId}:${checkout.fingerprint}`,
  );
  if (
    !CHECKOUT_ID_PATTERN.test(checkout._id ?? "")
    || checkout._id !== storeCheckoutId(baseCheckoutId, store)
    || checkout.paymentProvider !== STORE_PROVIDERS[store]
    || checkout.storeProductId !== productFor(plan, store)
    || (
      checkout.accountSigningKeyId !== undefined
      && !STORE_SIGNING_KEY_ID_PATTERN.test(checkout.accountSigningKeyId)
    )
    || !HASH_PATTERN.test(checkout.accountReferenceHash ?? "")
    || FORBIDDEN_PERSISTED_FIELDS.some((field) => Object.hasOwn(checkout, field))
  ) {
    throw new InputError("INVALID_STORE_CHECKOUT");
  }
  return plan;
}

function parseStoreProof(rawBody, code = "INVALID_STORE_PURCHASE") {
  const body = assertRecord(rawBody);
  const store = normalizeStore(body.store);
  const productId = cleanOpaqueString(
    body.productId ?? body.product_id,
    { code, max: 160 },
  );
  const verificationData = cleanOpaqueString(
    body.verificationData ?? body.verification_data,
    { code, min: 8, max: 200_000 },
  );
  const rawPurchaseId = body.purchaseId ?? body.purchase_id;
  const purchaseId = rawPurchaseId === undefined || rawPurchaseId === null || rawPurchaseId === ""
    ? ""
    : cleanOpaqueString(rawPurchaseId, { code, max: 200 });
  return Object.freeze({ store, productId, verificationData, purchaseId });
}

export function validateStoreConfirmation(rawBody, checkout) {
  const body = assertRecord(rawBody);
  validateStoreCheckout(checkout);
  const checkoutId = cleanOpaqueString(
    body.checkoutId ?? body.checkout_id,
    { code: "INVALID_STORE_PURCHASE", min: 36, max: 36 },
  );
  const proof = parseStoreProof(body);
  if (
    checkoutId !== checkout._id
    || proof.store !== checkout.store
    || proof.productId !== checkout.storeProductId
  ) {
    throw new InputError("STORE_PURCHASE_MISMATCH");
  }
  return Object.freeze({ checkoutId, ...proof });
}

export function validateStoreRestoration(rawBody) {
  const body = assertRecord(rawBody, "INVALID_STORE_RESTORATION");
  if ([
    "checkoutId",
    "checkout_id",
    "accountToken",
    "account_token",
    "appAccountToken",
    "obfuscatedExternalAccountId",
  ].some((field) => Object.hasOwn(body, field))) {
    throw new InputError("INVALID_STORE_RESTORATION");
  }
  return parseStoreProof(body, "INVALID_STORE_RESTORATION");
}

function timestampMs(value, code) {
  const milliseconds = typeof value === "number" ? value : Date.parse(value);
  if (!Number.isFinite(milliseconds)) throw new InputError(code);
  return milliseconds;
}

function normalizedIso(value, code) {
  return new Date(timestampMs(value, code)).toISOString();
}

function assertFutureExpiry(value, nowMs) {
  const expiresAtMs = timestampMs(value, "STORE_PURCHASE_EXPIRED");
  if (expiresAtMs <= nowMs) throw new InputError("STORE_PURCHASE_EXPIRED");
  return new Date(expiresAtMs).toISOString();
}

function assertPurchaseIdHint(expected, actual) {
  if (expected && expected !== actual) throw new InputError("STORE_PURCHASE_MISMATCH");
}

export function identifyApplePurchase(decodedValue, {
  productId,
  verificationData,
  purchaseId = "",
  nowMs = Date.now(),
} = {}) {
  const decoded = assertRecord(decodedValue, "UNTRUSTED_STORE_PURCHASE");
  const expectedProductId = cleanOpaqueString(productId, {
    code: "STORE_PRODUCT_MISMATCH",
    max: 160,
  });
  if (decoded.bundleId !== APP_BUNDLE_ID) throw new InputError("STORE_APP_MISMATCH");
  if (decoded.productId !== expectedProductId) throw new InputError("STORE_PRODUCT_MISMATCH");
  const accountToken = cleanOpaqueString(decoded.appAccountToken, {
    code: "STORE_ACCOUNT_MISMATCH",
    min: 36,
    max: 36,
  });
  if (!UUID_V4_PATTERN.test(accountToken)) throw new InputError("STORE_ACCOUNT_MISMATCH");
  if (decoded.revocationDate !== undefined && decoded.revocationDate !== null) {
    throw new InputError("STORE_PURCHASE_REVOKED");
  }
  if (decoded.isUpgraded === true) throw new InputError("STORE_PURCHASE_REPLACED");
  if (decoded.type !== "Auto-Renewable Subscription") {
    throw new InputError("STORE_PRODUCT_MISMATCH");
  }
  const environment = decoded.environment === "Production" ? "production"
    : decoded.environment === "Sandbox" ? "sandbox"
      : "";
  if (!environment) throw new InputError("STORE_ENVIRONMENT_MISMATCH");
  const transactionId = cleanOpaqueString(decoded.transactionId, {
    code: "UNTRUSTED_STORE_PURCHASE",
    max: 200,
  });
  const originalTransactionId = cleanOpaqueString(decoded.originalTransactionId, {
    code: "UNTRUSTED_STORE_PURCHASE",
    max: 200,
  });
  assertPurchaseIdHint(purchaseId, transactionId);
  const startedAtMs = timestampMs(decoded.purchaseDate, "UNTRUSTED_STORE_PURCHASE");
  if (startedAtMs > nowMs + 5 * 60_000) throw new InputError("UNTRUSTED_STORE_PURCHASE");
  const expiresAt = assertFutureExpiry(decoded.expiresDate, nowMs);
  const rawVerification = cleanOpaqueString(verificationData, {
    code: "UNTRUSTED_STORE_PURCHASE",
    min: 8,
    max: 200_000,
  });
  const purchase = Object.freeze({
    provider: "apple",
    productId: expectedProductId,
    environment,
    status: "active",
    startsAt: new Date(startedAtMs).toISOString(),
    expiresAt,
    originalTransactionHash: sha256(`apple:original:${originalTransactionId}`),
    lastTransactionHash: sha256(`apple:transaction:${transactionId}`),
    sourceEventHash: sha256(`apple:jws:${rawVerification}`),
    providerEventAt: new Date(
      Number.isFinite(decoded.signedDate) ? decoded.signedDate : nowMs,
    ).toISOString(),
    needsAcknowledgement: false,
  });
  return Object.freeze({ accountToken, purchase });
}

export function normalizeApplePurchase(decodedValue, {
  checkout,
  accountToken,
  verificationData,
  purchaseId = "",
  nowMs = Date.now(),
} = {}) {
  validateStoreCheckout(checkout);
  if (checkout.store !== "app_store") throw new InputError("STORE_PURCHASE_MISMATCH");
  const identified = identifyApplePurchase(decodedValue, {
    productId: checkout.storeProductId,
    verificationData,
    purchaseId,
    nowMs,
  });
  if (!UUID_V4_PATTERN.test(accountToken ?? "") || identified.accountToken !== accountToken) {
    throw new InputError("STORE_ACCOUNT_MISMATCH");
  }
  return identified.purchase;
}

const GOOGLE_STATE_STATUS = Object.freeze({
  SUBSCRIPTION_STATE_ACTIVE: "active",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
  // Google documents CANCELED as access that remains valid until expiry.
  SUBSCRIPTION_STATE_CANCELED: "active",
});

function optionalGooglePurchaseToken(value) {
  if (value === undefined || value === null || value === "") return "";
  return cleanOpaqueString(value, {
    code: "UNTRUSTED_STORE_PURCHASE",
    min: 8,
    max: 20_000,
  });
}

function googlePurchaseTokenHash(value) {
  const token = cleanOpaqueString(value, {
    code: "UNTRUSTED_STORE_PURCHASE",
    min: 8,
    max: 20_000,
  });
  return sha256(`google:purchase-token:${token}`);
}

function googleLineItem(value) {
  const item = assertRecord(value, "UNTRUSTED_STORE_PURCHASE");
  const productId = cleanOpaqueString(item.productId, {
    code: "STORE_PRODUCT_MISMATCH",
    max: 160,
  });
  getStorePlanForProduct("google_play", productId);
  if (
    item.autoRenewingPlan !== undefined
    && item.autoRenewingPlan !== null
    && typeof item.autoRenewingPlan !== "object"
  ) {
    throw new InputError("STORE_PRODUCT_MISMATCH");
  }
  return item;
}

/**
 * Google expose deux lineItems pendant un remplacement différé : le forfait
 * encore actif possède une échéance et pointe vers le forfait planifié, qui
 * n'a pas encore d'échéance. Après la bascule, le forfait cible possède
 * l'échéance future et l'ancien peut rester brièvement dans la réponse.
 */
export function selectGoogleSubscriptionLineItem(responseValue, {
  productId,
  nowMs = Date.now(),
  allowExpired = false,
  expectedRole = "requested",
} = {}) {
  const response = assertRecord(responseValue, "UNTRUSTED_STORE_PURCHASE");
  const expectedProductId = cleanOpaqueString(productId, {
    code: "STORE_PRODUCT_MISMATCH",
    max: 160,
  });
  getStorePlanForProduct("google_play", expectedProductId);
  if (!["requested", "effective"].includes(expectedRole)) {
    throw new InputError("STORE_PRODUCT_MISMATCH");
  }
  if (
    !Array.isArray(response.lineItems)
    || response.lineItems.length < 1
    || response.lineItems.length > 2
  ) {
    throw new InputError("STORE_PRODUCT_MISMATCH");
  }
  const items = response.lineItems.map(googleLineItem);
  const withoutExpiry = items.filter(
    (item) => item.expiryTime === undefined || item.expiryTime === null || item.expiryTime === "",
  );
  let effectiveItem;
  let pendingItem = null;
  let replacementMode = "";

  if (withoutExpiry.length === 1 && items.length === 2) {
    [pendingItem] = withoutExpiry;
    [effectiveItem] = items.filter((item) => item !== pendingItem);
    const replacement = assertRecord(
      effectiveItem.deferredItemReplacement,
      "STORE_PRODUCT_MISMATCH",
    );
    if (
      (expectedRole === "requested" && pendingItem.productId !== expectedProductId)
      || (expectedRole === "effective" && effectiveItem.productId !== expectedProductId)
      || effectiveItem.productId === pendingItem.productId
      || replacement.productId !== pendingItem.productId
      || !effectiveItem.autoRenewingPlan
      || effectiveItem.autoRenewingPlan.autoRenewEnabled !== false
      || (
        pendingItem.autoRenewingPlan
        && pendingItem.autoRenewingPlan.autoRenewEnabled !== true
      )
      || pendingItem.latestSuccessfulOrderId !== undefined
      || effectiveItem.itemReplacement !== undefined
    ) {
      throw new InputError("STORE_PRODUCT_MISMATCH");
    }
    const effectivePlan = getStorePlanForProduct("google_play", effectiveItem.productId);
    const pendingPlan = getStorePlanForProduct("google_play", pendingItem.productId);
    if (effectivePlan.id !== "professional" || pendingPlan.id !== "premium") {
      throw new InputError("STORE_REPLACEMENT_POLICY_MISMATCH");
    }
    replacementMode = "DEFERRED";
  } else if (withoutExpiry.length === 0) {
    const matching = items.filter((item) => item.productId === expectedProductId);
    if (matching.length !== 1) throw new InputError("STORE_PRODUCT_MISMATCH");
    [effectiveItem] = matching;
    if (!effectiveItem.autoRenewingPlan) throw new InputError("STORE_PRODUCT_MISMATCH");
    if (items.length === 2) {
      const [historicalItem] = items.filter((item) => item !== effectiveItem);
      const effectiveExpiryMs = timestampMs(
        effectiveItem.expiryTime,
        "UNTRUSTED_STORE_PURCHASE",
      );
      const historicalExpiryMs = timestampMs(
        historicalItem.expiryTime,
        "UNTRUSTED_STORE_PURCHASE",
      );
      if (
        (!allowExpired && effectiveExpiryMs <= nowMs)
        || historicalExpiryMs > nowMs
        || historicalExpiryMs > effectiveExpiryMs
        || historicalItem.autoRenewingPlan?.autoRenewEnabled === true
      ) {
        throw new InputError("STORE_PRODUCT_MISMATCH");
      }
    }
  } else {
    throw new InputError("STORE_PRODUCT_MISMATCH");
  }

  const expiresAtMs = timestampMs(effectiveItem.expiryTime, "UNTRUSTED_STORE_PURCHASE");
  if (!allowExpired && expiresAtMs <= nowMs) throw new InputError("STORE_PURCHASE_EXPIRED");
  const replacementInfo = effectiveItem.itemReplacement;
  let replacesProductId = "";
  if (replacementInfo !== undefined && replacementInfo !== null) {
    const replacement = assertRecord(replacementInfo, "STORE_PRODUCT_MISMATCH");
    replacesProductId = cleanOpaqueString(replacement.productId, {
      code: "STORE_PRODUCT_MISMATCH",
      max: 160,
    });
    getStorePlanForProduct("google_play", replacesProductId);
    if (
      replacesProductId === effectiveItem.productId
      || replacement.replacementMode !== "WITH_TIME_PRORATION"
    ) {
      throw new InputError("STORE_REPLACEMENT_POLICY_MISMATCH");
    }
    const previousPlan = getStorePlanForProduct("google_play", replacesProductId);
    const effectivePlan = getStorePlanForProduct("google_play", effectiveItem.productId);
    if (previousPlan.id !== "premium" || effectivePlan.id !== "professional") {
      throw new InputError("STORE_REPLACEMENT_POLICY_MISMATCH");
    }
    replacementMode = replacement.replacementMode;
  }

  return Object.freeze({
    effectiveItem,
    pendingItem,
    pendingProductId: pendingItem?.productId ?? "",
    pendingEffectiveAt: pendingItem ? new Date(expiresAtMs).toISOString() : "",
    isReplacement: Boolean(pendingItem || replacesProductId),
    replacesProductId,
    replacementMode,
  });
}

export function identifyGooglePurchase(responseValue, {
  productId,
  verificationData,
  purchaseId = "",
  nowMs = Date.now(),
} = {}) {
  const response = assertRecord(responseValue, "UNTRUSTED_STORE_PURCHASE");
  const expectedProductId = cleanOpaqueString(productId, {
    code: "STORE_PRODUCT_MISMATCH",
    max: 160,
  });
  if (response.packageName !== APP_BUNDLE_ID) throw new InputError("STORE_APP_MISMATCH");
  if (response.revoked === true || response.revocationTime !== undefined) {
    throw new InputError("STORE_PURCHASE_REVOKED");
  }
  const status = GOOGLE_STATE_STATUS[response.subscriptionState];
  if (!status) throw new InputError("STORE_PURCHASE_NOT_ACTIVE");
  const selection = selectGoogleSubscriptionLineItem(response, {
    productId: expectedProductId,
    nowMs,
  });
  const lineItem = selection.effectiveItem;
  const accountToken = cleanOpaqueString(
    response.externalAccountIdentifiers?.obfuscatedExternalAccountId,
    { code: "STORE_ACCOUNT_MISMATCH", min: 36, max: 36 },
  );
  if (!UUID_V4_PATTERN.test(accountToken)) throw new InputError("STORE_ACCOUNT_MISMATCH");
  const expiresAt = assertFutureExpiry(lineItem.expiryTime, nowMs);
  const startedAt = response.startTime === undefined && selection.pendingItem
    ? ""
    : normalizedIso(response.startTime, "UNTRUSTED_STORE_PURCHASE");
  if (startedAt && Date.parse(startedAt) > nowMs + 5 * 60_000) {
    throw new InputError("UNTRUSTED_STORE_PURCHASE");
  }
  const orderId = typeof lineItem.latestSuccessfulOrderId === "string"
    && lineItem.latestSuccessfulOrderId.length <= 200
    && lineItem.latestSuccessfulOrderId.trim() === lineItem.latestSuccessfulOrderId
    ? lineItem.latestSuccessfulOrderId
    : "";
  // Google documente l'identifiant de commande comme une donnée d'affichage :
  // seule la réponse subscriptionsv2 liée au purchaseToken fait autorité.
  const purchaseToken = cleanOpaqueString(verificationData, {
    code: "UNTRUSTED_STORE_PURCHASE",
    min: 8,
    max: 20_000,
  });
  const linkedPurchaseToken = optionalGooglePurchaseToken(response.linkedPurchaseToken);
  if (linkedPurchaseToken && linkedPurchaseToken === purchaseToken) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  if (selection.isReplacement && !linkedPurchaseToken) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  const currentTransactionHash = googlePurchaseTokenHash(purchaseToken);
  const linkedTransactionHash = linkedPurchaseToken
    ? googlePurchaseTokenHash(linkedPurchaseToken)
    : "";
  const acknowledgementState = response.acknowledgementState;
  if (![
    "ACKNOWLEDGEMENT_STATE_PENDING",
    "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
  ].includes(acknowledgementState)) {
    throw new InputError("UNTRUSTED_STORE_PURCHASE");
  }
  const purchase = Object.freeze({
    provider: "google",
    productId: lineItem.productId,
    environment: response.testPurchase ? "sandbox" : "production",
    status,
    startsAt: startedAt,
    expiresAt,
    originalTransactionHash: currentTransactionHash,
    currentTransactionHash,
    linkedTransactionHash,
    replacesProductId: selection.replacesProductId,
    replacementMode: selection.replacementMode,
    pendingProductId: selection.pendingProductId,
    pendingEffectiveAt: selection.pendingEffectiveAt,
    lastTransactionHash: orderId
      ? sha256(`google:order:${orderId}`)
      : currentTransactionHash,
    sourceEventHash: sha256(`google:subscription:${purchaseToken}:${response.etag ?? orderId}`),
    providerEventAt: new Date(nowMs).toISOString(),
    needsAcknowledgement: acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING",
  });
  return Object.freeze({ accountToken, purchase });
}

export function normalizeGooglePurchase(responseValue, {
  checkout,
  accountToken,
  verificationData,
  purchaseId = "",
  nowMs = Date.now(),
} = {}) {
  validateStoreCheckout(checkout);
  if (checkout.store !== "google_play") throw new InputError("STORE_PURCHASE_MISMATCH");
  const identified = identifyGooglePurchase(responseValue, {
    productId: checkout.storeProductId,
    verificationData,
    purchaseId,
    nowMs,
  });
  if (!UUID_V4_PATTERN.test(accountToken ?? "") || identified.accountToken !== accountToken) {
    throw new InputError("STORE_ACCOUNT_MISMATCH");
  }
  return identified.purchase;
}

function validateNormalizedPurchase(purchase, checkout, { allowProductChange = false } = {}) {
  const value = assertRecord(purchase, "UNTRUSTED_STORE_PURCHASE");
  const expectedProvider = STORE_PROVIDERS[checkout.store];
  if (
    value.provider !== expectedProvider
    || (!allowProductChange && value.productId !== checkout.storeProductId)
    || ![
      "active",
      "grace_period",
      "billing_retry",
      "on_hold",
      "paused",
      "expired",
      "revoked",
    ].includes(value.status)
    || !["production", "sandbox"].includes(value.environment)
    || !HASH_PATTERN.test(value.originalTransactionHash ?? "")
    || (
      value.provider === "google"
      && !HASH_PATTERN.test(value.currentTransactionHash ?? "")
    )
    || !HASH_PATTERN.test(value.lastTransactionHash ?? "")
    || !HASH_PATTERN.test(value.sourceEventHash ?? "")
    || !Number.isFinite(Date.parse(value.providerEventAt))
  ) {
    throw new InputError("UNTRUSTED_STORE_PURCHASE");
  }
  if (
    value.provider === "google"
    && value.linkedTransactionHash
    && !HASH_PATTERN.test(value.linkedTransactionHash)
  ) {
    throw new InputError("UNTRUSTED_STORE_PURCHASE");
  }
  if (value.replacesProductId) {
    if (
      value.provider !== "google"
      || value.replacementMode !== "WITH_TIME_PRORATION"
      || value.pendingProductId
    ) {
      throw new InputError("STORE_REPLACEMENT_POLICY_MISMATCH");
    }
    getStorePlanForProduct("google_play", value.replacesProductId);
  }
  if (value.pendingProductId) {
    if (
      value.provider !== "google"
      || !allowProductChange
      || value.replacementMode !== "DEFERRED"
      || value.replacesProductId
      || !Number.isFinite(Date.parse(value.pendingEffectiveAt ?? ""))
    ) {
      throw new InputError("STORE_REPLACEMENT_POLICY_MISMATCH");
    }
    getStorePlanForProduct("google_play", value.pendingProductId);
  }
  if (
    value.replacementMode
    && !value.replacesProductId
    && !value.pendingProductId
  ) {
    throw new InputError("STORE_REPLACEMENT_POLICY_MISMATCH");
  }
  if (allowProductChange) getStorePlanForProduct(checkout.store, value.productId);
  const comparisonStart = Number.isFinite(Date.parse(value.startsAt))
    ? Date.parse(value.startsAt)
    : 0;
  assertFutureExpiry(value.expiresAt, comparisonStart);
  return value;
}

export function buildStoreEntitlementId(purchaseValue) {
  const purchase = assertRecord(purchaseValue, "UNTRUSTED_STORE_PURCHASE");
  if (
    !["apple", "google"].includes(purchase.provider)
    || !HASH_PATTERN.test(purchase.originalTransactionHash ?? "")
  ) {
    throw new InputError("UNTRUSTED_STORE_PURCHASE");
  }
  return `ent_${sha256(`${purchase.provider}:${purchase.originalTransactionHash}`).slice(0, 32)}`;
}

export function buildEntitlementRecord(checkoutValue, purchaseValue, nowMs = Date.now()) {
  const checkout = assertRecord(checkoutValue, "INVALID_STORE_CHECKOUT");
  validateStoreCheckout(checkout);
  const purchase = validateNormalizedPurchase(purchaseValue, checkout);
  if (purchase.provider === "google" && (purchase.linkedTransactionHash || purchase.pendingProductId)) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  if (!Number.isFinite(nowMs)) throw new InputError("UNTRUSTED_STORE_PURCHASE");
  return Object.freeze({
    _id: buildStoreEntitlementId(purchase),
    professionalId: buildProfessionalId(`checkout:${checkout._id}`),
    rootCheckoutId: checkout._id,
    checkoutId: checkout._id,
    planId: checkout.planId,
    provider: purchase.provider,
    productId: purchase.productId,
    environment: purchase.environment,
    status: purchase.status,
    startsAt: purchase.startsAt,
    expiresAt: purchase.expiresAt,
    originalTransactionHash: purchase.originalTransactionHash,
    ...(purchase.provider === "google" ? {
      currentTransactionHash: purchase.currentTransactionHash,
      pendingPlanId: "",
      pendingProductId: "",
      pendingEffectiveAt: "",
    } : {}),
    lastTransactionHash: purchase.lastTransactionHash,
    sourceEventHash: purchase.sourceEventHash,
    lastProviderEventAt: purchase.providerEventAt,
    updatedAt: new Date(nowMs).toISOString(),
  });
}

export function buildLifecycleEntitlementRecord(
  checkoutValue,
  purchaseValue,
  existingValue = null,
  nowMs = Date.now(),
) {
  const checkout = assertRecord(checkoutValue, "INVALID_STORE_CHECKOUT");
  validateStoreCheckout(checkout);
  const purchase = validateNormalizedPurchase(
    purchaseValue,
    checkout,
    { allowProductChange: true },
  );
  if (!Number.isFinite(nowMs)) throw new InputError("UNTRUSTED_STORE_PURCHASE");
  const plan = getStorePlanForProduct(checkout.store, purchase.productId);
  const entitlementId = buildStoreEntitlementId(purchase);
  const professionalId = buildProfessionalId(`checkout:${checkout._id}`);
  if (existingValue) {
    const existing = assertRecord(existingValue, "INVALID_ENTITLEMENT");
    const rootCheckoutId = existing.rootCheckoutId ?? existing.checkoutId;
    if (
      existing._id !== entitlementId
      || existing.checkoutId !== checkout._id
      || existing.professionalId !== professionalId
      || !CHECKOUT_ID_PATTERN.test(rootCheckoutId ?? "")
      || existing.professionalId !== buildProfessionalId(`checkout:${rootCheckoutId}`)
      || existing.provider !== purchase.provider
      || existing.originalTransactionHash !== purchase.originalTransactionHash
    ) {
      throw new InputError("STORE_PURCHASE_ALREADY_USED");
    }
  }
  return Object.freeze({
    _id: entitlementId,
    professionalId,
    rootCheckoutId: existingValue?.rootCheckoutId ?? checkout._id,
    checkoutId: checkout._id,
    planId: plan.id,
    provider: purchase.provider,
    productId: purchase.productId,
    environment: purchase.environment,
    status: purchase.status,
    startsAt: purchase.startsAt,
    expiresAt: purchase.expiresAt,
    originalTransactionHash: purchase.originalTransactionHash,
    lastTransactionHash: purchase.lastTransactionHash,
    sourceEventHash: purchase.sourceEventHash,
    lastProviderEventAt: purchase.providerEventAt,
    updatedAt: new Date(nowMs).toISOString(),
  });
}

function withEntitlementLineage(record, previousCurrentTransactionHash) {
  Object.defineProperty(record, ENTITLEMENT_LINEAGE, {
    value: Object.freeze({ previousCurrentTransactionHash }),
    enumerable: false,
    writable: false,
    configurable: false,
  });
  return Object.freeze(record);
}

export function buildGoogleLineageEntitlementRecord(
  checkoutValue,
  purchaseValue,
  existingValue,
  nowMs = Date.now(),
) {
  const checkout = assertRecord(checkoutValue, "INVALID_STORE_CHECKOUT");
  validateStoreCheckout(checkout);
  if (checkout.store !== "google_play") throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  const purchase = validateNormalizedPurchase(
    purchaseValue,
    checkout,
    { allowProductChange: true },
  );
  const existing = assertRecord(existingValue, "INVALID_ENTITLEMENT");
  const rootCheckoutId = existing.rootCheckoutId ?? existing.checkoutId;
  const existingCurrentTransactionHash = existing.currentTransactionHash
    ?? existing.originalTransactionHash;
  if (
    existing.provider !== "google"
    || !CHECKOUT_ID_PATTERN.test(rootCheckoutId ?? "")
    || existing.professionalId !== buildProfessionalId(`checkout:${rootCheckoutId}`)
    || !HASH_PATTERN.test(existingCurrentTransactionHash ?? "")
    || !HASH_PATTERN.test(purchase.currentTransactionHash ?? "")
    || existing._id !== buildStoreEntitlementId({
      provider: "google",
      originalTransactionHash: existing.originalTransactionHash,
    })
  ) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  const currentReplay = existingCurrentTransactionHash === purchase.currentTransactionHash;
  const directReplacement = purchase.linkedTransactionHash
    && existingCurrentTransactionHash === purchase.linkedTransactionHash
    && existingCurrentTransactionHash !== purchase.currentTransactionHash;
  if (!currentReplay && !directReplacement) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  const existingExpired = ["expired", "revoked"].includes(existing.status)
    || (
      Number.isFinite(Date.parse(existing.expiresAt ?? ""))
      && Date.parse(existing.expiresAt) <= nowMs
    );
  // Google peut créer un nouveau purchaseToken (et donc un nouveau checkout
  // local) lors d'un réabonnement au même produit, sans itemReplacement. Le
  // linkedPurchaseToken vérifié constitue alors la preuve de continuité du
  // compte Play; le jeton de compte courant a déjà été lié au checkout par
  // normalizeGooglePurchase. Une chaîne encore active ou un autre produit
  // restent refusés afin d'empêcher une migration arbitraire de droit.
  const safeSameProductResubscribe = directReplacement
    && !purchase.replacementMode
    && purchase.productId === existing.productId
    && existingExpired
    && !purchase.replacesProductId
    && !purchase.pendingProductId;
  if (directReplacement && !purchase.replacementMode && !safeSameProductResubscribe) {
    throw new InputError("STORE_REPLACEMENT_POLICY_MISMATCH");
  }
  const expectedPreviousProductId = purchase.replacesProductId
    || (purchase.pendingProductId ? purchase.productId : "");
  if (
    directReplacement
    && expectedPreviousProductId
    && existing.productId !== expectedPreviousProductId
  ) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  if (checkout._id !== existing.checkoutId && !directReplacement) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  const requestedProductId = purchase.pendingProductId || purchase.productId;
  if (checkout.storeProductId !== requestedProductId) {
    throw new InputError("STORE_PRODUCT_MISMATCH");
  }
  const activePlan = getStorePlanForProduct("google_play", purchase.productId);
  const pendingPlan = purchase.pendingProductId
    ? getStorePlanForProduct("google_play", purchase.pendingProductId)
    : null;
  if (
    pendingPlan
    && (
      !directReplacement && !currentReplay
      || purchase.pendingEffectiveAt !== purchase.expiresAt
    )
  ) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  if (!Number.isFinite(nowMs)) throw new InputError("UNTRUSTED_STORE_PURCHASE");
  const record = {
    _id: existing._id,
    professionalId: existing.professionalId,
    rootCheckoutId,
    checkoutId: checkout._id,
    planId: activePlan.id,
    provider: "google",
    productId: purchase.productId,
    environment: purchase.environment,
    status: purchase.status,
    startsAt: purchase.startsAt || existing.startsAt,
    expiresAt: purchase.expiresAt,
    originalTransactionHash: existing.originalTransactionHash,
    currentTransactionHash: purchase.currentTransactionHash,
    pendingPlanId: pendingPlan?.id ?? "",
    pendingProductId: pendingPlan?.storeProducts?.google_play ?? "",
    pendingEffectiveAt: pendingPlan ? purchase.pendingEffectiveAt : "",
    lastTransactionHash: purchase.lastTransactionHash,
    sourceEventHash: purchase.sourceEventHash,
    lastProviderEventAt: purchase.providerEventAt,
    updatedAt: new Date(nowMs).toISOString(),
  };
  return withEntitlementLineage(
    record,
    directReplacement ? existingCurrentTransactionHash : "",
  );
}

const ENTITLEMENT_STATUS_SEVERITY = Object.freeze({
  active: 0,
  grace_period: 1,
  billing_retry: 2,
  on_hold: 2,
  paused: 2,
  expired: 3,
  revoked: 4,
});

export function compareStoreEntitlements(leftValue, rightValue) {
  const left = assertRecord(leftValue, "INVALID_ENTITLEMENT");
  const right = assertRecord(rightValue, "INVALID_ENTITLEMENT");
  const leftAt = Date.parse(left.lastProviderEventAt ?? "");
  const rightAt = Date.parse(right.lastProviderEventAt ?? "");
  if (!Number.isFinite(leftAt) || !Number.isFinite(rightAt)) {
    throw new InputError("INVALID_ENTITLEMENT");
  }
  if (leftAt !== rightAt) return leftAt - rightAt;
  const statusDifference = (ENTITLEMENT_STATUS_SEVERITY[left.status] ?? -1)
    - (ENTITLEMENT_STATUS_SEVERITY[right.status] ?? -1);
  if (statusDifference !== 0) return statusDifference;
  return String(left.sourceEventHash ?? "").localeCompare(String(right.sourceEventHash ?? ""));
}

export function selectLatestStoreEntitlement(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new InputError("INVALID_ENTITLEMENT");
  }
  return values.reduce((latest, candidate) => (
    compareStoreEntitlements(candidate, latest) > 0 ? candidate : latest
  ));
}

export function reconcileEntitlement(existingValue, incomingValue) {
  const incoming = assertRecord(incomingValue, "INVALID_ENTITLEMENT");
  if (!existingValue) {
    return Object.freeze({ action: "insert", item: incoming, idempotent: false });
  }
  const existing = assertRecord(existingValue, "INVALID_ENTITLEMENT");
  const lineage = incoming[ENTITLEMENT_LINEAGE];
  const checkoutChanged = existing.checkoutId !== incoming.checkoutId;
  const existingRootCheckoutId = existing.rootCheckoutId ?? existing.checkoutId;
  const incomingRootCheckoutId = incoming.rootCheckoutId ?? incoming.checkoutId;
  const validGoogleReplacement = checkoutChanged
    && existing.provider === "google"
    && incoming.provider === "google"
    && lineage?.previousCurrentTransactionHash
      === (existing.currentTransactionHash ?? existing.originalTransactionHash)
    && incoming.currentTransactionHash
      !== (existing.currentTransactionHash ?? existing.originalTransactionHash);
  const immutableFields = [
    "_id",
    "professionalId",
    "provider",
    "originalTransactionHash",
  ];
  if (
    !CHECKOUT_ID_PATTERN.test(existingRootCheckoutId ?? "")
    || !CHECKOUT_ID_PATTERN.test(incomingRootCheckoutId ?? "")
    || immutableFields.some((field) => existing[field] !== incoming[field])
    || existingRootCheckoutId !== incomingRootCheckoutId
    || (checkoutChanged && !validGoogleReplacement)
  ) {
    throw new InputError("STORE_PURCHASE_ALREADY_USED");
  }
  const comparedFields = [
    "rootCheckoutId",
    "checkoutId",
    "planId",
    "productId",
    "environment",
    "status",
    "startsAt",
    "expiresAt",
    "lastTransactionHash",
    "currentTransactionHash",
    "pendingPlanId",
    "pendingProductId",
    "pendingEffectiveAt",
    "sourceEventHash",
    "lastProviderEventAt",
  ];
  if (existing.sourceEventHash === incoming.sourceEventHash) {
    return Object.freeze({ action: "unchanged", item: existing, idempotent: true });
  }
  if (comparedFields.every((field) => existing[field] === incoming[field])) {
    return Object.freeze({ action: "unchanged", item: existing, idempotent: true });
  }
  const existingEventAt = Date.parse(existing.lastProviderEventAt ?? "");
  const incomingEventAt = Date.parse(incoming.lastProviderEventAt ?? "");
  if (
    Number.isFinite(existingEventAt)
    && Number.isFinite(incomingEventAt)
    && incomingEventAt < existingEventAt
    && !(
      existingEventAt - incomingEventAt <= 5 * 60_000
      && ENTITLEMENT_STATUS_SEVERITY[incoming.status]
        > ENTITLEMENT_STATUS_SEVERITY[existing.status]
    )
  ) {
    return Object.freeze({ action: "unchanged", item: existing, idempotent: true });
  }
  return Object.freeze({
    action: "update",
    item: Object.freeze({ ...existing, ...incoming, _id: existing._id }),
    idempotent: false,
  });
}

export function storePaymentReference(purchase) {
  if (!purchase || !HASH_PATTERN.test(purchase.lastTransactionHash ?? "")) {
    throw new InputError("UNTRUSTED_STORE_PURCHASE");
  }
  return `store:${purchase.provider}:${purchase.lastTransactionHash}`;
}
