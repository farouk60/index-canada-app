import {
  badRequest,
  created,
  forbidden,
  notFound,
  ok,
  response,
  serverError,
} from "wix-http-functions";
import wixData from "wix-data";
import { elevate } from "wix-auth";
import { mediaManager } from "wix-media-backend";
import { secrets } from "wix-secrets-backend.v2";
import Stripe from "stripe";
import {
  DIRECTORY_COLLECTION_LIMITS,
  DirectoryDatasetLimitError,
  DirectoryPaginationInputError,
  buildDirectoryPage,
  collectAllPages,
  normalizeDirectoryPageRequest,
} from "backend/directory-pagination";
import {
  InputError,
  assertCheckoutNotExpired,
  buildEngagementEventRecord,
  buildMediaUploadPlan,
  buildPersistedCheckoutDraft,
  buildProfessionalId,
  buildProfessionalRecord,
  classifyPaymentIntentWebhook,
  classifyConfirmationReference,
  createCheckoutDraft,
  createFreeCheckoutToken,
  directorySearchText,
  evaluateRateLimit,
  getPlan,
  isCategoryEnabled,
  isProfessionalPubliclyVisible,
  isReviewPublic,
  normalizeFeaturedFilter,
  normalizeProfessionalIdFilter,
  normalizeProfessionalIdsFilter,
  normalizeReviewInput,
  normalizeSearchParams,
  normalizeWixImageUrl,
  projectPaymentPlans,
  reviewProfessionalId,
  selectOrphanedMediaUrls,
  sha256,
  toPublicOffer,
  toPublicPartner,
  toPublicProfessional,
  toPublicReview,
  toPublicSubCategory,
  validatePaymentIntentBinding,
  validatePaymentIntentForCheckout,
  validatePersistedCheckout,
  validateRequestSize,
  verifyFreeCheckoutToken,
} from "backend/security-core";
import {
  createStoreCheckoutDraft,
  createStoreSigningKeyring,
  deriveStoreAccountToken,
  reconcileEntitlement,
  validateStoreCheckout,
  validateStoreRestoration,
} from "backend/store-purchase-core";
import {
  confirmStorePurchaseWithDependencies,
  restoreStorePurchaseWithDependencies,
} from "backend/store-purchase-service";
import {
  decodeGoogleRtdnEnvelope,
  normalizeAppleLifecycleEvent,
  normalizeGoogleLifecycleEvent,
} from "backend/store-notification-core";
import { processStoreLifecycleEvent } from "backend/store-notification-service";
import {
  StoreProviderError,
  createAppleTransactionVerifier,
  createGooglePushTokenVerifier,
  createGoogleSubscriptionVerifier,
} from "backend/store-purchase-verifiers";

const DATA_OPTIONS = Object.freeze({ suppressAuth: true });
const CONSISTENT_DATA_OPTIONS = Object.freeze({ suppressAuth: true, consistentRead: true });
const CHECKOUT_COLLECTION = "PaymentCheckouts";
const ENGAGEMENT_COLLECTION = "EngagementEvents";
const RATE_LIMIT_COLLECTION = "ApiRateLimits";
const ENTITLEMENT_COLLECTION = "Entitlements";
const STORE_EVENT_COLLECTION = "PaymentEvents";
const CHECKOUT_VERSION = "2";
const STRIPE_SECRET_NAME = "STRIPE_SECRET_KEY";
const STRIPE_WEBHOOK_SECRET_NAME = "STRIPE_WEBHOOK_SECRET";
const CHECKOUT_SIGNING_SECRET_NAME = "CHECKOUT_SIGNING_SECRET";
const CHECKOUT_SIGNING_SECRET_PREVIOUS_NAME = "CHECKOUT_SIGNING_SECRET_PREVIOUS";
const APPLE_APP_ID_SECRET_NAME = "APPLE_APP_ID";
const APPLE_ROOT_CERTIFICATE_SECRET_NAMES = Object.freeze([
  "APPLE_ROOT_CERTIFICATE_G1_BASE64",
  "APPLE_ROOT_CERTIFICATE_G2_BASE64",
  "APPLE_ROOT_CERTIFICATE_G3_BASE64",
]);
const GOOGLE_PLAY_SERVICE_ACCOUNT_SECRET_NAME = "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON";
const GOOGLE_RTDN_AUDIENCE_SECRET_NAME = "GOOGLE_RTDN_AUDIENCE";
const GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL_SECRET_NAME = "GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL";
const GOOGLE_RTDN_SUBSCRIPTION_SECRET_NAME = "GOOGLE_RTDN_SUBSCRIPTION";
const STORE_ALLOW_SANDBOX_SECRET_NAME = "STORE_ALLOW_SANDBOX";

const RATE_LIMITS = Object.freeze({
  directory: Object.freeze({ limit: 120, windowMs: 60_000, failClosed: false }),
  search: Object.freeze({ limit: 60, windowMs: 60_000, failClosed: false }),
  plans: Object.freeze({ limit: 120, windowMs: 60_000, failClosed: false }),
  review: Object.freeze({ limit: 5, windowMs: 60 * 60_000, failClosed: true }),
  checkout: Object.freeze({ limit: 10, windowMs: 15 * 60_000, failClosed: true }),
  confirmation: Object.freeze({ limit: 20, windowMs: 15 * 60_000, failClosed: true }),
  // Défense CMS secondaire et non atomique; le limiteur edge/CDN reste requis.
  engagement: Object.freeze({ limit: 60, windowMs: 60_000, failClosed: true }),
});

const PUBLIC_HEADERS = Object.freeze({
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "public, max-age=60, stale-while-revalidate=120",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
});

const PRIVATE_HEADERS = Object.freeze({
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, max-age=0",
  Pragma: "no-cache",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Idempotency-Key",
});

const PLAN_HEADERS = Object.freeze({
  ...PUBLIC_HEADERS,
  "Cache-Control": "public, max-age=3600, stale-while-revalidate=86400",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
});

const getSecretValue = elevate(secrets.getSecretValue);
let stripePromise;
let signingSecretPromise;
let storeSigningKeyringPromise;
let webhookSecretPromise;
let appleStoreVerifierPromise;
let googleStoreVerifierPromise;
let googlePushVerifierPromise;
let googleRtdnSubscriptionPromise;
let storeAllowSandboxPromise;

class PaymentFlowError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = "PaymentFlowError";
    this.code = code;
    this.status = status;
  }
}

class RateLimitError extends Error {
  constructor(retryAfterSeconds) {
    super("RATE_LIMITED");
    this.name = "RateLimitError";
    this.code = "RATE_LIMITED";
    this.status = 429;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

class IdempotencyConflictError extends Error {
  constructor(code) {
    super(code);
    this.name = "IdempotencyConflictError";
    this.code = code;
    this.status = 409;
  }
}

function requestId() {
  return sha256(`${Date.now()}:${Math.random()}`).slice(0, 16);
}

function logFailure(scope, error, correlationId) {
  const errorCode = typeof error?.code === "string" ? error.code : "UNEXPECTED_ERROR";
  console.error(JSON.stringify({
    event: "api_failure",
    scope,
    requestId: correlationId,
    errorCode,
  }));
}

function logEngagementPersistenceRecovery(entry) {
  console.warn(JSON.stringify(entry));
}

function engagementRecoveryErrorCode(error) {
  return isDuplicateInsertError(error) ? "DUPLICATE_INSERT" : "INSERT_ERROR";
}

function jsonResponse(status, body, headers = PRIVATE_HEADERS) {
  const options = { headers: { ...headers }, body };
  if (status === 200) return ok(options);
  if (status === 201) return created(options);
  if (status === 400) return badRequest(options);
  if (status === 403) return forbidden(options);
  if (status === 404) return notFound(options);
  if (status === 500) return serverError(options);
  return response({ ...options, status });
}

function preflightOrMethodNotAllowed(request, headers) {
  if (String(request?.method ?? "").toUpperCase() === "OPTIONS") {
    return jsonResponse(204, null, headers);
  }
  return jsonResponse(405, {
    success: false,
    error: "Méthode non autorisée.",
    code: "METHOD_NOT_ALLOWED",
  }, headers);
}

function publicError(error, correlationId, headers = PRIVATE_HEADERS) {
  if (error instanceof RateLimitError) {
    return jsonResponse(429, {
      success: false,
      error: "Trop de requêtes. Réessayez plus tard.",
      code: error.code,
      requestId: correlationId,
    }, { ...headers, "Retry-After": String(error.retryAfterSeconds) });
  }
  if (error instanceof InputError) {
    const status = error.code === "PAYLOAD_TOO_LARGE" ? 413
      : error.code === "EXISTING_PROFILE_NOT_ALLOWED" ? 403
        : ["STORE_PURCHASE_ALREADY_USED", "STORE_ACCOUNT_REFERENCE_AMBIGUOUS"]
          .includes(error.code) ? 409
        : 400;
    const message = error.code === "LEGACY_FREE_TOKEN_DISABLED"
      ? "Cette confirmation a expiré. Recommencez l'inscription."
      : error.code === "PLAN_CAPABILITY_VIOLATION"
        ? "Le contenu fourni n'est pas inclus dans ce forfait."
        : "Requête invalide.";
    return jsonResponse(
      status,
      { success: false, error: message, code: error.code, requestId: correlationId },
      headers,
    );
  }
  if (error instanceof StoreProviderError) {
    const status = error.code === "GOOGLE_PUSH_UNAUTHORIZED" ? 401
      : error.retryable ? 503
        : 400;
    return jsonResponse(status, {
      success: false,
      error: status === 503
        ? "Le service du magasin est temporairement indisponible."
        : "L'achat du magasin n'a pas pu être validé.",
      code: error.code,
      requestId: correlationId,
    }, headers);
  }
  if (error instanceof DirectoryDatasetLimitError) {
    return jsonResponse(503, {
      success: false,
      error: "Le répertoire est temporairement indisponible.",
      code: error.code,
      requestId: correlationId,
    }, headers);
  }
  if (error instanceof DirectoryPaginationInputError) {
    return jsonResponse(400, {
      success: false,
      error: "Pagination invalide.",
      code: error.code,
      requestId: correlationId,
    }, headers);
  }
  if (error instanceof PaymentFlowError) {
    const message = error.status === 409
      ? "Cette opération a déjà été traitée."
      : error.status === 503
        ? "Le service est temporairement indisponible."
        : "Le paiement ne peut pas être confirmé.";
    return jsonResponse(error.status, {
      success: false,
      error: message,
      code: error.code,
      requestId: correlationId,
    }, headers);
  }
  if (error instanceof IdempotencyConflictError) {
    return jsonResponse(409, {
      success: false,
      error: "Conflit d'idempotence.",
      code: error.code,
      requestId: correlationId,
    }, headers);
  }
  return jsonResponse(500, {
    success: false,
    error: "Une erreur interne est survenue.",
    code: "INTERNAL_ERROR",
    requestId: correlationId,
  }, headers);
}

async function readSecret(name) {
  try {
    const result = await getSecretValue(name);
    const value = typeof result === "string" ? result : result?.value;
    if (typeof value !== "string" || !value) throw new Error("SECRET_NOT_CONFIGURED");
    return value;
  } catch (_error) {
    throw new PaymentFlowError("SERVICE_UNAVAILABLE", 503);
  }
}

async function getSigningSecret() {
  if (!signingSecretPromise) {
    signingSecretPromise = readSecret(CHECKOUT_SIGNING_SECRET_NAME)
      .then((value) => {
        if (Buffer.byteLength(value, "utf8") < 32) {
          throw new PaymentFlowError("SERVICE_UNAVAILABLE", 503);
        }
        return value;
      })
      .catch((error) => {
        signingSecretPromise = undefined;
        throw error;
      });
  }
  return signingSecretPromise;
}

async function getWebhookSecret() {
  if (!webhookSecretPromise) {
    webhookSecretPromise = readSecret(STRIPE_WEBHOOK_SECRET_NAME).catch((error) => {
      webhookSecretPromise = undefined;
      throw error;
    });
  }
  return webhookSecretPromise;
}

async function getStripe() {
  if (!stripePromise) {
    stripePromise = readSecret(STRIPE_SECRET_NAME)
      .then((secretKey) => new Stripe(secretKey))
      .catch((error) => {
        stripePromise = undefined;
        throw error;
      });
  }
  return stripePromise;
}

async function getStoreSigningKeyring() {
  if (!storeSigningKeyringPromise) {
    storeSigningKeyringPromise = Promise.all([
      getSigningSecret(),
      readSecret(CHECKOUT_SIGNING_SECRET_PREVIOUS_NAME),
    ])
      .then(([currentSecret, rawPreviousSecrets]) => {
        if (Buffer.byteLength(rawPreviousSecrets, "utf8") > 16_384) {
          throw new PaymentFlowError("SERVICE_UNAVAILABLE", 503);
        }
        let previousSecrets;
        try {
          previousSecrets = JSON.parse(rawPreviousSecrets);
          return createStoreSigningKeyring(currentSecret, previousSecrets);
        } catch (error) {
          if (error instanceof PaymentFlowError) throw error;
          throw new PaymentFlowError("SERVICE_UNAVAILABLE", 503);
        }
      })
      .catch((error) => {
        storeSigningKeyringPromise = undefined;
        throw error;
      });
  }
  return storeSigningKeyringPromise;
}

async function getAppleStoreVerifier() {
  if (!appleStoreVerifierPromise) {
    appleStoreVerifierPromise = Promise.all([
      ...APPLE_ROOT_CERTIFICATE_SECRET_NAMES.map((name) => readSecret(name)),
      readSecret(APPLE_APP_ID_SECRET_NAME),
    ])
      .then(([
        rootCertificateG1,
        rootCertificateG2,
        rootCertificateG3,
        appAppleId,
      ]) => createAppleTransactionVerifier({
        rootCertificates: [rootCertificateG1, rootCertificateG2, rootCertificateG3],
        appAppleId,
      }))
      .catch((error) => {
        appleStoreVerifierPromise = undefined;
        throw error;
      });
  }
  return appleStoreVerifierPromise;
}

async function getGoogleStoreVerifier() {
  if (!googleStoreVerifierPromise) {
    googleStoreVerifierPromise = readSecret(GOOGLE_PLAY_SERVICE_ACCOUNT_SECRET_NAME)
      .then((serviceAccount) => createGoogleSubscriptionVerifier({ serviceAccount }))
      .catch((error) => {
        googleStoreVerifierPromise = undefined;
        throw error;
      });
  }
  return googleStoreVerifierPromise;
}

async function getGooglePushVerifier() {
  if (!googlePushVerifierPromise) {
    googlePushVerifierPromise = Promise.all([
      readSecret(GOOGLE_RTDN_AUDIENCE_SECRET_NAME),
      readSecret(GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL_SECRET_NAME),
    ])
      .then(([audience, serviceAccountEmail]) => createGooglePushTokenVerifier({
        audience,
        serviceAccountEmail,
      }))
      .catch((error) => {
        googlePushVerifierPromise = undefined;
        throw error;
      });
  }
  return googlePushVerifierPromise;
}

async function getGoogleRtdnSubscription() {
  if (!googleRtdnSubscriptionPromise) {
    googleRtdnSubscriptionPromise = readSecret(GOOGLE_RTDN_SUBSCRIPTION_SECRET_NAME)
      .catch((error) => {
        googleRtdnSubscriptionPromise = undefined;
        throw error;
      });
  }
  return googleRtdnSubscriptionPromise;
}

async function getStoreAllowSandbox() {
  if (!storeAllowSandboxPromise) {
    storeAllowSandboxPromise = getSecretValue(STORE_ALLOW_SANDBOX_SECRET_NAME)
      .then((result) => {
        const value = typeof result === "string" ? result : result?.value;
        return value === "true";
      })
      .catch(() => false);
  }
  return storeAllowSandboxPromise;
}

function sandboxPolicy(dependencies) {
  return Object.hasOwn(dependencies, "allowSandbox")
    ? Promise.resolve(dependencies.allowSandbox === true)
    : getStoreAllowSandbox();
}

function requestHeader(request, name) {
  const headers = request?.headers;
  if (!headers || typeof headers !== "object") return "";
  const expected = name.toLowerCase();
  for (const [headerName, value] of Object.entries(headers)) {
    if (headerName.toLowerCase() === expected) return String(value ?? "");
  }
  return "";
}

async function readJsonBody(request) {
  const contentType = requestHeader(request, "content-type").toLowerCase();
  if (contentType && !contentType.includes("application/json")) {
    throw new InputError("INVALID_CONTENT_TYPE");
  }
  const contentLength = Number(requestHeader(request, "content-length") || 0);
  if (Number.isFinite(contentLength) && contentLength > 512 * 1024) {
    throw new InputError("PAYLOAD_TOO_LARGE");
  }
  let body;
  try {
    body = await request.body.json();
  } catch (_error) {
    throw new InputError("INVALID_JSON");
  }
  validateRequestSize(body);
  return body;
}

async function readLimitedJsonBody(request, maxBytes) {
  const contentLength = Number(requestHeader(request, "content-length") || 0);
  if (
    !Number.isSafeInteger(maxBytes)
    || maxBytes < 1
    || (Number.isFinite(contentLength) && contentLength > maxBytes)
  ) {
    throw new InputError("PAYLOAD_TOO_LARGE");
  }
  const body = await readJsonBody(request);
  if (Buffer.byteLength(JSON.stringify(body), "utf8") > maxBytes) {
    throw new InputError("PAYLOAD_TOO_LARGE");
  }
  return body;
}

async function findById(collection, id, { consistentRead = false } = {}) {
  const options = consistentRead ? CONSISTENT_DATA_OPTIONS : DATA_OPTIONS;
  const result = await wixData.query(collection).eq("_id", id).limit(1).find(options);
  return result.items[0] ?? null;
}

function isDuplicateInsertError(error) {
  const code = String(error?.code ?? "");
  const message = String(error?.message ?? "").toLowerCase();
  return code === "WDE0074" || message.includes("already exists") || message.includes("existe déjà");
}

function isStripeResourceMissing(error) {
  return error?.code === "resource_missing" || error?.raw?.code === "resource_missing";
}

async function consumeRateLimit(request, scope, correlationId) {
  // Wix Data persists the counter across warm instances, but its read/update
  // sequence is not an atomic increment. Keep an edge/CDN limiter in front of
  // these routes when strict burst enforcement is required in production.
  const config = RATE_LIMITS[scope];
  if (!config) throw new Error("RATE_LIMIT_CONFIG_NOT_FOUND");
  try {
    const signingSecret = await getSigningSecret();
    const ip = String(request?.ip ?? "unknown").slice(0, 128);
    const keyHash = sha256(`${scope}:${ip}:${signingSecret}`);
    const id = `rtl_${keyHash.slice(0, 32)}`;
    let existing = await findById(RATE_LIMIT_COLLECTION, id, { consistentRead: true });

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const decision = evaluateRateLimit(existing, Date.now(), config);
      const record = {
        ...(existing ?? {}),
        _id: id,
        scope,
        keyHash,
        count: decision.count,
        limit: decision.limit,
        windowStartedAtMs: decision.windowStartedAtMs,
        expiresAt: decision.expiresAt,
      };
      try {
        if (existing) await wixData.update(RATE_LIMIT_COLLECTION, record, DATA_OPTIONS);
        else await wixData.insert(RATE_LIMIT_COLLECTION, record, DATA_OPTIONS);
        if (!decision.allowed) throw new RateLimitError(decision.retryAfterSeconds);
        return;
      } catch (error) {
        if (!existing && isDuplicateInsertError(error)) {
          existing = await findById(RATE_LIMIT_COLLECTION, id, { consistentRead: true });
          continue;
        }
        throw error;
      }
    }
    throw new Error("RATE_LIMIT_CONFLICT");
  } catch (error) {
    if (error instanceof RateLimitError) throw error;
    logFailure(`rate_limit_${scope}`, error, correlationId);
    if (config.failClosed) throw new PaymentFlowError("RATE_LIMIT_UNAVAILABLE", 503);
  }
}

async function persistCheckoutDraft(draft) {
  const existing = await findById(CHECKOUT_COLLECTION, draft._id, { consistentRead: true });
  if (existing) {
    if (existing.fingerprint !== draft.fingerprint || existing.planId !== draft.planId) {
      throw new PaymentFlowError("CHECKOUT_CONFLICT", 409);
    }
    return { item: existing, created: false };
  }
  try {
    const inserted = await wixData.insert(CHECKOUT_COLLECTION, draft, DATA_OPTIONS);
    return { item: inserted, created: true };
  } catch (error) {
    let raced;
    try {
      raced = await findById(CHECKOUT_COLLECTION, draft._id, { consistentRead: true });
    } catch (_readError) {
      const uncertain = new PaymentFlowError("CHECKOUT_PERSISTENCE_UNCERTAIN", 503);
      uncertain.preserveUploadedMedia = true;
      throw uncertain;
    }
    if (raced?.fingerprint === draft.fingerprint && raced?.planId === draft.planId) {
      return { item: raced, created: false };
    }
    if (raced || isDuplicateInsertError(error)) {
      throw new PaymentFlowError("CHECKOUT_CONFLICT", 409);
    }
    // Une écriture ayant échoué après son commit ne peut pas être distinguée
    // avec certitude d'un échec avant commit. Conserver le média est plus sûr
    // que casser un checkout éventuellement créé; un nettoyage différé pourra
    // traiter cet éventuel orphelin.
    const uncertain = new PaymentFlowError("CHECKOUT_PERSISTENCE_UNCERTAIN", 503);
    uncertain.preserveUploadedMedia = true;
    throw uncertain;
  }
}

async function persistEntitlementRecord(record) {
  const existing = await findById(ENTITLEMENT_COLLECTION, record._id, { consistentRead: true });
  const decision = reconcileEntitlement(existing, record);
  if (decision.action === "unchanged") {
    return { item: decision.item, idempotent: true };
  }
  try {
    const saved = decision.action === "insert"
      ? await wixData.insert(ENTITLEMENT_COLLECTION, decision.item, DATA_OPTIONS)
      : await wixData.update(ENTITLEMENT_COLLECTION, decision.item, DATA_OPTIONS);
    return { item: saved, idempotent: false };
  } catch (_error) {
    let raced;
    try {
      raced = await findById(ENTITLEMENT_COLLECTION, record._id, { consistentRead: true });
    } catch (_readError) {
      throw new PaymentFlowError("ENTITLEMENT_PERSISTENCE_UNCERTAIN", 503);
    }
    if (!raced) throw new PaymentFlowError("ENTITLEMENT_PERSISTENCE_UNCERTAIN", 503);
    const recovered = reconcileEntitlement(raced, record);
    if (recovered.action === "unchanged") {
      return { item: recovered.item, idempotent: true };
    }
    throw new PaymentFlowError("ENTITLEMENT_PERSISTENCE_UNCERTAIN", 503);
  }
}

async function findStoreCheckoutsByAccountReference({
  accountReferenceHash,
  store,
  productId,
}) {
  if (!/^[a-f0-9]{64}$/u.test(accountReferenceHash ?? "")) {
    throw new InputError("INVALID_STORE_CHECKOUT");
  }
  let query = wixData.query(CHECKOUT_COLLECTION)
    .eq("accountReferenceHash", accountReferenceHash)
    .eq("store", store);
  if (productId !== undefined) query = query.eq("storeProductId", productId);
  const result = await query.limit(2).find(CONSISTENT_DATA_OPTIONS);
  return Array.isArray(result?.items) ? result.items : [];
}

async function findStoreEntitlementsByCurrentTransactionHash({ currentTransactionHash }) {
  if (!/^[a-f0-9]{64}$/u.test(currentTransactionHash ?? "")) {
    throw new InputError("INVALID_ENTITLEMENT");
  }
  const result = await wixData.query(ENTITLEMENT_COLLECTION)
    .eq("currentTransactionHash", currentTransactionHash)
    .limit(2)
    .find(CONSISTENT_DATA_OPTIONS);
  return Array.isArray(result?.items) ? result.items : [];
}

function assertStoreEventBinding(existing, incoming) {
  if (
    !existing
    || existing._id !== incoming._id
    || existing.provider !== incoming.provider
    || existing.sourceEventHash !== incoming.sourceEventHash
    || existing.entitlementId !== incoming.entitlementId
  ) {
    throw new PaymentFlowError("STORE_EVENT_CONFLICT", 409);
  }
  return existing;
}

async function beginStoreEventRecord(record) {
  const existing = await findById(STORE_EVENT_COLLECTION, record._id, { consistentRead: true });
  if (existing) return { item: assertStoreEventBinding(existing, record), idempotent: true };
  try {
    const inserted = await wixData.insert(STORE_EVENT_COLLECTION, record, DATA_OPTIONS);
    return { item: inserted, idempotent: false };
  } catch (_error) {
    let raced;
    try {
      raced = await findById(STORE_EVENT_COLLECTION, record._id, { consistentRead: true });
    } catch (_readError) {
      throw new PaymentFlowError("STORE_EVENT_PERSISTENCE_UNCERTAIN", 503);
    }
    if (!raced) throw new PaymentFlowError("STORE_EVENT_PERSISTENCE_UNCERTAIN", 503);
    return { item: assertStoreEventBinding(raced, record), idempotent: true };
  }
}

async function completeStoreEventRecord(existing, patch) {
  if (
    !existing
    || !["processed", "ignored"].includes(patch?.status)
    || typeof patch.processedAt !== "string"
    || typeof patch.outcome !== "string"
    || patch.outcome.length > 80
  ) {
    throw new PaymentFlowError("INVALID_STORE_EVENT", 500);
  }
  if (existing.status === patch.status && existing.outcome === patch.outcome) return existing;
  return wixData.update(
    STORE_EVENT_COLLECTION,
    { ...existing, ...patch, _id: existing._id },
    DATA_OPTIONS,
  );
}

export async function persistEngagementEvent(record, {
  findExisting = (id) => findById(ENGAGEMENT_COLLECTION, id, { consistentRead: true }),
  insertRecord = (item) => wixData.insert(ENGAGEMENT_COLLECTION, item, DATA_OPTIONS),
  logRecovered = logEngagementPersistenceRecovery,
} = {}) {
  const existing = await findExisting(record._id);
  if (existing) {
    if (existing.contentHash !== record.contentHash) {
      throw new IdempotencyConflictError("ENGAGEMENT_EVENT_CONFLICT");
    }
    return { duplicate: true };
  }

  try {
    await insertRecord(record);
    return { duplicate: false };
  } catch (_insertError) {
    let raced;
    try {
      raced = await findExisting(record._id);
    } catch (_readError) {
      throw new PaymentFlowError("ENGAGEMENT_PERSISTENCE_UNCERTAIN", 503);
    }
    if (raced?.contentHash === record.contentHash) {
      try {
        logRecovered({
          event: "engagement_persistence_recovered",
          recordId: record._id,
          eventType: record.type,
          errorCode: engagementRecoveryErrorCode(_insertError),
        });
      } catch (_loggingError) {
        // L'observabilité ne doit jamais transformer une écriture récupérée en échec client.
      }
      return { duplicate: true };
    }
    if (raced) throw new IdempotencyConflictError("ENGAGEMENT_EVENT_CONFLICT");
    throw new PaymentFlowError("ENGAGEMENT_PERSISTENCE_UNCERTAIN", 503);
  }
}

async function updateCheckout(checkout, patch) {
  return wixData.update(CHECKOUT_COLLECTION, { ...checkout, ...patch, _id: checkout._id }, DATA_OPTIONS);
}

function validateStoredCheckout(checkout) {
  if (!checkout || checkout.version !== 2 || !/^chk_[a-f0-9]{32}$/u.test(checkout._id)) {
    throw new PaymentFlowError("CHECKOUT_NOT_FOUND", 400);
  }
  try {
    return validatePersistedCheckout(checkout);
  } catch (error) {
    if (!(error instanceof InputError)) throw error;
    throw new PaymentFlowError("CHECKOUT_INTEGRITY_ERROR", 409);
  }
}

function lower(value) {
  return directorySearchText(value).toLocaleLowerCase("fr-CA");
}

function contains(value, query) {
  return lower(value).includes(lower(query));
}

function professionalMatches(professional, filters) {
  const { search, category, city } = filters;
  if (search) {
    const fields = [
      professional.title,
      professional.category,
      professional.sousCategorie,
      professional.sousCatgorie,
      professional.subtitle,
      professional.description,
      professional.speciality,
      professional.address,
    ];
    if (!fields.some((field) => contains(field, search))) return false;
  }
  if (category) {
    const expected = lower(category);
    const actual = [professional.category, professional.sousCategorie, professional.sousCatgorie]
      .map(lower);
    if (!actual.includes(expected)) return false;
  }
  return !city || contains(professional.ville, city) || contains(professional.address, city);
}

function searchScore(professional, query) {
  const scoreField = (value, weight) => {
    const text = lower(value);
    const target = lower(query);
    if (!text || !target) return 0;
    if (text === target) return 100 * weight;
    const words = text.split(/\s+/u);
    if (words.includes(target)) return 90 * weight;
    if (words.some((word) => word.startsWith(target))) return 80 * weight;
    if (text.startsWith(target)) return 70 * weight;
    if (text.includes(target)) return 50 * weight;
    return 0;
  };
  return scoreField(professional.title, 2)
    + scoreField(professional.category, 1.5)
    + scoreField(professional.sousCategorie ?? professional.sousCatgorie, 1.5)
    + scoreField(professional.speciality, 1)
    + scoreField(professional.subtitle ?? professional.description, 0.5)
    + scoreField(professional.address, 0.25);
}

function activeProfessionalsQuery() {
  return wixData.query("Professionnel").eq("isActive", true);
}

function combineOrQueries(queries) {
  if (!Array.isArray(queries) || queries.length === 0) {
    throw new Error("DIRECTORY_QUERY_REQUIRED");
  }
  return queries.slice(1).reduce((combined, query) => combined.or(query), queries[0]);
}

function publicReviewsQuery(professionalId = "") {
  const visibilityQuery = combineOrQueries([
    wixData.query("Reviews").eq("isApproved", true),
    wixData.query("Reviews").eq("moderationStatus", "approved"),
  ]);
  if (!professionalId) return visibilityQuery;
  const associationQuery = combineOrQueries(
    ["professionalId", "professionnelId", "image"]
      .map((field) => wixData.query("Reviews").eq(field, professionalId)),
  );
  return visibilityQuery.and(associationQuery);
}

function publicPartnersQuery() {
  return wixData.query("Partenaires")
    .eq("isActive", true)
    .eq("isOfficial", true);
}

function publicOffersQuery() {
  return wixData.query("OffresPartenaire").eq("isActive", true);
}

function publicCategoriesQuery() {
  return wixData.query("SousCategorie");
}

async function loadDirectoryData() {
  return Promise.all([
    collectAllPages(
      activeProfessionalsQuery().ascending("_id").limit(1000).find(DATA_OPTIONS),
      { collection: "Professionnel" },
    ),
    collectAllPages(
      publicCategoriesQuery().ascending("_id").limit(1000).find(DATA_OPTIONS),
      { collection: "SousCategorie" },
    ),
    collectAllPages(
      publicReviewsQuery().ascending("_id").limit(1000).find(DATA_OPTIONS),
      { collection: "Reviews" },
    ),
    collectAllPages(
      publicPartnersQuery().ascending("_id").limit(1000).find(DATA_OPTIONS),
      { collection: "Partenaires" },
    ),
    collectAllPages(
      publicOffersQuery().ascending("_id").limit(1000).find(DATA_OPTIONS),
      { collection: "OffresPartenaire" },
    ),
  ]);
}

export async function get_data(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "directory", correlationId);
    const filters = normalizeSearchParams(request?.query ?? {});
    const [professionalsResult, subCategoriesResult, reviewsResult, partnersResult, offersResult]
      = await loadDirectoryData();
    const activeProfessionals = professionalsResult.items
      .filter((item) => isProfessionalPubliclyVisible(item))
      .filter((item) => professionalMatches(item, filters));
    return jsonResponse(200, {
      professionnels: activeProfessionals.map(toPublicProfessional),
      sousCategories: subCategoriesResult.items
        .filter(isCategoryEnabled)
        .map(toPublicSubCategory),
      reviews: reviewsResult.items
        .filter(isReviewPublic)
        .map(toPublicReview),
      partenaires: partnersResult.items
        .filter((item) => item.isActive === true && item.isOfficial === true)
        .map(toPublicPartner),
      offres: offersResult.items.filter((item) => item.isActive === true).map(toPublicOffer),
      searchStats: {
        totalProfessionnels: professionalsResult.items.filter(
          (item) => isProfessionalPubliclyVisible(item),
        ).length,
        filteredProfessionnels: activeProfessionals.length,
      },
    }, PUBLIC_HEADERS);
  } catch (error) {
    logFailure("get_data", error, correlationId);
    return publicError(error, correlationId, PUBLIC_HEADERS);
  }
}

export function use_data(request) {
  return preflightOrMethodNotAllowed(request, PUBLIC_HEADERS);
}

export async function get_searchProfessionals(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "search", correlationId);
    const filters = normalizeSearchParams(request?.query ?? {});
    if (!filters.search && !filters.category && !filters.city) {
      throw new InputError("SEARCH_CRITERION_REQUIRED");
    }
    const result = await collectAllPages(
      activeProfessionalsQuery().ascending("_id").limit(1000).find(DATA_OPTIONS),
      { collection: "Professionnel" },
    );
    let professionals = result.items
      .filter((item) => isProfessionalPubliclyVisible(item))
      .filter((item) => professionalMatches(item, filters));
    if (filters.search) {
      professionals = professionals
        .map((item) => ({ ...item, searchScore: searchScore(item, filters.search) }))
        .filter((item) => item.searchScore > 0)
        .sort((left, right) => right.searchScore - left.searchScore);
    }
    const limited = professionals.slice(0, filters.limit);
    return jsonResponse(200, {
      success: true,
      professionnels: limited.map((item) => ({
        ...toPublicProfessional(item),
        ...(typeof item.searchScore === "number" ? { searchScore: item.searchScore } : {}),
      })),
      searchStats: { totalFound: professionals.length, returned: limited.length },
    }, PUBLIC_HEADERS);
  } catch (error) {
    logFailure("get_searchProfessionals", error, correlationId);
    return publicError(error, correlationId, PUBLIC_HEADERS);
  }
}

export function use_searchProfessionals(request) {
  return preflightOrMethodNotAllowed(request, PUBLIC_HEADERS);
}

// Compatibilité transitoire avec l'ancienne URL snake_case. La route publique
// documentée et canonique reste /_functions/searchProfessionals.
export function get_search_professionals(request) {
  return get_searchProfessionals(request);
}

export function use_search_professionals(request) {
  return use_searchProfessionals(request);
}

function publicPagination(page) {
  return {
    limit: page.pagination.limit,
    has_more: page.pagination.hasMore,
    next_cursor: page.pagination.nextCursor,
  };
}

async function queryDirectoryPage(query, pageRequest) {
  let pagedQuery = query;
  if (pageRequest.lastId) pagedQuery = pagedQuery.gt("_id", pageRequest.lastId);
  return pagedQuery
    .ascending("_id")
    .limit(pageRequest.limit + 1)
    .find(DATA_OPTIONS);
}

async function queryFilteredProfessionalPage(query, pageRequest, isVisible) {
  const chunkSize = 1000;
  const maxItems = DIRECTORY_COLLECTION_LIMITS.Professionnel;
  const matches = [];
  let lastScannedId = pageRequest.lastId;
  let scannedCount = 0;
  let pageCount = 0;

  while (matches.length <= pageRequest.limit) {
    let pagedQuery = query;
    if (lastScannedId) pagedQuery = pagedQuery.gt("_id", lastScannedId);
    const result = await pagedQuery
      .ascending("_id")
      .limit(chunkSize)
      .find(DATA_OPTIONS);
    pageCount += 1;
    if (!result || !Array.isArray(result.items)) {
      throw new TypeError("Page Wix invalide pour la collection Professionnel");
    }
    if (result.items.length === 0) break;

    for (const item of result.items) {
      if (!item || typeof item._id !== "string" || !item._id) {
        throw new TypeError("Identifiant Wix invalide pour la collection Professionnel");
      }
      lastScannedId = item._id;
      scannedCount += 1;
      if (isVisible(item)) matches.push(item);
      if (matches.length > pageRequest.limit) break;
    }
    if (matches.length > pageRequest.limit) break;

    const hasMore = typeof result.hasNext === "function"
      ? Boolean(await result.hasNext())
      : result.items.length === chunkSize;
    if (!hasMore) break;
    if (scannedCount >= maxItems) {
      throw new DirectoryDatasetLimitError({
        collection: "Professionnel",
        maxItems,
        itemCount: scannedCount,
        minimumItemCount: scannedCount + 1,
        pageCount,
      });
    }
  }
  return { items: matches };
}

function professionalDirectoryFieldQuery(fields, method, value) {
  return combineOrQueries(fields.map((field) => wixData.query("Professionnel")[method](field, value)));
}

function professionalDirectoryQuery(filters) {
  let query = activeProfessionalsQuery();
  if (filters.featured !== null) query = query.eq("sponsor", filters.featured);
  if (filters.ids.length > 0) query = query.hasSome("_id", filters.ids);
  if (filters.category) {
    query = query.and(professionalDirectoryFieldQuery(
      ["category", "sousCategorie", "sousCatgorie"],
      "eq",
      filters.category,
    ));
  }
  return query;
}

function professionalDirectoryMatches(item, filters) {
  if (!isProfessionalPubliclyVisible(item) || !professionalMatches(item, filters)) return false;
  if (filters.featured !== null && item.sponsor !== filters.featured) return false;
  return filters.ids.length === 0 || filters.ids.includes(item._id);
}

export async function get_categories(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "directory", correlationId);
    const filterKey = "enabled-categories-v2";
    const pageRequest = normalizeDirectoryPageRequest(request?.query ?? {}, {
      collection: "SousCategorie",
      filterKey,
    });
    const result = await queryDirectoryPage(publicCategoriesQuery(), pageRequest);
    const page = buildDirectoryPage(result.items, {
      collection: "SousCategorie",
      filterKey,
      limit: pageRequest.limit,
      isVisible: isCategoryEnabled,
      project: toPublicSubCategory,
    });
    return jsonResponse(200, {
      success: true,
      version: 2,
      categories: page.items,
      pagination: publicPagination(page),
    }, PUBLIC_HEADERS);
  } catch (error) {
    logFailure("get_categories", error, correlationId);
    return publicError(error, correlationId, PUBLIC_HEADERS);
  }
}

export function use_categories(request) {
  return preflightOrMethodNotAllowed(request, PUBLIC_HEADERS);
}

export async function get_professionals(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "search", correlationId);
    const normalizedSearch = normalizeSearchParams({
      search: request?.query?.search,
      category: request?.query?.category,
      city: request?.query?.city,
    });
    const filters = Object.freeze({
      ...normalizedSearch,
      featured: normalizeFeaturedFilter(request?.query?.featured),
      ids: normalizeProfessionalIdsFilter(request?.query?.ids),
    });
    const filterKey = JSON.stringify({
      search: filters.search,
      category: filters.category,
      city: filters.city,
      featured: filters.featured,
      ids: filters.ids,
    });
    const pageRequest = normalizeDirectoryPageRequest(request?.query ?? {}, {
      collection: "Professionnel",
      filterKey,
    });
    const visibilityFilter = (item) => professionalDirectoryMatches(item, filters);
    const result = await queryFilteredProfessionalPage(
      professionalDirectoryQuery(filters),
      pageRequest,
      visibilityFilter,
    );
    const page = buildDirectoryPage(result.items, {
      collection: "Professionnel",
      filterKey,
      limit: pageRequest.limit,
      isVisible: visibilityFilter,
      project: (item) => {
        const projected = toPublicProfessional(item);
        return filters.search
          ? { ...projected, searchScore: searchScore(item, filters.search) }
          : projected;
      },
    });
    return jsonResponse(200, {
      success: true,
      version: 2,
      professionals: page.items,
      pagination: publicPagination(page),
    }, PUBLIC_HEADERS);
  } catch (error) {
    logFailure("get_professionals", error, correlationId);
    return publicError(error, correlationId, PUBLIC_HEADERS);
  }
}

export function use_professionals(request) {
  return preflightOrMethodNotAllowed(request, PUBLIC_HEADERS);
}

export async function get_reviews(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "directory", correlationId);
    const legacyPath = request?.path;
    if (Array.isArray(legacyPath) && legacyPath.length > 1) {
      throw new InputError("INVALID_SEARCH");
    }
    const candidates = [
      request?.query?.professionalId,
      request?.query?.professionnelId,
      Array.isArray(legacyPath) ? legacyPath[0] : undefined,
    ].filter((candidate) => candidate !== undefined && candidate !== null);
    if (candidates.length > 1 && candidates.some((candidate) => candidate !== candidates[0])) {
      throw new InputError("INVALID_SEARCH");
    }
    const professionalId = normalizeProfessionalIdFilter(candidates[0]);
    const professional = await findById("Professionnel", professionalId, { consistentRead: true });
    if (!isProfessionalPubliclyVisible(professional)) {
      return jsonResponse(404, {
        success: false,
        error: "Professionnel introuvable.",
        code: "PROFESSIONAL_NOT_FOUND",
        requestId: correlationId,
      }, PUBLIC_HEADERS);
    }
    const filterKey = JSON.stringify({ professionalId });
    const pageRequest = normalizeDirectoryPageRequest(request?.query ?? {}, {
      collection: "Reviews",
      filterKey,
    });
    const result = await queryDirectoryPage(publicReviewsQuery(professionalId), pageRequest);
    const page = buildDirectoryPage(result.items, {
      collection: "Reviews",
      filterKey,
      limit: pageRequest.limit,
      isVisible: (item) => (
        reviewProfessionalId(item) === professionalId && isReviewPublic(item)
      ),
      project: toPublicReview,
    });
    return jsonResponse(200, {
      success: true,
      version: 2,
      reviews: page.items,
      pagination: publicPagination(page),
    }, PUBLIC_HEADERS);
  } catch (error) {
    logFailure("get_reviews", error, correlationId);
    return publicError(error, correlationId, PUBLIC_HEADERS);
  }
}

export function use_reviews(request) {
  return preflightOrMethodNotAllowed(request, PUBLIC_HEADERS);
}

export async function get_partners(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "directory", correlationId);
    const filterKey = "active-official-partners-v2";
    const pageRequest = normalizeDirectoryPageRequest(request?.query ?? {}, {
      collection: "Partenaires",
      filterKey,
    });
    const result = await queryDirectoryPage(publicPartnersQuery(), pageRequest);
    const page = buildDirectoryPage(result.items, {
      collection: "Partenaires",
      filterKey,
      limit: pageRequest.limit,
      isVisible: (item) => item.isActive === true && item.isOfficial === true,
      project: toPublicPartner,
    });
    return jsonResponse(200, {
      success: true,
      version: 2,
      partners: page.items,
      pagination: publicPagination(page),
    }, PUBLIC_HEADERS);
  } catch (error) {
    logFailure("get_partners", error, correlationId);
    return publicError(error, correlationId, PUBLIC_HEADERS);
  }
}

export function use_partners(request) {
  return preflightOrMethodNotAllowed(request, PUBLIC_HEADERS);
}

export async function get_offers(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "directory", correlationId);
    const filterKey = "active-partner-offers-v2";
    const pageRequest = normalizeDirectoryPageRequest(request?.query ?? {}, {
      collection: "OffresPartenaire",
      filterKey,
    });
    const result = await queryDirectoryPage(publicOffersQuery(), pageRequest);
    const page = buildDirectoryPage(result.items, {
      collection: "OffresPartenaire",
      filterKey,
      limit: pageRequest.limit,
      isVisible: (item) => item.isActive === true,
      project: toPublicOffer,
    });
    return jsonResponse(200, {
      success: true,
      version: 2,
      offers: page.items,
      pagination: publicPagination(page),
    }, PUBLIC_HEADERS);
  } catch (error) {
    logFailure("get_offers", error, correlationId);
    return publicError(error, correlationId, PUBLIC_HEADERS);
  }
}

export function use_offers(request) {
  return preflightOrMethodNotAllowed(request, PUBLIC_HEADERS);
}

export async function get_paymentPlans(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "plans", correlationId);
    return jsonResponse(200, { success: true, version: 2, plans: projectPaymentPlans() }, PLAN_HEADERS);
  } catch (error) {
    logFailure("get_paymentPlans", error, correlationId);
    return publicError(error, correlationId, PLAN_HEADERS);
  }
}

export function use_paymentPlans(request) {
  return preflightOrMethodNotAllowed(request, PLAN_HEADERS);
}

export async function post_review(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "review", correlationId);
    const body = await readJsonBody(request);
    const review = normalizeReviewInput(body);
    const professional = await findById("Professionnel", review.professionalId, { consistentRead: true });
    if (!isProfessionalPubliclyVisible(professional)) {
      return jsonResponse(404, {
        success: false,
        error: "Professionnel introuvable.",
        code: "PROFESSIONAL_NOT_FOUND",
        requestId: correlationId,
      });
    }
    const createdAt = new Date();
    const result = await wixData.insert("Reviews", {
      title: review.title,
      professionalId: review.professionalId,
      message: review.message,
      rating: review.rating,
      auteurNom: review.auteurNom,
      dateCreation: createdAt,
      dateCreationFormatted: new Intl.DateTimeFormat("fr-CA", {
        day: "2-digit",
        month: "long",
        year: "numeric",
      }).format(createdAt),
      moderationStatus: "pending",
      isApproved: false,
    }, DATA_OPTIONS);
    return jsonResponse(201, {
      success: true,
      id: result._id,
      status: "pending_review",
      message: "Avis reçu et soumis à modération.",
    });
  } catch (error) {
    logFailure("post_review", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_review(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

export async function post_engagementEvent(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "engagement", correlationId);
    const body = await readJsonBody(request);
    const record = buildEngagementEventRecord(body, new Date());

    if (record.professionalId) {
      const professional = await findById(
        "Professionnel",
        record.professionalId,
        { consistentRead: true },
      );
      if (!isProfessionalPubliclyVisible(professional)) {
        return jsonResponse(404, {
          success: false,
          error: "Professionnel introuvable.",
          code: "PROFESSIONAL_NOT_FOUND",
          requestId: correlationId,
        });
      }
    }

    const persisted = await persistEngagementEvent(record);
    if (persisted.duplicate) {
      return jsonResponse(200, { success: true, duplicate: true });
    }
    return jsonResponse(201, { success: true, received: true });
  } catch (error) {
    logFailure("post_engagementEvent", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_engagementEvent(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

function assertClientHints(body, plan) {
  if (body.amount !== undefined && Number(body.amount) !== plan.amountCents) {
    throw new InputError("PAYMENT_PARAMETER_MISMATCH");
  }
  if (body.currency !== undefined && String(body.currency).toLowerCase() !== plan.currency) {
    throw new InputError("PAYMENT_PARAMETER_MISMATCH");
  }
}

function checkoutResponse(checkout, plan, extra = {}) {
  return {
    success: true,
    checkout_id: checkout._id,
    requires_payment: plan.requiresPayment,
    amount: plan.amountCents,
    currency: plan.currency,
    ...extra,
  };
}

async function retrieveExistingPaymentIntent(stripe, checkout) {
  if (!checkout.paymentIntentId) return null;
  try {
    return await stripe.paymentIntents.retrieve(checkout.paymentIntentId);
  } catch (_error) {
    // Never create a second charge merely because Stripe retrieval was
    // temporarily unavailable. Stripe PaymentIntents are not deletable.
    throw new PaymentFlowError("STRIPE_UNAVAILABLE", 503);
  }
}

function storeCheckoutResponse(checkout, accountToken, extra = {}) {
  return {
    success: true,
    checkout_id: checkout._id,
    store: checkout.store,
    product_id: checkout.storeProductId,
    account_token: accountToken,
    requires_payment: true,
    ...extra,
  };
}

export async function post_createStoreCheckout(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "checkout", correlationId);
    const body = await readJsonBody(request);
    const signingKeyring = await getStoreSigningKeyring();
    const draft = createStoreCheckoutDraft(body, signingKeyring);
    const plan = getPlan(draft.planId);
    assertClientHints(body, plan);
    let checkout = await getOrCreatePersistedCheckout(draft, correlationId);
    validateStoredCheckout(checkout);
    validateStoreCheckout(checkout);
    const accountToken = deriveStoreAccountToken(checkout, signingKeyring);

    if (checkout.status === "finalized" && checkout.professionalId) {
      return jsonResponse(200, storeCheckoutResponse(checkout, accountToken, {
        already_finalized: true,
        complete_purchase: true,
        professional_id: checkout.professionalId,
        entitlement_id: checkout.entitlementId,
      }));
    }

    assertCheckoutNotExpired(checkout);
    if (checkout.status === "created") {
      checkout = await updateCheckout(checkout, { status: "store_purchase_pending" });
    }
    return jsonResponse(200, storeCheckoutResponse(checkout, accountToken));
  } catch (error) {
    logFailure("post_createStoreCheckout", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_createStoreCheckout(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

export async function post_createPaymentIntent(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "checkout", correlationId);
    const body = await readJsonBody(request);
    const draft = createCheckoutDraft(body);
    const plan = getPlan(draft.planId);
    assertClientHints(body, plan);
    let checkout = await getOrCreatePersistedCheckout(draft, correlationId);
    validateStoredCheckout(checkout);
    const expectedProvider = plan.requiresPayment ? "stripe" : "free";
    if ((checkout.paymentProvider ?? expectedProvider) !== expectedProvider) {
      throw new PaymentFlowError("CHECKOUT_PROVIDER_MISMATCH", 409);
    }

    if (checkout.status === "finalized" && checkout.professionalId) {
      return jsonResponse(200, checkoutResponse(checkout, plan, {
        already_finalized: true,
        professional_id: checkout.professionalId,
      }));
    }

    if (!checkout.paymentIntentId) assertCheckoutNotExpired(checkout);

    if (!plan.requiresPayment) {
      const signingSecret = await getSigningSecret();
      const confirmation = createFreeCheckoutToken(checkout, signingSecret);
      if (checkout.status === "created") {
        checkout = await updateCheckout(checkout, { status: "awaiting_confirmation" });
      }
      return jsonResponse(200, checkoutResponse(checkout, plan, {
        id: confirmation.token,
        payment_intent_id: confirmation.token,
        confirmation_token: confirmation.token,
        expires_at: confirmation.expiresAt,
      }));
    }

    const stripe = await getStripe();
    const existingIntent = await retrieveExistingPaymentIntent(stripe, checkout);
    if (existingIntent) validatePaymentIntentBinding(existingIntent, checkout);
    if (existingIntent?.status === "succeeded") {
      const finalized = await finalizePaidPaymentIntent(existingIntent);
      return jsonResponse(200, checkoutResponse(finalized.checkout, plan, {
        already_finalized: true,
        professional_id: finalized.professional._id,
        id: existingIntent.id,
        payment_intent_id: existingIntent.id,
      }));
    }
    if (existingIntent && existingIntent.status !== "canceled") {
      if (!existingIntent?.client_secret) {
        throw new PaymentFlowError("STRIPE_UNAVAILABLE", 503);
      }
      return jsonResponse(200, checkoutResponse(checkout, plan, {
        id: existingIntent.id,
        payment_intent_id: existingIntent.id,
        client_secret: existingIntent.client_secret,
      }));
    }

    assertCheckoutNotExpired(checkout);

    const paymentAttempt = Number(checkout.paymentAttempt ?? 0) + 1;
    let paymentIntent;
    try {
      paymentIntent = await stripe.paymentIntents.create({
        amount: plan.amountCents,
        currency: plan.currency,
        automatic_payment_methods: { enabled: true },
        receipt_email: checkout.registration.email,
        description: `Index Canada - forfait ${plan.id}`,
        metadata: {
          checkoutVersion: CHECKOUT_VERSION,
          checkoutId: checkout._id,
          checkoutFingerprint: checkout.fingerprint,
          planId: plan.id,
          expectedAmountCents: String(plan.amountCents),
          currency: plan.currency,
        },
      }, { idempotencyKey: `index-canada:${checkout._id}:${paymentAttempt}` });
    } catch (_error) {
      throw new PaymentFlowError("STRIPE_UNAVAILABLE", 503);
    }
    if (!paymentIntent?.id || !paymentIntent?.client_secret) {
      throw new PaymentFlowError("STRIPE_UNAVAILABLE", 503);
    }
    checkout = await updateCheckout(checkout, {
      status: "payment_pending",
      paymentIntentId: paymentIntent.id,
      paymentAttempt,
    });
    return jsonResponse(200, checkoutResponse(checkout, plan, {
      id: paymentIntent.id,
      payment_intent_id: paymentIntent.id,
      client_secret: paymentIntent.client_secret,
    }));
  } catch (error) {
    logFailure("post_createPaymentIntent", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_createPaymentIntent(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

async function insertProfessionalOnce(record) {
  const existing = await findById("Professionnel", record._id, { consistentRead: true });
  if (existing) {
    if (existing.checkoutId !== record.checkoutId) {
      throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
    }
    return { item: existing, idempotent: true };
  }
  try {
    const inserted = await wixData.insert("Professionnel", record, DATA_OPTIONS);
    return { item: inserted, idempotent: false };
  } catch (error) {
    if (!isDuplicateInsertError(error)) throw error;
    const raced = await findById("Professionnel", record._id, { consistentRead: true });
    if (raced?.checkoutId === record.checkoutId) return { item: raced, idempotent: true };
    throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
  }
}

async function cleanupUploadedMedia(fileUrls, protectedUrls, correlationId) {
  try {
    const candidates = selectOrphanedMediaUrls(fileUrls, protectedUrls);
    if (candidates.length === 0) return;
    await mediaManager.moveFilesToTrash(candidates);
  } catch (error) {
    // Le nettoyage est compensatoire : son échec ne doit pas masquer la cause
    // initiale ni supprimer un média déjà référencé par un checkout concurrent.
    logFailure("checkout_media_cleanup", error, correlationId);
  }
}

async function uploadCheckoutMedia(checkout, correlationId) {
  const uploadPlan = buildMediaUploadPlan(checkout);
  const references = { profile: "", gallery: [] };
  const uploadedUrls = [];
  try {
    for (const upload of uploadPlan.uploads) {
      const fileInfo = await mediaManager.upload(
        upload.path,
        upload.buffer,
        upload.fileName,
        {
          mediaOptions: {
            mimeType: upload.mimeType,
            mediaType: "image",
          },
          metadataOptions: {
            isPrivate: false,
            isVisitorUpload: false,
          },
        },
      );
      const fileUrl = normalizeWixImageUrl(fileInfo?.fileUrl);
      uploadedUrls.push(fileUrl);
      if (upload.kind === "profile") references.profile = fileUrl;
      else references.gallery[upload.index] = fileUrl;
    }
    return {
      references,
      uploadedUrls,
    };
  } catch (error) {
    await cleanupUploadedMedia(uploadedUrls, [], correlationId);
    logFailure("checkout_media_upload", error, correlationId);
    throw new PaymentFlowError("MEDIA_UPLOAD_FAILED", 503);
  }
}

function checkoutMediaUrls(checkout) {
  return [checkout.images.profile, ...checkout.images.gallery].filter(Boolean);
}

async function assertRegistrationCategoryAvailable(categoryId) {
  const category = await findById("SousCategorie", categoryId, { consistentRead: true });
  if (!isCategoryEnabled(category)) throw new InputError("CATEGORY_UNAVAILABLE");
  return category;
}

async function getOrCreatePersistedCheckout(transientDraft, correlationId) {
  const existing = await findById(CHECKOUT_COLLECTION, transientDraft._id, { consistentRead: true });
  if (existing) {
    if (
      existing.fingerprint !== transientDraft.fingerprint
      || existing.planId !== transientDraft.planId
    ) {
      throw new PaymentFlowError("CHECKOUT_CONFLICT", 409);
    }
    validateStoredCheckout(existing);
    return existing;
  }

  await assertRegistrationCategoryAvailable(transientDraft.registration.categoryId);
  const media = await uploadCheckoutMedia(transientDraft, correlationId);
  let persistence;
  try {
    const persistedDraft = buildPersistedCheckoutDraft(
      transientDraft,
      media.references,
    );
    persistence = await persistCheckoutDraft(persistedDraft);
  } catch (error) {
    if (error?.preserveUploadedMedia !== true) {
      await cleanupUploadedMedia(media.uploadedUrls, [], correlationId);
    }
    throw error;
  }

  validateStoredCheckout(persistence.item);
  if (!persistence.created) {
    await cleanupUploadedMedia(
      media.uploadedUrls,
      checkoutMediaUrls(persistence.item),
      correlationId,
    );
  }
  return persistence.item;
}

function checkoutFinalizationPatch(checkout, {
  plan,
  paymentId,
  professionalId,
  entitlement,
}) {
  const patch = {
    status: "finalized",
    professionalId,
    finalizedAt: checkout.finalizedAt || new Date().toISOString(),
  };
  if (entitlement) {
    patch.storeEnvironment = entitlement.environment;
    patch.storeTransactionHash = entitlement.currentTransactionHash
      ?? entitlement.lastTransactionHash;
    patch.entitlementId = entitlement._id;
    patch.entitlementExpiresAt = entitlement.expiresAt;
    patch.currentPlanId = entitlement.planId;
    patch.currentStoreProductId = entitlement.productId;
    patch.pendingPlanId = entitlement.pendingPlanId ?? "";
    patch.pendingStoreProductId = entitlement.pendingProductId ?? "";
    patch.pendingEffectiveAt = entitlement.pendingEffectiveAt ?? "";
    patch.lastStoreEventAt = entitlement.lastProviderEventAt;
  } else if (plan.requiresPayment) {
    patch.paymentIntentId = paymentId;
  }
  return patch;
}

async function repairProfessionalEntitlement(existing, entitlement, paymentId, {
  checkoutId,
} = {}) {
  if (!entitlement) return { item: existing, changed: false };
  const plan = getPlan(entitlement.planId);
  const paymentStatus = ["active", "grace_period"].includes(entitlement.status)
    ? "paid"
    : ["billing_retry", "on_hold", "paused"].includes(entitlement.status)
      ? "past_due"
      : entitlement.status;
  const projection = {
    paymentId,
    paymentProvider: entitlement.provider,
    paymentStatus,
    plan: plan.id,
    sponsor: plan.capabilities.featured,
    entitlementId: entitlement._id,
    entitlementStatus: entitlement.status,
    entitlementExpiresAt: entitlement.expiresAt,
    expiryDate: entitlement.expiresAt,
    pendingPlan: entitlement.pendingPlanId ?? "",
    pendingStoreProductId: entitlement.pendingProductId ?? "",
    pendingEffectiveAt: entitlement.pendingEffectiveAt ?? "",
    ...(checkoutId ? { checkoutId } : {}),
  };
  const changed = Object.entries(projection).some(([field, value]) => existing[field] !== value);
  if (!changed) return { item: existing, changed: false };
  const updated = await wixData.update(
    "Professionnel",
    { ...existing, ...projection, _id: existing._id },
    DATA_OPTIONS,
  );
  return { item: updated, changed: true };
}

async function finalizeExistingStoreProfessional({
  checkout,
  entitlement,
  previousEntitlement,
  paymentReference,
}) {
  validateStoredCheckout(checkout);
  validateStoreCheckout(checkout);
  const rootCheckoutId = entitlement?.rootCheckoutId
    ?? previousEntitlement?.rootCheckoutId
    ?? previousEntitlement?.checkoutId
    ?? checkout._id;
  const previousRootCheckoutId = previousEntitlement
    ? previousEntitlement.rootCheckoutId ?? previousEntitlement.checkoutId
    : rootCheckoutId;
  if (
    !entitlement
    || entitlement.checkoutId !== checkout._id
    || !/^ent_[a-f0-9]{32}$/u.test(entitlement._id ?? "")
    || !/^idx_[a-f0-9]{32}$/u.test(entitlement.professionalId ?? "")
    || !/^chk_[a-f0-9]{32}$/u.test(rootCheckoutId ?? "")
    || entitlement.professionalId !== buildProfessionalId(`checkout:${rootCheckoutId}`)
    || (
      previousEntitlement
      && (
        previousEntitlement._id !== entitlement._id
        || previousEntitlement.professionalId !== entitlement.professionalId
        || previousRootCheckoutId !== rootCheckoutId
        || previousEntitlement.provider !== entitlement.provider
        || previousEntitlement.originalTransactionHash
          !== entitlement.originalTransactionHash
      )
    )
  ) {
    throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
  }
  const currentCheckout = await findById(CHECKOUT_COLLECTION, checkout._id, {
    consistentRead: true,
  });
  if (!currentCheckout) throw new PaymentFlowError("CHECKOUT_NOT_FOUND", 500);
  validateStoredCheckout(currentCheckout);
  validateStoreCheckout(currentCheckout);
  if (
    (currentCheckout.professionalId
      && currentCheckout.professionalId !== entitlement.professionalId)
    || (currentCheckout.entitlementId
      && currentCheckout.entitlementId !== entitlement._id)
  ) {
    throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
  }
  const rootCheckout = rootCheckoutId === currentCheckout._id
    ? currentCheckout
    : await findById(CHECKOUT_COLLECTION, rootCheckoutId, { consistentRead: true });
  if (!rootCheckout) throw new PaymentFlowError("PROFESSIONAL_REPAIR_REQUIRED", 503);
  validateStoredCheckout(rootCheckout);
  validateStoreCheckout(rootCheckout);
  if (
    rootCheckout.store !== currentCheckout.store
    || rootCheckout.paymentProvider !== entitlement.provider
    || (rootCheckout.professionalId
      && rootCheckout.professionalId !== entitlement.professionalId)
    || (rootCheckout.entitlementId && rootCheckout.entitlementId !== entitlement._id)
  ) {
    throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
  }
  const effectivePaymentReference = paymentReference
    ?? `store:${entitlement.provider}:${entitlement.lastTransactionHash}`;
  let professional = await findById("Professionnel", entitlement.professionalId, {
    consistentRead: true,
  });
  let professionalCreated = false;
  if (!professional) {
    const bootstrapEntitlement = {
      ...entitlement,
      rootCheckoutId,
      checkoutId: rootCheckoutId,
      planId: rootCheckout.planId,
      productId: rootCheckout.storeProductId,
      pendingPlanId: "",
      pendingProductId: "",
      pendingEffectiveAt: "",
    };
    const record = buildProfessionalRecord(
      rootCheckout,
      effectivePaymentReference,
      Date.now(),
      { entitlement: bootstrapEntitlement },
    );
    const saved = await insertProfessionalOnce(record);
    professional = saved.item;
    professionalCreated = !saved.idempotent;
  }
  if (
    professional._id !== entitlement.professionalId
    || professional.entitlementId !== entitlement._id
  ) {
    throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
  }
  let predecessorCheckoutChanged = false;
  if (professional.checkoutId !== checkout._id && professional.checkoutId !== rootCheckoutId) {
    const predecessorCheckout = await findById(
      CHECKOUT_COLLECTION,
      professional.checkoutId,
      { consistentRead: true },
    );
    if (!predecessorCheckout) {
      throw new PaymentFlowError("PROFESSIONAL_REPAIR_REQUIRED", 503);
    }
    validateStoredCheckout(predecessorCheckout);
    validateStoreCheckout(predecessorCheckout);
    const predecessorProvenByPrevious = previousEntitlement
      && previousEntitlement.checkoutId === predecessorCheckout._id
      && previousRootCheckoutId === rootCheckoutId;
    if (
      predecessorCheckout._id === checkout._id
      || predecessorCheckout.store !== currentCheckout.store
      || predecessorCheckout.paymentProvider !== entitlement.provider
      || (predecessorCheckout.entitlementId
        && predecessorCheckout.entitlementId !== entitlement._id)
      || (predecessorCheckout.professionalId
        && predecessorCheckout.professionalId !== entitlement.professionalId)
      || (
        (!predecessorCheckout.entitlementId || !predecessorCheckout.professionalId)
        && !predecessorProvenByPrevious
      )
    ) {
      throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
    }
    const predecessorLinkPatch = {
      status: "finalized",
      professionalId: entitlement.professionalId,
      entitlementId: entitlement._id,
      finalizedAt: predecessorCheckout.finalizedAt || new Date().toISOString(),
    };
    predecessorCheckoutChanged = Object.entries(predecessorLinkPatch)
      .some(([field, value]) => predecessorCheckout[field] !== value);
    if (predecessorCheckoutChanged) {
      await updateCheckout(predecessorCheckout, predecessorLinkPatch);
    }
  }
  let rootCheckoutChanged = false;
  if (rootCheckoutId !== currentCheckout._id) {
    const rootLinkPatch = {
      status: "finalized",
      professionalId: entitlement.professionalId,
      entitlementId: entitlement._id,
      finalizedAt: rootCheckout.finalizedAt || new Date().toISOString(),
    };
    rootCheckoutChanged = Object.entries(rootLinkPatch)
      .some(([field, value]) => rootCheckout[field] !== value);
    if (rootCheckoutChanged) await updateCheckout(rootCheckout, rootLinkPatch);
  }
  const repaired = await repairProfessionalEntitlement(
    professional,
    entitlement,
    effectivePaymentReference,
    { checkoutId: checkout._id },
  );
  const plan = getPlan(entitlement.planId);
  const patch = checkoutFinalizationPatch(currentCheckout, {
    plan,
    paymentId: effectivePaymentReference,
    professionalId: professional._id,
    entitlement,
  });
  const checkoutChanged = Object.entries(patch)
    .some(([field, value]) => currentCheckout[field] !== value);
  const finalizedCheckout = checkoutChanged
    ? await updateCheckout(currentCheckout, patch)
    : currentCheckout;
  return {
    checkout: finalizedCheckout,
    professional: repaired.item,
    idempotent: !professionalCreated
      && !rootCheckoutChanged
      && !predecessorCheckoutChanged
      && !checkoutChanged
      && !repaired.changed,
  };
}

async function projectLifecycleEntitlement({ checkout, entitlement, previousEntitlement }) {
  validateStoredCheckout(checkout);
  validateStoreCheckout(checkout);
  const latest = await findById(ENTITLEMENT_COLLECTION, entitlement._id, {
    consistentRead: true,
  });
  if (
    !latest
    || latest._id !== entitlement._id
    || latest.professionalId !== entitlement.professionalId
    || latest.checkoutId !== checkout._id
  ) {
    throw new PaymentFlowError("ENTITLEMENT_PERSISTENCE_UNCERTAIN", 503);
  }
  return finalizeExistingStoreProfessional({
    checkout,
    entitlement: latest,
    previousEntitlement,
    paymentReference: `store:${latest.provider}:${latest.lastTransactionHash}`,
  });
}

async function finalizeCheckout(checkout, { plan, paymentId, entitlement = null }) {
  // Wix Data cannot atomically insert the profile and update the checkout.
  // A deterministic profile id makes a retry repair the second write safely.
  validateStoredCheckout(checkout);
  const professionalId = buildProfessionalId(`checkout:${checkout._id}`);
  const existing = await findById("Professionnel", professionalId, { consistentRead: true });
  if (existing) {
    if (existing.checkoutId !== checkout._id) {
      throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
    }
    const professionalRepair = await repairProfessionalEntitlement(existing, entitlement, paymentId);
    const expectedPatch = checkoutFinalizationPatch(checkout, {
      plan,
      paymentId,
      professionalId,
      entitlement,
    });
    const checkoutAlreadyFinalized = Object.entries(expectedPatch)
      .every(([field, value]) => checkout[field] === value);
    const repairedCheckout = checkoutAlreadyFinalized
      ? checkout
      : await updateCheckout(checkout, expectedPatch);
    return {
      checkout: repairedCheckout,
      professional: professionalRepair.item,
      idempotent: checkoutAlreadyFinalized && !professionalRepair.changed,
    };
  }

  const record = buildProfessionalRecord(checkout, paymentId, Date.now(), { entitlement });
  const saved = await insertProfessionalOnce(record);
  const professionalRepair = await repairProfessionalEntitlement(saved.item, entitlement, paymentId);
  const finalizedCheckout = await updateCheckout(checkout, checkoutFinalizationPatch(checkout, {
    plan,
    paymentId,
    professionalId: saved.item._id,
    entitlement,
  }));
  return {
    checkout: finalizedCheckout,
    professional: professionalRepair.item,
    idempotent: saved.idempotent && !professionalRepair.changed,
  };
}

async function finalizePaidPaymentIntent(paymentIntent) {
  const checkoutId = paymentIntent?.metadata?.checkoutId;
  if (typeof checkoutId !== "string" || !/^chk_[a-f0-9]{32}$/u.test(checkoutId)) {
    throw new InputError("UNTRUSTED_PAYMENT_INTENT");
  }
  const checkout = await findById(CHECKOUT_COLLECTION, checkoutId, { consistentRead: true });
  if (!checkout) throw new PaymentFlowError("CHECKOUT_NOT_FOUND", 500);
  const plan = validatePaymentIntentForCheckout(paymentIntent, checkout);
  if (checkout.paymentIntentId && checkout.paymentIntentId !== paymentIntent.id) {
    throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
  }
  return finalizeCheckout(checkout, {
    plan,
    paymentId: paymentIntent.id,
  });
}

export async function post_confirmPayment(request) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "confirmation", correlationId);
    const body = await readJsonBody(request);
    const reference = body.confirmationToken
      ?? body.confirmation_token
      ?? body.paymentIntentId
      ?? body.payment_intent_id;
    const referenceType = classifyConfirmationReference(reference);
    let finalized;

    if (referenceType === "free") {
      const signingSecret = await getSigningSecret();
      const token = verifyFreeCheckoutToken(reference, signingSecret);
      const checkout = await findById(CHECKOUT_COLLECTION, token.checkoutId, { consistentRead: true });
      if (
        !checkout
        || checkout.planId !== "basic"
        || (checkout.paymentProvider ?? "free") !== "free"
        || checkout.fingerprint !== token.fp
        || checkout.sourceRegistrationId !== token.sid
      ) {
        throw new InputError("REGISTRATION_MISMATCH");
      }
      const plan = validateStoredCheckout(checkout);
      assertCheckoutNotExpired(checkout);
      finalized = await finalizeCheckout(checkout, {
        plan,
        paymentId: `free:${checkout._id}`,
      });
    } else {
      const stripe = await getStripe();
      let paymentIntent;
      try {
        paymentIntent = await stripe.paymentIntents.retrieve(reference);
      } catch (error) {
        if (isStripeResourceMissing(error)) {
          throw new PaymentFlowError("PAYMENT_NOT_FOUND", 400);
        }
        throw new PaymentFlowError("STRIPE_UNAVAILABLE", 503);
      }
      finalized = await finalizePaidPaymentIntent(paymentIntent);
    }

    const plan = getPlan(finalized.checkout.planId);
    return jsonResponse(200, {
      success: true,
      checkout_id: finalized.checkout._id,
      idempotent: finalized.idempotent,
      status: finalized.professional.registrationStatus,
      data: {
        professionalId: finalized.professional._id,
        planId: plan.id,
        isActive: finalized.professional.isActive === true,
      },
    });
  } catch (error) {
    logFailure("post_confirmPayment", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_confirmPayment(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

export async function post_confirmStorePurchase(request, dependencies = {}) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "confirmation", correlationId);
    const body = await readJsonBody(request);
    const checkoutId = body?.checkoutId ?? body?.checkout_id;
    if (typeof checkoutId !== "string" || !/^chk_[a-f0-9]{32}$/u.test(checkoutId)) {
      throw new InputError("INVALID_STORE_PURCHASE");
    }
    const checkout = await findById(CHECKOUT_COLLECTION, checkoutId, { consistentRead: true });
    if (!checkout) throw new PaymentFlowError("CHECKOUT_NOT_FOUND", 400);
    validateStoredCheckout(checkout);
    validateStoreCheckout(checkout);
    const signingKeyring = await getStoreSigningKeyring();

    let verifyApple = dependencies.verifyApple;
    let verifyGoogle = dependencies.verifyGoogle;
    let acknowledgeGoogle = dependencies.acknowledgeGoogle;
    if (checkout.store === "app_store" && typeof verifyApple !== "function") {
      const verifier = await getAppleStoreVerifier();
      verifyApple = (signedTransactionInfo) => verifier.verifyTransaction(signedTransactionInfo);
    }
    if (checkout.store === "google_play") {
      const needsVerifier = typeof verifyGoogle !== "function";
      const needsAcknowledger = typeof acknowledgeGoogle !== "function";
      if (needsVerifier || needsAcknowledger) {
        const verifier = await getGoogleStoreVerifier();
        if (needsVerifier) {
          verifyGoogle = (purchaseToken) => verifier.getSubscription(purchaseToken);
        }
        if (needsAcknowledger) {
          acknowledgeGoogle = ({ purchaseToken, productId }) => verifier.acknowledgeSubscription({
            purchaseToken,
            productId,
          });
        }
      }
    }

    const delivered = await confirmStorePurchaseWithDependencies({
      checkout,
      rawConfirmation: body,
      signingKeyring,
      verifyApple,
      verifyGoogle,
      acknowledgeGoogle,
      allowSandbox: await sandboxPolicy(dependencies),
      persistEntitlement: dependencies.persistEntitlement ?? persistEntitlementRecord,
      findEntitlement: dependencies.findEntitlement
        ?? ((id) => findById(ENTITLEMENT_COLLECTION, id, { consistentRead: true })),
      findEntitlementsByCurrentTransactionHash:
        dependencies.findEntitlementsByCurrentTransactionHash
        ?? findStoreEntitlementsByCurrentTransactionHash,
      finalizeProfessional: dependencies.finalizeProfessional
        ?? finalizeExistingStoreProfessional,
      finalizeExistingProfessional: dependencies.finalizeExistingProfessional
        ?? finalizeExistingStoreProfessional,
    });

    let finalizedCheckout = delivered.checkout;
    if (checkout.store === "google_play" && finalizedCheckout.storeAcknowledged !== true) {
      finalizedCheckout = await updateCheckout(finalizedCheckout, {
        storeAcknowledged: true,
        storeAcknowledgedAt: new Date().toISOString(),
      });
    }
    return jsonResponse(200, {
      success: true,
      checkout_id: finalizedCheckout._id,
      idempotent: delivered.idempotent,
      complete_purchase: true,
      status: delivered.professional.registrationStatus,
      entitlement: {
        status: delivered.entitlement.status,
        expires_at: delivered.entitlement.expiresAt,
        plan_id: delivered.entitlement.planId,
        product_id: delivered.entitlement.productId,
        ...(delivered.entitlement.pendingPlanId ? {
          pending_plan_id: delivered.entitlement.pendingPlanId,
          pending_product_id: delivered.entitlement.pendingProductId,
          pending_effective_at: delivered.entitlement.pendingEffectiveAt,
        } : {}),
      },
      data: {
        professionalId: delivered.professional._id,
        planId: delivered.entitlement.planId,
        ...(delivered.entitlement.pendingPlanId
          ? { pendingPlanId: delivered.entitlement.pendingPlanId }
          : {}),
        isActive: delivered.professional.isActive === true,
      },
    });
  } catch (error) {
    logFailure("post_confirmStorePurchase", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_confirmStorePurchase(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

export async function post_restoreStorePurchase(request, dependencies = {}) {
  const correlationId = requestId();
  try {
    await consumeRateLimit(request, "confirmation", correlationId);
    const body = await readJsonBody(request);
    const restoration = validateStoreRestoration(body);
    const signingKeyring = await getStoreSigningKeyring();

    let verifyApple = dependencies.verifyApple;
    let verifyGoogle = dependencies.verifyGoogle;
    let acknowledgeGoogle = dependencies.acknowledgeGoogle;
    if (restoration.store === "app_store" && typeof verifyApple !== "function") {
      const verifier = await getAppleStoreVerifier();
      verifyApple = (signedTransactionInfo) => verifier.verifyTransaction(signedTransactionInfo);
    }
    if (restoration.store === "google_play") {
      const needsVerifier = typeof verifyGoogle !== "function";
      const needsAcknowledger = typeof acknowledgeGoogle !== "function";
      if (needsVerifier || needsAcknowledger) {
        const verifier = await getGoogleStoreVerifier();
        if (needsVerifier) {
          verifyGoogle = (purchaseToken) => verifier.getSubscription(purchaseToken);
        }
        if (needsAcknowledger) {
          acknowledgeGoogle = ({ purchaseToken, productId }) => verifier.acknowledgeSubscription({
            purchaseToken,
            productId,
          });
        }
      }
    }

    const delivered = await restoreStorePurchaseWithDependencies({
      rawRestoration: restoration,
      signingKeyring,
      verifyApple,
      verifyGoogle,
      acknowledgeGoogle,
      allowSandbox: await sandboxPolicy(dependencies),
      findEntitlement: dependencies.findEntitlement
        ?? ((id) => findById(ENTITLEMENT_COLLECTION, id, { consistentRead: true })),
      findEntitlementsByCurrentTransactionHash:
        dependencies.findEntitlementsByCurrentTransactionHash
        ?? findStoreEntitlementsByCurrentTransactionHash,
      findCheckout: dependencies.findCheckout
        ?? ((id) => findById(CHECKOUT_COLLECTION, id, { consistentRead: true })),
      findCheckoutsByAccountReference: dependencies.findCheckoutsByAccountReference
        ?? findStoreCheckoutsByAccountReference,
      persistEntitlement: dependencies.persistEntitlement ?? persistEntitlementRecord,
      finalizeProfessional: dependencies.finalizeProfessional
        ?? finalizeExistingStoreProfessional,
      finalizeExistingProfessional: dependencies.finalizeExistingProfessional
        ?? finalizeExistingStoreProfessional,
    });

    let finalizedCheckout = delivered.checkout;
    if (restoration.store === "google_play" && finalizedCheckout.storeAcknowledged !== true) {
      finalizedCheckout = await updateCheckout(finalizedCheckout, {
        storeAcknowledged: true,
        storeAcknowledgedAt: new Date().toISOString(),
      });
    }
    const plan = getPlan(delivered.entitlement.planId);
    return jsonResponse(200, {
      success: true,
      restored: true,
      checkout_id: finalizedCheckout._id,
      idempotent: delivered.idempotent,
      complete_purchase: true,
      status: delivered.professional.registrationStatus,
      entitlement: {
        status: delivered.entitlement.status,
        expires_at: delivered.entitlement.expiresAt,
        plan_id: delivered.entitlement.planId,
        product_id: delivered.entitlement.productId,
        ...(delivered.entitlement.pendingPlanId ? {
          pending_plan_id: delivered.entitlement.pendingPlanId,
          pending_product_id: delivered.entitlement.pendingProductId,
          pending_effective_at: delivered.entitlement.pendingEffectiveAt,
        } : {}),
      },
      data: {
        professionalId: delivered.professional._id,
        planId: plan.id,
        ...(delivered.entitlement.pendingPlanId
          ? { pendingPlanId: delivered.entitlement.pendingPlanId }
          : {}),
        isActive: delivered.professional.isActive === true,
      },
    });
  } catch (error) {
    logFailure("post_restoreStorePurchase", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_restoreStorePurchase(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

export async function post_appStoreServerNotificationV2(request, dependencies = {}) {
  const correlationId = requestId();
  try {
    const body = await readLimitedJsonBody(request, 320 * 1024);
    const signedPayload = body?.signedPayload ?? body?.signed_payload;
    if (
      typeof signedPayload !== "string"
      || signedPayload.length < 8
      || signedPayload.length > 300_000
      || signedPayload.trim() !== signedPayload
    ) {
      throw new InputError("INVALID_STORE_NOTIFICATION");
    }
    let verifyNotification = dependencies.verifyAppleNotification;
    let verifyTransaction = dependencies.verifyAppleTransaction;
    if (typeof verifyNotification !== "function" || typeof verifyTransaction !== "function") {
      const verifier = await getAppleStoreVerifier();
      if (typeof verifyNotification !== "function") {
        verifyNotification = (value) => verifier.verifyNotification(value);
      }
      if (typeof verifyTransaction !== "function") {
        verifyTransaction = (value) => verifier.verifyTransaction(value);
      }
    }
    const notification = await verifyNotification(signedPayload);
    if (notification?.notificationType === "TEST") {
      return jsonResponse(200, { received: true, test: true });
    }
    const signedTransactionInfo = notification?.data?.signedTransactionInfo;
    if (typeof signedTransactionInfo !== "string" || signedTransactionInfo.length < 8) {
      return jsonResponse(200, { received: true, ignored: true });
    }
    const transaction = await verifyTransaction(signedTransactionInfo);
    const event = normalizeAppleLifecycleEvent(notification, transaction, {
      signedPayload,
      signedTransactionInfo,
    });
    const processed = await processStoreLifecycleEvent({
      event,
      signingKeyring: await getStoreSigningKeyring(),
      allowSandbox: await sandboxPolicy(dependencies),
      beginEvent: dependencies.beginEvent ?? beginStoreEventRecord,
      completeEvent: dependencies.completeEvent ?? completeStoreEventRecord,
      findEntitlement: dependencies.findEntitlement
        ?? ((id) => findById(ENTITLEMENT_COLLECTION, id, { consistentRead: true })),
      findEntitlementsByCurrentTransactionHash:
        dependencies.findEntitlementsByCurrentTransactionHash
        ?? findStoreEntitlementsByCurrentTransactionHash,
      findCheckout: dependencies.findCheckout
        ?? ((id) => findById(CHECKOUT_COLLECTION, id, { consistentRead: true })),
      findCheckoutsByAccountReference: dependencies.findCheckoutsByAccountReference
        ?? findStoreCheckoutsByAccountReference,
      persistEntitlement: dependencies.persistEntitlement ?? persistEntitlementRecord,
      projectProfessional: dependencies.projectProfessional ?? projectLifecycleEntitlement,
      projectReplacementProfessional: dependencies.projectReplacementProfessional
        ?? finalizeExistingStoreProfessional,
    });
    return jsonResponse(200, {
      received: true,
      idempotent: processed.idempotent,
      ignored: processed.ignored,
    });
  } catch (error) {
    logFailure("post_appStoreServerNotificationV2", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_appStoreServerNotificationV2(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

export async function post_googlePlayRtdn(request, dependencies = {}) {
  const correlationId = requestId();
  try {
    const contentLength = Number(requestHeader(request, "content-length") || 0);
    if (Number.isFinite(contentLength) && contentLength > 128 * 1024) {
      throw new InputError("PAYLOAD_TOO_LARGE");
    }
    const authorization = requestHeader(request, "authorization");
    if (typeof dependencies.verifyGooglePush === "function") {
      await dependencies.verifyGooglePush(authorization);
    } else {
      const pushVerifier = await getGooglePushVerifier();
      await pushVerifier.verifyAuthorization(authorization);
    }
    const body = await readLimitedJsonBody(request, 128 * 1024);
    const expectedSubscription = dependencies.expectedSubscription
      ?? await getGoogleRtdnSubscription();
    const rtdn = decodeGoogleRtdnEnvelope(body, { expectedSubscription });
    if (rtdn.test) return jsonResponse(200, { received: true, test: true });

    let verifyGoogle = dependencies.verifyGoogle;
    let acknowledgeGoogle = dependencies.acknowledgeGoogle;
    if (typeof verifyGoogle !== "function" || typeof acknowledgeGoogle !== "function") {
      const verifier = await getGoogleStoreVerifier();
      if (typeof verifyGoogle !== "function") {
        verifyGoogle = (purchaseToken) => verifier.getSubscription(purchaseToken);
      }
      if (typeof acknowledgeGoogle !== "function") {
        acknowledgeGoogle = ({ purchaseToken, productId }) => verifier.acknowledgeSubscription({
          purchaseToken,
          productId,
        });
      }
    }
    const subscription = await verifyGoogle(rtdn.purchaseToken);
    const event = normalizeGoogleLifecycleEvent(rtdn, subscription);
    const processed = await processStoreLifecycleEvent({
      event,
      signingKeyring: await getStoreSigningKeyring(),
      allowSandbox: await sandboxPolicy(dependencies),
      beginEvent: dependencies.beginEvent ?? beginStoreEventRecord,
      completeEvent: dependencies.completeEvent ?? completeStoreEventRecord,
      findEntitlement: dependencies.findEntitlement
        ?? ((id) => findById(ENTITLEMENT_COLLECTION, id, { consistentRead: true })),
      findEntitlementsByCurrentTransactionHash:
        dependencies.findEntitlementsByCurrentTransactionHash
        ?? findStoreEntitlementsByCurrentTransactionHash,
      findCheckout: dependencies.findCheckout
        ?? ((id) => findById(CHECKOUT_COLLECTION, id, { consistentRead: true })),
      findCheckoutsByAccountReference: dependencies.findCheckoutsByAccountReference
        ?? findStoreCheckoutsByAccountReference,
      persistEntitlement: dependencies.persistEntitlement ?? persistEntitlementRecord,
      projectProfessional: dependencies.projectProfessional ?? projectLifecycleEntitlement,
      projectReplacementProfessional: dependencies.projectReplacementProfessional
        ?? finalizeExistingStoreProfessional,
      acknowledgeGoogle,
    });
    return jsonResponse(200, {
      received: true,
      idempotent: processed.idempotent,
      ignored: processed.ignored,
    });
  } catch (error) {
    logFailure("post_googlePlayRtdn", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function use_googlePlayRtdn(request) {
  return preflightOrMethodNotAllowed(request, PRIVATE_HEADERS);
}

export async function post_stripeWebhook(request) {
  const correlationId = requestId();
  try {
    const contentLength = Number(requestHeader(request, "content-length") || 0);
    if (Number.isFinite(contentLength) && contentLength > 128 * 1024) {
      throw new InputError("PAYLOAD_TOO_LARGE");
    }
    const signature = requestHeader(request, "stripe-signature");
    if (!signature) {
      throw new InputError("INVALID_WEBHOOK_SIGNATURE");
    }
    const rawBody = await request.body.buffer();
    if (!rawBody || rawBody.length > 128 * 1024) throw new InputError("PAYLOAD_TOO_LARGE");
    const [stripe, webhookSecret] = await Promise.all([getStripe(), getWebhookSecret()]);
    let event;
    try {
      event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
    } catch (_error) {
      throw new InputError("INVALID_WEBHOOK_SIGNATURE");
    }
    if (event.type === "payment_intent.succeeded") {
      const paymentIntent = event?.data?.object;
      if (classifyPaymentIntentWebhook(paymentIntent) === "linked") {
        await finalizePaidPaymentIntent(paymentIntent);
      }
    }
    return jsonResponse(200, { received: true });
  } catch (error) {
    logFailure("post_stripeWebhook", error, correlationId);
    return publicError(error, correlationId);
  }
}

export function createPaymentIntent(request) {
  return post_createPaymentIntent(request);
}

export function confirmPayment(request) {
  return post_confirmPayment(request);
}

export function createStoreCheckout(request) {
  return post_createStoreCheckout(request);
}

export function confirmStorePurchase(request) {
  return post_confirmStorePurchase(request);
}

export function restoreStorePurchase(request) {
  return post_restoreStorePurchase(request);
}

export function appStoreServerNotificationV2(request) {
  return post_appStoreServerNotificationV2(request);
}

export function googlePlayRtdn(request) {
  return post_googlePlayRtdn(request);
}

export { get_data as data_get };
export { get_searchProfessionals as searchProfessionals_get };
export { get_categories as categories_get };
export { get_professionals as professionals_get };
export { get_reviews as reviews_get };
export { get_partners as partners_get };
export { get_offers as offers_get };
export { get_paymentPlans as paymentPlans_get };
export { post_review as review_post };
export { post_engagementEvent as engagementEvent_post };
export { post_createPaymentIntent as createPaymentIntent_post };
export { post_confirmPayment as confirmPayment_post };
export { post_createStoreCheckout as createStoreCheckout_post };
export { post_confirmStorePurchase as confirmStorePurchase_post };
export { post_restoreStorePurchase as restoreStorePurchase_post };
export { post_appStoreServerNotificationV2 as appStoreServerNotificationV2_post };
export { post_googlePlayRtdn as googlePlayRtdn_post };
export { post_stripeWebhook as stripeWebhook_post };
