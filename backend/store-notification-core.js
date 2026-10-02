import { InputError, sha256 } from "./security-core.js";
import {
  APP_BUNDLE_ID,
  selectGoogleSubscriptionLineItem,
} from "./store-purchase-core.js";

const HASH_PATTERN = /^[a-f0-9]{64}$/u;
const UUID_PATTERN = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/iu;
const ENTITLEMENT_ID_PATTERN = /^ent_[a-f0-9]{32}$/u;
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/u;

const APPLE_STATUS = Object.freeze({
  1: "active",
  2: "expired",
  3: "billing_retry",
  4: "grace_period",
  5: "revoked",
});

const GOOGLE_STATE = Object.freeze({
  SUBSCRIPTION_STATE_ACTIVE: "active",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
  SUBSCRIPTION_STATE_CANCELED: "active",
  SUBSCRIPTION_STATE_ON_HOLD: "on_hold",
  SUBSCRIPTION_STATE_PAUSED: "paused",
  SUBSCRIPTION_STATE_EXPIRED: "expired",
  SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: "expired",
});

const GOOGLE_NOTIFICATION_TYPE = Object.freeze({
  1: "SUBSCRIPTION_RECOVERED",
  2: "SUBSCRIPTION_RENEWED",
  3: "SUBSCRIPTION_CANCELED",
  4: "SUBSCRIPTION_PURCHASED",
  5: "SUBSCRIPTION_ON_HOLD",
  6: "SUBSCRIPTION_IN_GRACE_PERIOD",
  7: "SUBSCRIPTION_RESTARTED",
  8: "SUBSCRIPTION_PRICE_CHANGE_CONFIRMED",
  9: "SUBSCRIPTION_DEFERRED",
  10: "SUBSCRIPTION_PAUSED",
  11: "SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED",
  12: "SUBSCRIPTION_REVOKED",
  13: "SUBSCRIPTION_EXPIRED",
  17: "SUBSCRIPTION_ITEMS_CHANGED",
  18: "SUBSCRIPTION_CANCELLATION_SCHEDULED",
  19: "SUBSCRIPTION_PRICE_CHANGE_UPDATED",
  20: "SUBSCRIPTION_PENDING_PURCHASE_CANCELED",
  22: "SUBSCRIPTION_PRICE_STEP_UP_CONSENT_UPDATED",
});

function record(value, code = "INVALID_STORE_NOTIFICATION") {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new InputError(code);
  return value;
}

function opaque(value, { code = "INVALID_STORE_NOTIFICATION", min = 1, max = 256 } = {}) {
  if (
    typeof value !== "string"
    || value.length < min
    || value.length > max
    || value.trim() !== value
  ) {
    throw new InputError(code);
  }
  return value;
}

function timestamp(value, code = "INVALID_STORE_NOTIFICATION") {
  const milliseconds = typeof value === "number" ? value : Date.parse(value);
  if (!Number.isFinite(milliseconds)) throw new InputError(code);
  return milliseconds;
}

function eventTimestamp(value, nowMs, code = "INVALID_STORE_NOTIFICATION") {
  const milliseconds = timestamp(value, code);
  if (!Number.isFinite(nowMs) || milliseconds > nowMs + 5 * 60_000) throw new InputError(code);
  return new Date(milliseconds).toISOString();
}

function subscriptionTimes({ startTime, expiryTime, nowMs }) {
  const startsAtMs = timestamp(startTime, "UNTRUSTED_STORE_NOTIFICATION");
  const expiresAtMs = timestamp(expiryTime, "UNTRUSTED_STORE_NOTIFICATION");
  if (startsAtMs > nowMs + 5 * 60_000 || expiresAtMs <= startsAtMs) {
    throw new InputError("UNTRUSTED_STORE_NOTIFICATION");
  }
  return {
    startsAt: new Date(startsAtMs).toISOString(),
    expiresAt: new Date(expiresAtMs).toISOString(),
    expiresAtMs,
  };
}

function appleEnvironment(value) {
  if (value === "Production") return "production";
  if (value === "Sandbox") return "sandbox";
  throw new InputError("STORE_ENVIRONMENT_MISMATCH");
}

export function normalizeAppleLifecycleEvent(notificationValue, transactionValue, {
  signedPayload,
  signedTransactionInfo,
  nowMs = Date.now(),
} = {}) {
  const notification = record(notificationValue, "UNTRUSTED_STORE_NOTIFICATION");
  const transaction = record(transactionValue, "UNTRUSTED_STORE_NOTIFICATION");
  const data = record(notification.data, "UNTRUSTED_STORE_NOTIFICATION");
  const notificationType = opaque(notification.notificationType, {
    code: "UNTRUSTED_STORE_NOTIFICATION",
    max: 80,
  });
  const subtype = notification.subtype === undefined
    ? ""
    : opaque(notification.subtype, { code: "UNTRUSTED_STORE_NOTIFICATION", max: 80 });
  const notificationUuid = opaque(notification.notificationUUID, {
    code: "UNTRUSTED_STORE_NOTIFICATION",
    min: 36,
    max: 36,
  });
  if (!UUID_PATTERN.test(notificationUuid) || notification.version !== "2.0") {
    throw new InputError("UNTRUSTED_STORE_NOTIFICATION");
  }
  const eventAt = eventTimestamp(notification.signedDate, nowMs, "UNTRUSTED_STORE_NOTIFICATION");
  const rawNotification = opaque(signedPayload, {
    code: "UNTRUSTED_STORE_NOTIFICATION",
    min: 8,
    max: 300_000,
  });
  const rawTransaction = opaque(signedTransactionInfo, {
    code: "UNTRUSTED_STORE_NOTIFICATION",
    min: 8,
    max: 200_000,
  });
  if (
    data.bundleId !== APP_BUNDLE_ID
    || transaction.bundleId !== APP_BUNDLE_ID
    || data.bundleId !== transaction.bundleId
  ) {
    throw new InputError("STORE_APP_MISMATCH");
  }
  const environment = appleEnvironment(data.environment);
  if (appleEnvironment(transaction.environment) !== environment) {
    throw new InputError("STORE_ENVIRONMENT_MISMATCH");
  }
  if (transaction.type !== "Auto-Renewable Subscription") {
    throw new InputError("STORE_PRODUCT_MISMATCH");
  }
  const productId = opaque(transaction.productId, { code: "STORE_PRODUCT_MISMATCH", max: 160 });
  const accountToken = opaque(transaction.appAccountToken, {
    code: "STORE_ACCOUNT_MISMATCH",
    min: 36,
    max: 36,
  });
  if (!UUID_PATTERN.test(accountToken)) throw new InputError("STORE_ACCOUNT_MISMATCH");
  const transactionId = opaque(transaction.transactionId, {
    code: "UNTRUSTED_STORE_NOTIFICATION",
    max: 200,
  });
  const originalTransactionId = opaque(transaction.originalTransactionId, {
    code: "UNTRUSTED_STORE_NOTIFICATION",
    max: 200,
  });
  const times = subscriptionTimes({
    startTime: transaction.purchaseDate,
    expiryTime: transaction.expiresDate,
    nowMs,
  });
  let status = APPLE_STATUS[Number(data.status)];
  if (!status) throw new InputError("UNTRUSTED_STORE_NOTIFICATION");
  if (["REFUND", "REVOKE"].includes(notificationType) || transaction.revocationDate != null) {
    status = "revoked";
  } else if (["EXPIRED", "GRACE_PERIOD_EXPIRED"].includes(notificationType)) {
    status = "expired";
  } else if (["active", "grace_period"].includes(status) && times.expiresAtMs <= nowMs) {
    status = "expired";
  }
  const providerEventAt = eventAt;
  const sourceEventHash = sha256(`apple:notification:${rawNotification}`);
  const purchase = Object.freeze({
    provider: "apple",
    productId,
    environment,
    status,
    startsAt: times.startsAt,
    expiresAt: times.expiresAt,
    originalTransactionHash: sha256(`apple:original:${originalTransactionId}`),
    lastTransactionHash: sha256(`apple:transaction:${transactionId}`),
    sourceEventHash,
    providerEventAt,
    needsAcknowledgement: false,
  });
  return Object.freeze({
    provider: "apple",
    eventId: `sev_${sha256(`apple:${notificationUuid}`).slice(0, 32)}`,
    eventType: subtype ? `${notificationType}:${subtype}` : notificationType,
    eventAt,
    sourceEventHash,
    accountToken,
    purchase,
    transactionSourceHash: sha256(`apple:transaction-jws:${rawTransaction}`),
  });
}

function decodeBase64Json(value) {
  const encoded = opaque(value, { code: "INVALID_GOOGLE_RTDN", min: 4, max: 128_000 });
  if (!BASE64_PATTERN.test(encoded) || encoded.length % 4 === 1) {
    throw new InputError("INVALID_GOOGLE_RTDN");
  }
  try {
    const decoded = Buffer.from(encoded, "base64");
    if (decoded.length < 2 || decoded.length > 96_000) throw new Error("size");
    return record(JSON.parse(decoded.toString("utf8")), "INVALID_GOOGLE_RTDN");
  } catch (_error) {
    throw new InputError("INVALID_GOOGLE_RTDN");
  }
}

export function decodeGoogleRtdnEnvelope(rawBody, {
  expectedSubscription,
  nowMs = Date.now(),
} = {}) {
  const body = record(rawBody, "INVALID_GOOGLE_RTDN");
  const subscription = opaque(body.subscription, {
    code: "INVALID_GOOGLE_RTDN",
    max: 300,
  });
  const expected = opaque(expectedSubscription, {
    code: "GOOGLE_RTDN_CONFIGURATION_INVALID",
    max: 300,
  });
  if (subscription !== expected) throw new InputError("GOOGLE_RTDN_SUBSCRIPTION_MISMATCH");
  const message = record(body.message, "INVALID_GOOGLE_RTDN");
  const messageId = opaque(message.messageId ?? message.message_id, {
    code: "INVALID_GOOGLE_RTDN",
    max: 128,
  });
  const payload = decodeBase64Json(message.data);
  if (payload.version !== "1.0") throw new InputError("INVALID_GOOGLE_RTDN");
  if (payload.packageName !== APP_BUNDLE_ID) throw new InputError("STORE_APP_MISMATCH");
  const eventTimeNumber = Number(payload.eventTimeMillis);
  if (!Number.isSafeInteger(eventTimeNumber) || eventTimeNumber <= 0) {
    throw new InputError("INVALID_GOOGLE_RTDN");
  }
  const eventAt = eventTimestamp(eventTimeNumber, nowMs, "INVALID_GOOGLE_RTDN");
  const base = {
    provider: "google",
    eventId: `sev_${sha256(`google:${messageId}`).slice(0, 32)}`,
    messageIdHash: sha256(`google:message:${messageId}`),
    eventAt,
    packageName: APP_BUNDLE_ID,
  };
  const notificationFamilies = [
    ["subscription", payload.subscriptionNotification],
    ["one_time_product", payload.oneTimeProductNotification],
    ["voided_purchase", payload.voidedPurchaseNotification],
    ["pending_refund_review", payload.pendingRefundReviewNotification],
    ["test", payload.testNotification],
  ].filter(([, value]) => value !== undefined && value !== null);
  if (notificationFamilies.length !== 1) throw new InputError("INVALID_GOOGLE_RTDN");
  const [notificationFamily, notificationValue] = notificationFamilies[0];
  const notification = record(notificationValue, "INVALID_GOOGLE_RTDN");

  if (notificationFamily === "test") {
    if (notification.version !== "1.0") throw new InputError("INVALID_GOOGLE_RTDN");
    return Object.freeze({ ...base, test: true, eventType: "TEST_NOTIFICATION" });
  }
  if (notificationFamily === "one_time_product") {
    if (notification.version !== "1.0") throw new InputError("INVALID_GOOGLE_RTDN");
    const notificationType = Number(notification.notificationType);
    const eventType = {
      1: "ONE_TIME_PRODUCT_PURCHASED",
      2: "ONE_TIME_PRODUCT_CANCELED",
    }[notificationType];
    if (!eventType || !Number.isInteger(notificationType)) {
      throw new InputError("INVALID_GOOGLE_RTDN");
    }
    opaque(notification.purchaseToken, {
      code: "INVALID_GOOGLE_RTDN",
      min: 8,
      max: 20_000,
    });
    opaque(notification.sku, { code: "INVALID_GOOGLE_RTDN", max: 160 });
    return Object.freeze({
      ...base,
      test: false,
      ignored: true,
      notificationFamily,
      eventType,
    });
  }
  if (notificationFamily === "voided_purchase") {
    opaque(notification.purchaseToken, {
      code: "INVALID_GOOGLE_RTDN",
      min: 8,
      max: 20_000,
    });
    opaque(notification.orderId, { code: "INVALID_GOOGLE_RTDN", max: 200 });
    const productType = Number(notification.productType);
    const refundType = Number(notification.refundType);
    if (
      !Number.isInteger(productType)
      || ![1, 2].includes(productType)
      || !Number.isInteger(refundType)
      || ![1, 2].includes(refundType)
    ) {
      throw new InputError("INVALID_GOOGLE_RTDN");
    }
    const productLabel = productType === 1 ? "SUBSCRIPTION" : "ONE_TIME_PRODUCT";
    const refundLabel = refundType === 1 ? "FULL_REFUND" : "QUANTITY_PARTIAL_REFUND";
    return Object.freeze({
      ...base,
      test: false,
      ignored: true,
      notificationFamily,
      eventType: `VOIDED_${productLabel}_${refundLabel}`,
    });
  }
  if (notificationFamily === "pending_refund_review") {
    if (notification.version !== "1.0") throw new InputError("INVALID_GOOGLE_RTDN");
    opaque(notification.pendingRefundToken, {
      code: "INVALID_GOOGLE_RTDN",
      min: 8,
      max: 20_000,
    });
    opaque(notification.orderId, { code: "INVALID_GOOGLE_RTDN", max: 200 });
    const refundReason = Number(notification.refundReason);
    if (!Number.isInteger(refundReason) || refundReason < 1 || refundReason > 1_000) {
      throw new InputError("INVALID_GOOGLE_RTDN");
    }
    for (const optionalId of ["obfuscatedAccountId", "obfuscatedProfileId"]) {
      if (notification[optionalId] !== undefined && notification[optionalId] !== null) {
        opaque(notification[optionalId], { code: "INVALID_GOOGLE_RTDN", max: 256 });
      }
    }
    return Object.freeze({
      ...base,
      test: false,
      ignored: true,
      notificationFamily,
      eventType: "PENDING_REFUND_REVIEW",
    });
  }

  if (notification.version !== "1.0") throw new InputError("INVALID_GOOGLE_RTDN");
  const notificationType = Number(notification.notificationType);
  const eventType = GOOGLE_NOTIFICATION_TYPE[notificationType];
  if (!eventType || !Number.isInteger(notificationType)) {
    throw new InputError("INVALID_GOOGLE_RTDN");
  }
  const purchaseToken = opaque(notification.purchaseToken, {
    code: "INVALID_GOOGLE_RTDN",
    min: 8,
    max: 20_000,
  });
  return Object.freeze({
    ...base,
    test: false,
    ignored: false,
    notificationFamily,
    notificationType,
    eventType,
    purchaseToken,
  });
}

export function validateGooglePendingPurchaseCanceled(rtdnValue, responseValue) {
  const rtdn = record(rtdnValue, "INVALID_GOOGLE_RTDN");
  const response = record(responseValue, "UNTRUSTED_STORE_NOTIFICATION");
  if (rtdn.test || rtdn.notificationType !== 20) {
    throw new InputError("INVALID_GOOGLE_RTDN");
  }
  if (rtdn.packageName !== APP_BUNDLE_ID || response.packageName !== APP_BUNDLE_ID) {
    throw new InputError("STORE_APP_MISMATCH");
  }
  if (response.subscriptionState !== "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED") {
    throw new InputError("UNTRUSTED_STORE_NOTIFICATION");
  }
  const purchaseToken = opaque(rtdn.purchaseToken, {
    code: "INVALID_GOOGLE_RTDN",
    min: 8,
    max: 20_000,
  });
  const linkedPurchaseToken = response.linkedPurchaseToken === undefined
    || response.linkedPurchaseToken === null
    ? ""
    : opaque(response.linkedPurchaseToken, {
      code: "UNTRUSTED_STORE_NOTIFICATION",
      min: 8,
      max: 20_000,
    });
  if (linkedPurchaseToken === purchaseToken) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  return Object.freeze({ ignored: true });
}

export function normalizeGoogleLifecycleEvent(rtdnValue, responseValue, {
  nowMs = Date.now(),
} = {}) {
  const rtdn = record(rtdnValue, "INVALID_GOOGLE_RTDN");
  const response = record(responseValue, "UNTRUSTED_STORE_NOTIFICATION");
  if (rtdn.test || rtdn.packageName !== APP_BUNDLE_ID || response.packageName !== APP_BUNDLE_ID) {
    throw new InputError("STORE_APP_MISMATCH");
  }
  const selection = selectGoogleSubscriptionLineItem(response, {
    nowMs,
    allowExpired: true,
    expectedRole: "effective",
  });
  const lineItem = selection.effectiveItem;
  const accountToken = opaque(
    response.externalAccountIdentifiers?.obfuscatedExternalAccountId,
    { code: "STORE_ACCOUNT_MISMATCH", min: 36, max: 36 },
  );
  if (!UUID_PATTERN.test(accountToken)) throw new InputError("STORE_ACCOUNT_MISMATCH");
  const expiresAtMs = timestamp(lineItem.expiryTime, "UNTRUSTED_STORE_NOTIFICATION");
  const startsAt = response.startTime === undefined && selection.pendingItem
    ? ""
    : eventTimestamp(response.startTime, nowMs, "UNTRUSTED_STORE_NOTIFICATION");
  if (startsAt && expiresAtMs <= Date.parse(startsAt)) {
    throw new InputError("UNTRUSTED_STORE_NOTIFICATION");
  }
  const expiresAt = new Date(expiresAtMs).toISOString();
  let status = GOOGLE_STATE[response.subscriptionState];
  if (!status) throw new InputError("UNTRUSTED_STORE_NOTIFICATION");
  if (rtdn.notificationType === 12) status = "revoked";
  else if ([13, 20].includes(rtdn.notificationType)) status = "expired";
  else if (rtdn.notificationType === 5) status = "on_hold";
  else if (rtdn.notificationType === 6) status = "grace_period";
  else if (rtdn.notificationType === 10) status = "paused";
  else if (["active", "grace_period"].includes(status) && expiresAtMs <= nowMs) status = "expired";
  const acknowledgementState = response.acknowledgementState;
  if (!["ACKNOWLEDGEMENT_STATE_PENDING", "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED"].includes(acknowledgementState)) {
    throw new InputError("UNTRUSTED_STORE_NOTIFICATION");
  }
  const orderId = typeof lineItem.latestSuccessfulOrderId === "string"
    && lineItem.latestSuccessfulOrderId.length <= 200
    ? lineItem.latestSuccessfulOrderId
    : "";
  const sourceEventHash = sha256(
    `google:rtdn:${rtdn.messageIdHash}:${rtdn.notificationType}:${rtdn.eventAt}:${rtdn.purchaseToken}`,
  );
  const linkedPurchaseToken = response.linkedPurchaseToken === undefined
    || response.linkedPurchaseToken === null
    || response.linkedPurchaseToken === ""
    ? ""
    : opaque(response.linkedPurchaseToken, {
      code: "UNTRUSTED_STORE_NOTIFICATION",
      min: 8,
      max: 20_000,
    });
  if (linkedPurchaseToken === rtdn.purchaseToken) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  if (selection.isReplacement && !linkedPurchaseToken) {
    throw new InputError("STORE_PURCHASE_LINEAGE_INVALID");
  }
  const currentTransactionHash = sha256(`google:purchase-token:${rtdn.purchaseToken}`);
  const linkedTransactionHash = linkedPurchaseToken
    ? sha256(`google:purchase-token:${linkedPurchaseToken}`)
    : "";
  const purchase = Object.freeze({
    provider: "google",
    productId: lineItem.productId,
    environment: response.testPurchase ? "sandbox" : "production",
    status,
    startsAt,
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
    sourceEventHash,
    providerEventAt: rtdn.eventAt,
    needsAcknowledgement: acknowledgementState === "ACKNOWLEDGEMENT_STATE_PENDING",
  });
  return Object.freeze({
    provider: "google",
    eventId: rtdn.eventId,
    eventType: rtdn.eventType,
    eventAt: rtdn.eventAt,
    sourceEventHash,
    accountToken,
    purchase,
    verificationData: rtdn.purchaseToken,
    acknowledgementProductId: lineItem.productId,
  });
}

export function buildStoreEventRecord(eventValue, entitlementId, nowMs = Date.now()) {
  const event = record(eventValue, "INVALID_STORE_NOTIFICATION");
  if (
    !/^sev_[a-f0-9]{32}$/u.test(event.eventId ?? "")
    || !["apple", "google"].includes(event.provider)
    || !HASH_PATTERN.test(event.sourceEventHash ?? "")
    || !ENTITLEMENT_ID_PATTERN.test(entitlementId ?? "")
    || !Number.isFinite(nowMs)
  ) {
    throw new InputError("INVALID_STORE_NOTIFICATION");
  }
  return Object.freeze({
    _id: event.eventId,
    provider: event.provider,
    eventType: opaque(event.eventType, { code: "INVALID_STORE_NOTIFICATION", max: 180 }),
    eventAt: new Date(timestamp(event.eventAt)).toISOString(),
    sourceEventHash: event.sourceEventHash,
    entitlementId,
    status: "processing",
    createdAt: new Date(nowMs).toISOString(),
  });
}
