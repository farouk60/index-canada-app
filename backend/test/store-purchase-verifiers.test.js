import assert from "node:assert/strict";
import test from "node:test";

import {
  StoreProviderError,
  createAppleTransactionVerifier,
  createGoogleSubscriptionVerifier,
  parseAppleRootCertificates,
  parseGoogleServiceAccount,
} from "../store-purchase-verifiers.js";

const FAKE_PRIVATE_KEY = [
  ["-----BEGIN ", "PRIVATE KEY-----"].join(""),
  "opaque",
  ["-----END ", "PRIVATE KEY-----"].join(""),
  "",
].join("\n");

test("les certificats Apple distincts sont décodés en DER sans accepter une configuration vide", () => {
  const certificates = [1, 2, 3]
    .map((value) => Buffer.alloc(256, value).toString("base64"));
  const roots = parseAppleRootCertificates(certificates);
  assert.equal(roots.length, 3);
  assert.equal(roots.every((root) => Buffer.isBuffer(root)), true);
  assert.deepEqual(roots.map((root) => root[0]), [1, 2, 3]);
  assert.equal(roots.every((root) => root.length === 256), true);
  assert.throws(() => parseAppleRootCertificates("[]"), StoreProviderError);
  assert.throws(() => parseAppleRootCertificates("not-json"), StoreProviderError);
});

test("l'adaptateur Apple utilise exclusivement SignedDataVerifier officiel", async () => {
  const calls = [];
  class FakeSignedDataVerifier {
    constructor(roots, online, environment, bundleId, appAppleId) {
      this.environment = environment;
      calls.push({ roots, online, environment, bundleId, appAppleId });
    }

    async verifyAndDecodeTransaction(value) {
      if (this.environment === "PRODUCTION") throw new Error("signature invalide en production");
      return { transactionId: "sandbox-transaction", signedValueSeen: value };
    }
  }
  const verifier = await createAppleTransactionVerifier({
    rootCertificates: [Buffer.alloc(256, 1)],
    appAppleId: 1234567890,
    libraryLoader: async () => ({
      Environment: { PRODUCTION: "PRODUCTION", SANDBOX: "SANDBOX" },
      SignedDataVerifier: FakeSignedDataVerifier,
    }),
  });

  const decoded = await verifier.verifyTransaction("header.payload.signature");
  assert.equal(decoded.transactionId, "sandbox-transaction");
  assert.deepEqual(calls.map((call) => call.environment), ["PRODUCTION", "SANDBOX"]);
  assert.equal(calls.every((call) => call.online === true), true);
  assert.equal(calls.every((call) => call.bundleId === "ca.indexcanada.app"), true);
});

test("le compte de service Google est validé sans exposer sa clé", () => {
  const parsed = parseGoogleServiceAccount(JSON.stringify({
    type: "service_account",
    client_email: "iap-verifier@example-project.iam.gserviceaccount.com",
    private_key: FAKE_PRIVATE_KEY,
  }));
  assert.equal(parsed.type, "service_account");
  assert.equal(parsed.client_email.endsWith(".gserviceaccount.com"), true);
  assert.throws(() => parseGoogleServiceAccount("{}"), StoreProviderError);
});

test("l'adaptateur Google appelle subscriptionsv2.get puis acknowledge avec le package fixe", async () => {
  const calls = [];
  class FakeGoogleAuth {
    constructor(options) {
      calls.push({ method: "auth", options });
    }
  }
  const api = {
    purchases: {
      subscriptionsv2: {
        async get(parameters) {
          calls.push({ method: "get", parameters });
          return { data: {
            subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
            linkedPurchaseToken: "predecessor-purchase-token",
          } };
        },
      },
      subscriptions: {
        async acknowledge(parameters) {
          calls.push({ method: "acknowledge", parameters });
          return { data: {} };
        },
      },
    },
  };
  const verifier = await createGoogleSubscriptionVerifier({
    serviceAccount: {
      type: "service_account",
      client_email: "iap-verifier@example-project.iam.gserviceaccount.com",
      private_key: FAKE_PRIVATE_KEY,
    },
    libraryLoader: async () => ({
      auth: { GoogleAuth: FakeGoogleAuth },
      androidpublisher(options) {
        calls.push({ method: "client", options });
        return api;
      },
    }),
  });

  const response = await verifier.getSubscription("purchase-token");
  assert.equal(response.packageName, "ca.indexcanada.app");
  assert.equal(response.subscriptionState, "SUBSCRIPTION_STATE_ACTIVE");
  assert.equal(response.linkedPurchaseToken, "predecessor-purchase-token");
  await verifier.acknowledgeSubscription({
    purchaseToken: "purchase-token",
    productId: "ca.indexcanada.app.premium.annual",
  });

  const getCall = calls.find((call) => call.method === "get");
  assert.deepEqual(getCall.parameters, {
    packageName: "ca.indexcanada.app",
    token: "purchase-token",
  });
  const acknowledgeCall = calls.find((call) => call.method === "acknowledge");
  assert.deepEqual(acknowledgeCall.parameters, {
    packageName: "ca.indexcanada.app",
    subscriptionId: "ca.indexcanada.app.premium.annual",
    token: "purchase-token",
    requestBody: {},
  });
  const authCall = calls.find((call) => call.method === "auth");
  assert.deepEqual(authCall.options.scopes, ["https://www.googleapis.com/auth/androidpublisher"]);
});

test("les erreurs Google sont classées sans recopier le jeton dans l'erreur", async () => {
  const verifier = await createGoogleSubscriptionVerifier({
    serviceAccount: {
      type: "service_account",
      client_email: "iap-verifier@example-project.iam.gserviceaccount.com",
      private_key: FAKE_PRIVATE_KEY,
    },
    libraryLoader: async () => ({
      auth: { GoogleAuth: class {} },
      androidpublisher: () => ({
        purchases: {
          subscriptionsv2: {
            async get() {
              const error = new Error("purchase-token-is-invalid");
              error.code = 404;
              throw error;
            },
          },
          subscriptions: { acknowledge: async () => ({}) },
        },
      }),
    }),
  });

  await assert.rejects(
    verifier.getSubscription("purchase-token-is-invalid"),
    (error) => error instanceof StoreProviderError
      && error.code === "GOOGLE_PURCHASE_NOT_FOUND"
      && error.retryable === false
      && !error.message.includes("purchase-token-is-invalid"),
  );
});
