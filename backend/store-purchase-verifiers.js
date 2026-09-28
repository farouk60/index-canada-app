import * as appleStoreServerLibrary from "@apple/app-store-server-library";
import * as googleAndroidPublisherLibrary from "@googleapis/androidpublisher";
import * as googleAuthLibrary from "google-auth-library";

import { APP_BUNDLE_ID } from "./store-purchase-core.js";

const GOOGLE_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/u;

export class StoreProviderError extends Error {
  constructor(code, { retryable = false } = {}) {
    super(code);
    this.name = "StoreProviderError";
    this.code = code;
    this.retryable = retryable;
  }
}

function providerConfigError(code) {
  return new StoreProviderError(code, { retryable: true });
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

  return Object.freeze({
    async verifyAuthorization(authorizationValue) {
      if (typeof authorizationValue !== "string" || authorizationValue.length > 16_384) {
        throw new StoreProviderError("GOOGLE_PUSH_UNAUTHORIZED");
      }
      const match = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/u.exec(authorizationValue);
      if (!match) throw new StoreProviderError("GOOGLE_PUSH_UNAUTHORIZED");
      try {
        const ticket = await client.verifyIdToken({
          idToken: match[1],
          audience: audienceUrl.toString(),
        });
        const payload = ticket?.getPayload?.();
        if (
          !payload
          || payload.email !== serviceAccountEmail
          || payload.email_verified !== true
          || typeof payload.sub !== "string"
          || !payload.sub
        ) {
          throw new StoreProviderError("GOOGLE_PUSH_UNAUTHORIZED");
        }
        return Object.freeze({ verified: true });
      } catch (error) {
        if (error instanceof StoreProviderError) throw error;
        throw new StoreProviderError("GOOGLE_PUSH_UNAUTHORIZED");
      }
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
