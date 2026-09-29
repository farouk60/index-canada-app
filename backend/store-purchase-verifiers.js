import * as appleStoreServerLibrary from "@apple/app-store-server-library";
import * as googleAndroidPublisherLibrary from "@googleapis/androidpublisher";
import * as googleAuthLibrary from "google-auth-library";

import { APP_BUNDLE_ID } from "./store-purchase-core.js";

const GOOGLE_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const GOOGLE_FEDERATED_SIGNON_PEM_CERTS_URL = "https://www.googleapis.com/oauth2/v1/certs";
const GOOGLE_OIDC_ISSUERS = Object.freeze([
  "accounts.google.com",
  "https://accounts.google.com",
]);
const GOOGLE_CERTIFICATE_FETCH_TIMEOUT_MS = 5_000;
const GOOGLE_CERTIFICATE_MAX_RESPONSE_BYTES = 64 * 1024;
const GOOGLE_CERTIFICATE_FALLBACK_CACHE_MS = 5 * 60 * 1000;
const GOOGLE_CERTIFICATE_MAX_CACHE_MS = 6 * 60 * 60 * 1000;
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/u;
const GOOGLE_CERTIFICATE_KID_PATTERN = /^[A-Za-z0-9_-]{8,128}$/u;
const GOOGLE_PEM_CERTIFICATE_PATTERN = /^-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\r?\n?$/u;
const SAFE_PROVIDER_DIAGNOSTICS = new Set([
  "authorization_missing_or_oversize",
  "authorization_format_invalid",
  "id_token_certificate_fetch_failed",
  "id_token_key_unknown",
  "id_token_signature_invalid",
  "id_token_time_invalid",
  "id_token_issuer_invalid",
  "id_token_audience_mismatch",
  "id_token_format_invalid",
  "id_token_verification_failed",
  "claim_payload_missing",
  "claim_email_mismatch",
  "claim_email_unverified",
  "claim_subject_missing",
]);

export function safeStoreProviderDiagnostic(value) {
  return typeof value === "string" && SAFE_PROVIDER_DIAGNOSTICS.has(value) ? value : "";
}

export class StoreProviderError extends Error {
  constructor(code, { retryable = false, diagnostic = "" } = {}) {
    super(code);
    this.name = "StoreProviderError";
    this.code = code;
    this.retryable = retryable;
    const safeDiagnostic = safeStoreProviderDiagnostic(diagnostic);
    if (safeDiagnostic) {
      Object.defineProperty(this, "diagnostic", {
        value: safeDiagnostic,
        enumerable: false,
        writable: false,
      });
    }
  }
}

function providerConfigError(code) {
  return new StoreProviderError(code, { retryable: true });
}

function googlePushVerificationDiagnostic(error) {
  const message = typeof error?.message === "string" ? error.message : "";
  if (message.startsWith("Failed to retrieve verification certificates:")) {
    return "id_token_certificate_fetch_failed";
  }
  if (message.startsWith("No pem found for envelope:")) {
    return "id_token_key_unknown";
  }
  if (message.startsWith("Invalid token signature:")) {
    return "id_token_signature_invalid";
  }
  if (message.startsWith("Invalid issuer,")) {
    return "id_token_issuer_invalid";
  }
  if (message === "Wrong recipient, payload audience != requiredAudience") {
    return "id_token_audience_mismatch";
  }
  if ([
    "No issue time in token:",
    "No expiration time in token:",
    "iat field using invalid format",
    "exp field using invalid format",
    "Expiration time too far in future:",
    "Token used too early,",
    "Token used too late,",
  ].some((prefix) => message.startsWith(prefix))) {
    return "id_token_time_invalid";
  }
  if ([
    "Wrong number of segments in token:",
    "Can't parse token envelope:",
    "Can't parse token payload",
  ].some((prefix) => message.startsWith(prefix))) {
    return "id_token_format_invalid";
  }
  return "id_token_verification_failed";
}

function googleCertificateUnavailable() {
  return new StoreProviderError("GOOGLE_PUSH_VERIFICATION_UNAVAILABLE", {
    retryable: true,
    diagnostic: "id_token_certificate_fetch_failed",
  });
}

function responseHeader(response, name) {
  const value = response?.headers?.get?.(name);
  return typeof value === "string" ? value.trim() : "";
}

function certificateCacheDuration(cacheControl) {
  const match = /(?:^|,)\s*max-age\s*=\s*([0-9]+)(?:\s*(?:,|$))/iu.exec(cacheControl);
  if (!match) return GOOGLE_CERTIFICATE_FALLBACK_CACHE_MS;
  const declaredMilliseconds = Number(match[1]) * 1000;
  if (!Number.isSafeInteger(declaredMilliseconds) || declaredMilliseconds <= 0) return 0;
  const boundedMilliseconds = Math.min(declaredMilliseconds, GOOGLE_CERTIFICATE_MAX_CACHE_MS);
  const refreshMargin = Math.min(60_000, Math.floor(boundedMilliseconds / 10));
  return Math.max(0, boundedMilliseconds - refreshMargin);
}

function validatedGooglePemCertificates(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw googleCertificateUnavailable();
  }
  const entries = Object.entries(value);
  if (entries.length < 1 || entries.length > 10) throw googleCertificateUnavailable();
  const certificates = Object.create(null);
  for (const [kid, certificate] of entries) {
    if (
      !GOOGLE_CERTIFICATE_KID_PATTERN.test(kid)
      || typeof certificate !== "string"
      || certificate.length < 512
      || certificate.length > 16_384
      || !GOOGLE_PEM_CERTIFICATE_PATTERN.test(certificate)
    ) {
      throw googleCertificateUnavailable();
    }
    certificates[kid] = certificate;
  }
  return Object.freeze(certificates);
}

export function createGoogleCertificateLoader({
  fetcher,
  timeoutMs = GOOGLE_CERTIFICATE_FETCH_TIMEOUT_MS,
  maxResponseBytes = GOOGLE_CERTIFICATE_MAX_RESPONSE_BYTES,
  now = () => Date.now(),
} = {}) {
  if (
    typeof fetcher !== "function"
    || !Number.isInteger(timeoutMs)
    || timeoutMs < 1
    || timeoutMs > 30_000
    || !Number.isInteger(maxResponseBytes)
    || maxResponseBytes < 512
    || maxResponseBytes > 256 * 1024
    || typeof now !== "function"
  ) {
    throw providerConfigError("GOOGLE_PUSH_CONFIGURATION_INVALID");
  }

  let cachedCertificates;
  let cacheExpiresAt = 0;
  let inFlight;

  async function fetchCertificates() {
    let timeoutHandle;
    const timeout = new Promise((_, reject) => {
      timeoutHandle = setTimeout(() => reject(googleCertificateUnavailable()), timeoutMs);
    });
    let response;
    try {
      response = await Promise.race([
        Promise.resolve().then(() => fetcher(GOOGLE_FEDERATED_SIGNON_PEM_CERTS_URL, {
          method: "GET",
          headers: { Accept: "application/json" },
          cache: "no-store",
        })),
        timeout,
      ]);
    } catch (_error) {
      throw googleCertificateUnavailable();
    } finally {
      clearTimeout(timeoutHandle);
    }

    try {
      if (response?.ok !== true || response.status !== 200 || typeof response.text !== "function") {
        throw googleCertificateUnavailable();
      }
      const contentType = responseHeader(response, "content-type");
      if (contentType && !/^application\/json(?:\s*;|$)/iu.test(contentType)) {
        throw googleCertificateUnavailable();
      }
      const declaredLength = responseHeader(response, "content-length");
      if (/^[0-9]+$/u.test(declaredLength) && Number(declaredLength) > maxResponseBytes) {
        throw googleCertificateUnavailable();
      }
      const body = await response.text();
      if (typeof body !== "string" || Buffer.byteLength(body, "utf8") > maxResponseBytes) {
        throw googleCertificateUnavailable();
      }
      const certificates = validatedGooglePemCertificates(JSON.parse(body));
      return {
        certificates,
        cacheDuration: certificateCacheDuration(responseHeader(response, "cache-control")),
      };
    } catch (_error) {
      throw googleCertificateUnavailable();
    }
  }

  return Object.freeze({
    async load() {
      const timestamp = Number(now());
      if (!Number.isFinite(timestamp)) throw googleCertificateUnavailable();
      if (cachedCertificates && timestamp < cacheExpiresAt) return cachedCertificates;
      if (!inFlight) {
        inFlight = fetchCertificates()
          .then(({ certificates, cacheDuration }) => {
            cachedCertificates = certificates;
            const refreshedAt = Number(now());
            cacheExpiresAt = Number.isFinite(refreshedAt) ? refreshedAt + cacheDuration : 0;
            return certificates;
          })
          .finally(() => {
            inFlight = undefined;
          });
      }
      return inFlight;
    },
  });
}

function opaqueString(value, code, max = 20_000) {
  if (
    typeof value !== "string"
    || value.length < 8
    || value.length > max
    || value.trim() !== value
  ) {
    throw new StoreProviderError(code);
  }
  return value;
}

export function parseAppleRootCertificates(value) {
  let entries = value;
  if (typeof entries === "string") {
    try {
      entries = JSON.parse(entries);
    } catch (_error) {
      throw providerConfigError("APPLE_CONFIGURATION_INVALID");
    }
  }
  if (!Array.isArray(entries) || entries.length < 1 || entries.length > 8) {
    throw providerConfigError("APPLE_CONFIGURATION_INVALID");
  }
  try {
    const roots = entries.map((entry) => {
      if (
        typeof entry !== "string"
        || entry.length > 16_000
        || !BASE64_PATTERN.test(entry)
      ) {
        throw providerConfigError("APPLE_CONFIGURATION_INVALID");
      }
      const certificate = Buffer.from(entry, "base64");
      if (certificate.length < 128 || certificate.length > 12_000) {
        throw providerConfigError("APPLE_CONFIGURATION_INVALID");
      }
      return certificate;
    });
    return Object.freeze(roots);
  } catch (error) {
    if (error instanceof StoreProviderError) throw error;
    throw providerConfigError("APPLE_CONFIGURATION_INVALID");
  }
}

export async function createAppleTransactionVerifier({
  rootCertificates,
  appAppleId,
  bundleId = APP_BUNDLE_ID,
  libraryLoader = () => appleStoreServerLibrary,
} = {}) {
  const roots = Array.isArray(rootCertificates)
    ? parseAppleRootCertificates(rootCertificates.map((entry) => Buffer.isBuffer(entry)
      ? entry.toString("base64")
      : entry))
    : parseAppleRootCertificates(rootCertificates);
  const normalizedAppAppleId = Number(appAppleId);
  if (!Number.isSafeInteger(normalizedAppAppleId) || normalizedAppAppleId <= 0) {
    throw providerConfigError("APPLE_CONFIGURATION_INVALID");
  }

  let library;
  try {
    library = await libraryLoader();
  } catch (_error) {
    throw providerConfigError("APPLE_LIBRARY_UNAVAILABLE");
  }
  if (
    typeof library?.SignedDataVerifier !== "function"
    || !library?.Environment?.PRODUCTION
    || !library?.Environment?.SANDBOX
  ) {
    throw providerConfigError("APPLE_LIBRARY_UNAVAILABLE");
  }

  let productionVerifier;
  let sandboxVerifier;
  try {
    productionVerifier = new library.SignedDataVerifier(
      roots,
      true,
      library.Environment.PRODUCTION,
      bundleId,
      normalizedAppAppleId,
    );
    sandboxVerifier = new library.SignedDataVerifier(
      roots,
      true,
      library.Environment.SANDBOX,
      bundleId,
      undefined,
    );
  } catch (_error) {
    throw providerConfigError("APPLE_CONFIGURATION_INVALID");
  }

  return Object.freeze({
    async verifyTransaction(signedTransactionInfo) {
      const signedTransaction = opaqueString(
        signedTransactionInfo,
        "APPLE_TRANSACTION_INVALID",
        200_000,
      );
      try {
        return await productionVerifier.verifyAndDecodeTransaction(signedTransaction);
      } catch (_productionError) {
        try {
          return await sandboxVerifier.verifyAndDecodeTransaction(signedTransaction);
        } catch (_sandboxError) {
          throw new StoreProviderError("APPLE_TRANSACTION_INVALID");
        }
      }
    },

    async verifyNotification(signedPayloadValue) {
      const signedPayload = opaqueString(
        signedPayloadValue,
        "APPLE_NOTIFICATION_INVALID",
        300_000,
      );
      try {
        return await productionVerifier.verifyAndDecodeNotification(signedPayload);
      } catch (_productionError) {
        try {
          return await sandboxVerifier.verifyAndDecodeNotification(signedPayload);
        } catch (_sandboxError) {
          throw new StoreProviderError("APPLE_NOTIFICATION_INVALID");
        }
      }
    },
  });
}

export function parseGoogleServiceAccount(value) {
  let parsed = value;
  if (typeof parsed === "string") {
    try {
      parsed = JSON.parse(parsed);
    } catch (_error) {
      throw providerConfigError("GOOGLE_CONFIGURATION_INVALID");
    }
  }
  if (
    !parsed
    || typeof parsed !== "object"
    || Array.isArray(parsed)
    || parsed.type !== "service_account"
    || typeof parsed.client_email !== "string"
    || !parsed.client_email.endsWith(".gserviceaccount.com")
    || typeof parsed.private_key !== "string"
    || !parsed.private_key.includes("BEGIN PRIVATE KEY")
  ) {
    throw providerConfigError("GOOGLE_CONFIGURATION_INVALID");
  }
  return Object.freeze({ ...parsed });
}

export async function createGooglePushTokenVerifier({
  audience,
  serviceAccountEmail,
  certificateFetcher,
  certificateLoaderOptions,
  libraryLoader = () => googleAuthLibrary,
} = {}) {
  let audienceUrl;
  try {
    audienceUrl = new URL(audience);
  } catch (_error) {
    throw providerConfigError("GOOGLE_PUSH_CONFIGURATION_INVALID");
  }
  if (
    audienceUrl.protocol !== "https:"
    || audienceUrl.username
    || audienceUrl.password
    || audienceUrl.hash
    || typeof serviceAccountEmail !== "string"
    || serviceAccountEmail.length > 254
    || !serviceAccountEmail.endsWith(".gserviceaccount.com")
  ) {
    throw providerConfigError("GOOGLE_PUSH_CONFIGURATION_INVALID");
  }
  let library;
  try {
    library = await libraryLoader();
  } catch (_error) {
    throw providerConfigError("GOOGLE_AUTH_LIBRARY_UNAVAILABLE");
  }
  if (typeof library?.OAuth2Client !== "function") {
    throw providerConfigError("GOOGLE_AUTH_LIBRARY_UNAVAILABLE");
  }
  const client = new library.OAuth2Client();
  const certificateLoader = typeof certificateFetcher === "function"
    ? createGoogleCertificateLoader({
      ...certificateLoaderOptions,
      fetcher: certificateFetcher,
    })
    : null;
  if (
    certificateLoader
    && typeof client.verifySignedJwtWithCertsAsync !== "function"
  ) {
    throw providerConfigError("GOOGLE_AUTH_LIBRARY_UNAVAILABLE");
  }
  const unauthorized = (diagnostic) => new StoreProviderError(
    "GOOGLE_PUSH_UNAUTHORIZED",
    { diagnostic },
  );

  return Object.freeze({
    async verifyAuthorization(authorizationValue) {
      if (
        typeof authorizationValue !== "string"
        || authorizationValue.length === 0
        || authorizationValue.length > 16_384
      ) {
        throw unauthorized("authorization_missing_or_oversize");
      }
      const match = /^[\t ]*Bearer[\t ]+([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)[\t ]*$/iu
        .exec(authorizationValue);
      if (!match) throw unauthorized("authorization_format_invalid");
      let payload;
      try {
        const ticket = certificateLoader
          ? await client.verifySignedJwtWithCertsAsync(
            match[1],
            await certificateLoader.load(),
            audienceUrl.toString(),
            GOOGLE_OIDC_ISSUERS,
          )
          : await client.verifyIdToken({
            idToken: match[1],
            audience: audienceUrl.toString(),
          });
        payload = ticket?.getPayload?.();
      } catch (error) {
        if (
          error instanceof StoreProviderError
          && error.code === "GOOGLE_PUSH_VERIFICATION_UNAVAILABLE"
        ) {
          throw error;
        }
        const diagnostic = googlePushVerificationDiagnostic(error);
        if (diagnostic === "id_token_certificate_fetch_failed") {
          throw googleCertificateUnavailable();
        }
        throw unauthorized(diagnostic);
      }
      if (!payload) throw unauthorized("claim_payload_missing");
      if (payload.email !== serviceAccountEmail) throw unauthorized("claim_email_mismatch");
      if (payload.email_verified !== true) throw unauthorized("claim_email_unverified");
      if (typeof payload.sub !== "string" || !payload.sub) {
        throw unauthorized("claim_subject_missing");
      }
      return Object.freeze({ verified: true });
    },
  });
}

function googleStatus(error) {
  const value = Number(error?.code ?? error?.response?.status ?? 0);
  return Number.isInteger(value) ? value : 0;
}

function googleVerificationError(error) {
  const status = googleStatus(error);
  if ([400, 404, 410].includes(status)) {
    return new StoreProviderError("GOOGLE_PURCHASE_NOT_FOUND");
  }
  return new StoreProviderError("GOOGLE_PLAY_UNAVAILABLE", { retryable: true });
}

function projectGoogleSubscription(data, packageName) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new StoreProviderError("GOOGLE_RESPONSE_INVALID");
  }
  return Object.freeze({
    packageName,
    subscriptionState: data.subscriptionState,
    acknowledgementState: data.acknowledgementState,
    startTime: data.startTime,
    lineItems: data.lineItems,
    linkedPurchaseToken: data.linkedPurchaseToken,
    externalAccountIdentifiers: data.externalAccountIdentifiers,
    testPurchase: data.testPurchase,
    etag: data.etag,
  });
}

export async function createGoogleSubscriptionVerifier({
  serviceAccount,
  packageName = APP_BUNDLE_ID,
  libraryLoader = () => googleAndroidPublisherLibrary,
} = {}) {
  const credentials = parseGoogleServiceAccount(serviceAccount);
  let library;
  try {
    library = await libraryLoader();
  } catch (_error) {
    throw providerConfigError("GOOGLE_LIBRARY_UNAVAILABLE");
  }
  if (
    typeof library?.auth?.GoogleAuth !== "function"
    || typeof library?.androidpublisher !== "function"
  ) {
    throw providerConfigError("GOOGLE_LIBRARY_UNAVAILABLE");
  }

  let publisher;
  try {
    const googleAuth = new library.auth.GoogleAuth({
      credentials,
      scopes: [GOOGLE_SCOPE],
    });
    publisher = library.androidpublisher({ version: "v3", auth: googleAuth });
  } catch (_error) {
    throw providerConfigError("GOOGLE_CONFIGURATION_INVALID");
  }
  if (
    typeof publisher?.purchases?.subscriptionsv2?.get !== "function"
    || typeof publisher?.purchases?.subscriptions?.acknowledge !== "function"
  ) {
    throw providerConfigError("GOOGLE_LIBRARY_UNAVAILABLE");
  }

  return Object.freeze({
    async getSubscription(purchaseTokenValue) {
      const purchaseToken = opaqueString(
        purchaseTokenValue,
        "GOOGLE_PURCHASE_INVALID",
      );
      try {
        const result = await publisher.purchases.subscriptionsv2.get({
          packageName,
          token: purchaseToken,
        });
        return projectGoogleSubscription(result?.data, packageName);
      } catch (error) {
        if (error instanceof StoreProviderError) throw error;
        throw googleVerificationError(error);
      }
    },

    async acknowledgeSubscription({ purchaseToken: purchaseTokenValue, productId }) {
      const purchaseToken = opaqueString(
        purchaseTokenValue,
        "GOOGLE_PURCHASE_INVALID",
      );
      const subscriptionId = opaqueString(productId, "GOOGLE_PURCHASE_INVALID", 160);
      try {
        await publisher.purchases.subscriptions.acknowledge({
          packageName,
          subscriptionId,
          token: purchaseToken,
          requestBody: {},
        });
      } catch (_error) {
        throw new StoreProviderError("GOOGLE_ACKNOWLEDGEMENT_UNAVAILABLE", { retryable: true });
      }
    },
  });
}
