import assert from "node:assert/strict";
import test from "node:test";

import {
  StoreProviderError,
  createAppleTransactionVerifier,
  createGooglePushTokenVerifier,
  createGoogleSubscriptionVerifier,
  parseAppleRootCertificates,
  parseGoogleServiceAccount,
  safeStoreProviderDiagnostic,
} from "../store-purchase-verifiers.js";

const FAKE_PRIVATE_KEY = [
  ["-----BEGIN ", "PRIVATE KEY-----"].join(""),
  "opaque",
  ["-----END ", "PRIVATE KEY-----"].join(""),
  "",
].join("\n");

const GOOGLE_PUSH_AUDIENCE = "https://www.example.test/_functions/googlePlayRtdn";
const GOOGLE_PUSH_EMAIL = "push@example-project.iam.gserviceaccount.com";
const GOOGLE_PUSH_TOKEN = "sensitive-header.sensitive-payload.sensitive-signature";

async function rejectedError(action) {
  let rejection;
  try {
    await action();
  } catch (error) {
    rejection = error;
  }
  assert.ok(rejection, "l'action devait être rejetée");
  return rejection;
}

async function assertSafePushRejection(action, diagnostic, forbiddenValues = []) {
  const error = await rejectedError(action);
  assert.equal(error instanceof StoreProviderError, true);
  assert.equal(error.code, "GOOGLE_PUSH_UNAUTHORIZED");
  assert.equal(error.message, "GOOGLE_PUSH_UNAUTHORIZED");
  assert.equal(error.retryable, false);
  assert.equal(error.diagnostic, diagnostic);
  assert.equal(Object.prototype.propertyIsEnumerable.call(error, "diagnostic"), false);

  const accidentalSurface = [
    error.message,
    error.stack,
    JSON.stringify(error),
    ...Object.values(error).map(String),
  ].join("\n");
  for (const forbidden of forbiddenValues) {
    assert.equal(
      accidentalSurface.includes(forbidden),
      false,
      `la valeur sensible ne doit pas fuiter : ${forbidden}`,
    );
  }
  return error;
}

function googlePushLibrary({ payload, failure, calls = [] } = {}) {
  return {
    OAuth2Client: class {
      async verifyIdToken(parameters) {
        calls.push(parameters);
        if (failure) throw failure;
        return { getPayload: () => payload };
      }
    },
  };
}

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

test("les SDK Store statiques sont disponibles sans chargeur personnalisé", async () => {
  await assert.rejects(
    createAppleTransactionVerifier({
      rootCertificates: [Buffer.alloc(256, 1)],
      appAppleId: 1234567890,
    }),
    (error) => error instanceof StoreProviderError
      && error.code === "APPLE_CONFIGURATION_INVALID",
  );

  const pushVerifier = await createGooglePushTokenVerifier({
    audience: "https://www.example.test/_functions/googlePlayRtdn",
    serviceAccountEmail: "push@example-project.iam.gserviceaccount.com",
  });
  assert.equal(typeof pushVerifier.verifyAuthorization, "function");

  const purchaseVerifier = await createGoogleSubscriptionVerifier({
    serviceAccount: {
      type: "service_account",
      client_email: "iap-verifier@example-project.iam.gserviceaccount.com",
      private_key: FAKE_PRIVATE_KEY,
    },
  });
  assert.equal(typeof purchaseVerifier.getSubscription, "function");
  assert.equal(typeof purchaseVerifier.acknowledgeSubscription, "function");
});

test("le diagnostic OIDC accepte uniquement les catégories internes autorisées", () => {
  const diagnostics = [
    "authorization_missing_or_oversize",
    "authorization_format_invalid",
    "id_token_verification_failed",
    "claim_payload_missing",
    "claim_email_mismatch",
    "claim_email_unverified",
    "claim_subject_missing",
  ];
  for (const diagnostic of diagnostics) {
    assert.equal(safeStoreProviderDiagnostic(diagnostic), diagnostic);
  }

  const sensitiveDiagnostic = `id_token_verification_failed:${GOOGLE_PUSH_TOKEN}`;
  assert.equal(safeStoreProviderDiagnostic(sensitiveDiagnostic), "");
  const error = new StoreProviderError("GOOGLE_PUSH_UNAUTHORIZED", {
    diagnostic: sensitiveDiagnostic,
  });
  assert.equal("diagnostic" in error, false);
  assert.equal(JSON.stringify(error).includes(GOOGLE_PUSH_TOKEN), false);
});

test("le vérificateur OIDC classe un header absent ou surdimensionné sans appeler Google", async () => {
  let googleCalls = 0;
  const verifier = await createGooglePushTokenVerifier({
    audience: GOOGLE_PUSH_AUDIENCE,
    serviceAccountEmail: GOOGLE_PUSH_EMAIL,
    libraryLoader: async () => ({
      OAuth2Client: class {
        async verifyIdToken() {
          googleCalls += 1;
          assert.fail("Google ne doit pas être appelé pour un header rejeté localement");
        }
      },
    }),
  });
  const oversizeFragment = "oversized-sensitive-fragment";
  const oversizeHeader = `Bearer ${oversizeFragment.repeat(700)}`;

  for (const value of [undefined, "", oversizeHeader]) {
    await assertSafePushRejection(
      () => verifier.verifyAuthorization(value),
      "authorization_missing_or_oversize",
      [GOOGLE_PUSH_EMAIL, GOOGLE_PUSH_AUDIENCE, oversizeFragment],
    );
  }
  assert.equal(googleCalls, 0);
});

test("le vérificateur OIDC classe un format Bearer invalide sans fuite", async () => {
  const malformedToken = "malformed-sensitive-token-without-jwt-shape";
  const verifier = await createGooglePushTokenVerifier({
    audience: GOOGLE_PUSH_AUDIENCE,
    serviceAccountEmail: GOOGLE_PUSH_EMAIL,
    libraryLoader: async () => googlePushLibrary({
      failure: new Error("ne doit pas être appelée"),
    }),
  });

  await assertSafePushRejection(
    () => verifier.verifyAuthorization(`Bearer ${malformedToken}`),
    "authorization_format_invalid",
    [malformedToken, GOOGLE_PUSH_EMAIL, GOOGLE_PUSH_AUDIENCE],
  );
});

test("le vérificateur OIDC expurge l'échec brut de verifyIdToken", async () => {
  const rawProviderMessage = [
    "raw-google-verification-error",
    GOOGLE_PUSH_TOKEN,
    GOOGLE_PUSH_EMAIL,
    GOOGLE_PUSH_AUDIENCE,
  ].join(" | ");
  const calls = [];
  const verifier = await createGooglePushTokenVerifier({
    audience: GOOGLE_PUSH_AUDIENCE,
    serviceAccountEmail: GOOGLE_PUSH_EMAIL,
    libraryLoader: async () => googlePushLibrary({
      calls,
      failure: new Error(rawProviderMessage),
    }),
  });

  await assertSafePushRejection(
    () => verifier.verifyAuthorization(`Bearer ${GOOGLE_PUSH_TOKEN}`),
    "id_token_verification_failed",
    [
      rawProviderMessage,
      "raw-google-verification-error",
      GOOGLE_PUSH_TOKEN,
      GOOGLE_PUSH_EMAIL,
      GOOGLE_PUSH_AUDIENCE,
    ],
  );
  assert.deepEqual(calls, [{
    idToken: GOOGLE_PUSH_TOKEN,
    audience: GOOGLE_PUSH_AUDIENCE,
  }]);
});

test("le vérificateur OIDC distingue les claims invalides sans les recopier", async (t) => {
  const cases = [{
    name: "payload absent",
    payload: undefined,
    diagnostic: "claim_payload_missing",
    extraForbidden: [],
  }, {
    name: "email différent",
    payload: {
      email: "unexpected-sensitive-account@example-project.iam.gserviceaccount.com",
      email_verified: true,
      sub: "123456789012345678901",
    },
    diagnostic: "claim_email_mismatch",
    extraForbidden: ["unexpected-sensitive-account@example-project.iam.gserviceaccount.com"],
  }, {
    name: "email non vérifié",
    payload: {
      email: GOOGLE_PUSH_EMAIL,
      email_verified: false,
      sub: "123456789012345678901",
    },
    diagnostic: "claim_email_unverified",
    extraForbidden: [],
  }, {
    name: "subject absent",
    payload: {
      email: GOOGLE_PUSH_EMAIL,
      email_verified: true,
      sub: "",
    },
    diagnostic: "claim_subject_missing",
    extraForbidden: [],
  }];

  for (const current of cases) {
    await t.test(current.name, async () => {
      const verifier = await createGooglePushTokenVerifier({
        audience: GOOGLE_PUSH_AUDIENCE,
        serviceAccountEmail: GOOGLE_PUSH_EMAIL,
        libraryLoader: async () => googlePushLibrary({ payload: current.payload }),
      });
      await assertSafePushRejection(
        () => verifier.verifyAuthorization(`Bearer ${GOOGLE_PUSH_TOKEN}`),
        current.diagnostic,
        [
          GOOGLE_PUSH_TOKEN,
          GOOGLE_PUSH_EMAIL,
          GOOGLE_PUSH_AUDIENCE,
          ...current.extraForbidden,
        ],
      );
    });
  }
});

test("le vérificateur OIDC accepte un Bearer valide sans relâcher les claims", async () => {
  const calls = [];
  const verifier = await createGooglePushTokenVerifier({
    audience: GOOGLE_PUSH_AUDIENCE,
    serviceAccountEmail: GOOGLE_PUSH_EMAIL,
    libraryLoader: async () => googlePushLibrary({
      calls,
      payload: {
        email: GOOGLE_PUSH_EMAIL,
        email_verified: true,
        sub: "123456789012345678901",
      },
    }),
  });

  const result = await verifier.verifyAuthorization(`  bearer\t${GOOGLE_PUSH_TOKEN}  `);
  assert.deepEqual(result, { verified: true });
  assert.deepEqual(calls, [{
    idToken: GOOGLE_PUSH_TOKEN,
    audience: GOOGLE_PUSH_AUDIENCE,
  }]);
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
