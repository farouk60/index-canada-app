import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";

register("./wix-test-loader.mjs", import.meta.url);

const { __wixDataTest } = await import("wix-data");
const {
  get_categories,
  get_offers,
  get_partners,
  get_professionals,
  get_reviews,
  get_search_professionals,
  get_searchProfessionals,
  persistEngagementEvent,
  post_appStoreServerNotificationV2,
  post_confirmStorePurchase,
  post_createStoreCheckout,
  post_engagementEvent,
  post_googlePlayRtdn,
  post_restoreStorePurchase,
  use_categories,
  use_engagementEvent,
  use_professionals,
  use_search_professionals,
  use_searchProfessionals,
  use_confirmStorePurchase,
  use_createStoreCheckout,
  use_appStoreServerNotificationV2,
  use_googlePlayRtdn,
  use_restoreStorePurchase,
} = await import("../http-functions.js");
const {
  buildEngagementEventRecord,
  buildPersistedCheckoutDraft,
} = await import("../security-core.js");
const {
  APP_BUNDLE_ID,
  createStoreCheckoutDraft,
  deriveStoreAccountToken,
} = await import("../store-purchase-core.js");

const TEST_SIGNING_SECRET = "test-only-CHECKOUT_SIGNING_SECRET-secret-with-more-than-thirty-two-characters";

const PUBLIC_REQUEST = Object.freeze({
  ip: "203.0.113.25",
  method: "GET",
  query: Object.freeze({}),
});

function request(query = {}, overrides = {}) {
  return {
    ...PUBLIC_REQUEST,
    ...overrides,
    query,
  };
}

function engagementRequest(body, overrides = {}) {
  return request({}, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: { json: async () => body },
    ...overrides,
  });
}

function seed(data = {}) {
  __wixDataTest.reset({
    ApiRateLimits: [],
    EngagementEvents: [],
    Entitlements: [],
    PaymentEvents: [],
    PaymentCheckouts: [],
    SousCategorie: [],
    Professionnel: [],
    Reviews: [],
    Partenaires: [],
    OffresPartenaire: [],
    ...data,
  });
}

function storeRegistration(overrides = {}) {
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

function storePostRequest(body) {
  return request({}, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: { json: async () => body },
  });
}

function flattenOperations(operations) {
  return operations.flatMap((operation) => [
    operation,
    ...flattenOperations(operation.operations ?? []),
  ]);
}

test.beforeEach(() => seed());

test("get_categories masque les catégories désactivées et applique la projection publique", async () => {
  seed({
    SousCategorie: [
      { _id: "cat_001", title: "Droit", titleEn: "Law", internalNote: "privé" },
      { _id: "cat_002", title: "Inactive", isActive: false },
      { _id: "cat_003", title: "Désactivée", disabled: true },
      { _id: "cat_004", title: "Santé", isActive: true },
    ],
  });

  const result = await get_categories(request({ limit: "25" }));

  assert.equal(result.status, 200);
  assert.deepEqual(result.body.categories, [
    { _id: "cat_001", title: "Droit", titleEn: "Law" },
    { _id: "cat_004", title: "Santé" },
  ]);
  assert.equal(JSON.stringify(result.body).includes("internalNote"), false);
  assert.deepEqual(result.body.pagination, {
    limit: 25,
    has_more: false,
    next_cursor: null,
  });
});

test("get_professionals filtre les fiches actives et reprend après le curseur avec gt", async () => {
  seed({
    Professionnel: [
      {
        _id: "pro_001",
        title: "Cabinet Alpha",
        isActive: true,
        paymentId: "pi_secret_alpha",
      },
      { _id: "pro_002", title: "Cabinet inactif", isActive: false },
      {
        _id: "pro_003",
        title: "Cabinet Bravo",
        isActive: true,
        registrationFingerprint: "empreinte-privée",
      },
    ],
  });

  const firstPage = await get_professionals(request({ limit: "1" }));
  const cursor = firstPage.body.pagination.next_cursor;

  assert.equal(firstPage.status, 200);
  assert.deepEqual(firstPage.body.professionals, [{
    _id: "pro_001",
    title: "Cabinet Alpha",
    isActive: true,
  }]);
  assert.equal(firstPage.body.pagination.has_more, true);
  assert.equal(typeof cursor, "string");
  assert.equal(JSON.stringify(firstPage.body).includes("paymentId"), false);

  const secondPage = await get_professionals(request({ limit: "1", cursor }));

  assert.equal(secondPage.status, 200);
  assert.deepEqual(secondPage.body.professionals, [{
    _id: "pro_003",
    title: "Cabinet Bravo",
    isActive: true,
  }]);
  assert.equal(secondPage.body.pagination.has_more, false);
  assert.equal(JSON.stringify(secondPage.body).includes("registrationFingerprint"), false);

  const professionalFinds = __wixDataTest.calls.filter(
    (call) => call.type === "find" && call.collection === "Professionnel",
  );
  assert.equal(professionalFinds.some((call) => call.operations.some(
    (operation) => operation.method === "eq"
      && operation.field === "isActive"
      && operation.value === true,
  )), true);
  assert.equal(professionalFinds.some((call) => call.operations.some(
    (operation) => operation.method === "gt"
      && operation.field === "_id"
      && operation.value === "pro_001",
  )), true);
});

test("get_searchProfessionals expose la route Wix documentée et masque les champs privés", async () => {
  seed({
    Professionnel: [
      {
        _id: "pro_search_001",
        title: "Cabinet Alpha Immigration",
        category: "Immigration",
        ville: "Montréal",
        isActive: true,
        paymentId: "pi_secret_alpha",
      },
      {
        _id: "pro_search_002",
        title: "Cabinet masqué",
        category: "Immigration",
        isActive: false,
      },
    ],
  });

  const result = await get_searchProfessionals(request({ search: "Alpha" }));

  assert.equal(result.status, 200);
  assert.equal(result.body.searchStats.totalFound, 1);
  assert.deepEqual(result.body.professionnels, [{
    _id: "pro_search_001",
    title: "Cabinet Alpha Immigration",
    category: "Immigration",
    ville: "Montréal",
    isActive: true,
    searchScore: 180,
  }]);
  assert.equal(JSON.stringify(result.body).includes("paymentId"), false);

  const legacyResult = await get_search_professionals(request({ search: "Alpha" }));
  assert.deepEqual(legacyResult.body, result.body);
});

test("get_searchProfessionals exige au moins un critère de recherche", async () => {
  const result = await get_searchProfessionals(request());

  assert.equal(result.status, 400);
  assert.equal(result.body.code, "SEARCH_CRITERION_REQUIRED");
});

test("get_reviews accepte les alias historiques mais ne publie que les avis approuvés", async () => {
  seed({
    Professionnel: [{ _id: "pro_001", title: "Cabinet Alpha", isActive: true }],
    Reviews: [
      {
        _id: "review_001",
        professionnelId: "pro_001",
        isApproved: true,
        title: "Excellent",
        internalNote: "privé",
      },
      {
        _id: "review_002",
        image: "pro_001",
        moderationStatus: "approved",
        message: "Très bon service",
      },
      {
        _id: "review_003",
        professionalId: "pro_001",
        moderationStatus: "pending",
        message: "À modérer",
      },
      {
        _id: "review_004",
        professionalId: "pro_999",
        isApproved: true,
        message: "Autre fiche",
      },
    ],
  });

  const result = await get_reviews(request({ professionalId: "pro_001", limit: "25" }));

  assert.equal(result.status, 200);
  assert.deepEqual(result.body.reviews, [
    { _id: "review_001", title: "Excellent", professionalId: "pro_001" },
    { _id: "review_002", message: "Très bon service", professionalId: "pro_001" },
  ]);
  assert.equal(JSON.stringify(result.body).includes("internalNote"), false);
  assert.equal(JSON.stringify(result.body).includes("À modérer"), false);

  const reviewFind = __wixDataTest.calls.find(
    (call) => call.type === "find" && call.collection === "Reviews",
  );
  const operations = flattenOperations(reviewFind?.operations ?? []);
  assert.equal(operations.some((operation) => operation.method === "eq"
    && operation.field === "isApproved"
    && operation.value === true), true);
  assert.equal(operations.some((operation) => operation.method === "eq"
    && operation.field === "moderationStatus"
    && operation.value === "approved"), true);
  assert.deepEqual(
    operations
      .filter((operation) => operation.method === "eq" && [
        "professionalId",
        "professionnelId",
        "image",
      ].includes(operation.field))
      .map((operation) => operation.field)
      .sort(),
    ["image", "professionalId", "professionnelId"],
  );
});

test("get_reviews accepte l'ancien professionalId dans request.path", async () => {
  seed({
    Professionnel: [{ _id: "pro_legacy", title: "Cabinet historique", isActive: true }],
    Reviews: [{
      _id: "review_legacy",
      professionalId: "pro_legacy",
      isApproved: true,
      message: "Avis historique",
    }],
  });

  const result = await get_reviews(request({}, { path: ["pro_legacy"] }));

  assert.equal(result.status, 200);
  assert.deepEqual(result.body.reviews, [{
    _id: "review_legacy",
    message: "Avis historique",
    professionalId: "pro_legacy",
  }]);
});

test("get_reviews refuse les identifiants contradictoires ou un chemin ambigu", async () => {
  seed({
    Professionnel: [
      { _id: "pro_query", title: "Cabinet actuel", isActive: true },
      { _id: "pro_path", title: "Cabinet historique", isActive: true },
    ],
  });

  const queryPathConflict = await get_reviews(request(
    { professionalId: "pro_query" },
    { path: ["pro_path"] },
  ));
  const queryAliasConflict = await get_reviews(request({
    professionalId: "pro_query",
    professionnelId: "pro_path",
  }));
  const multiSegmentPath = await get_reviews(request({}, {
    path: ["pro_path", "segment-inattendu"],
  }));

  for (const result of [queryPathConflict, queryAliasConflict, multiSegmentPath]) {
    assert.equal(result.status, 400);
    assert.equal(result.body.code, "INVALID_SEARCH");
  }
});

test("les routes v2 retournent 400 pour une taille ou un curseur de pagination invalide", async () => {
  const invalidLimit = await get_categories(request({ limit: "101" }));
  const invalidCursor = await get_categories(request({ cursor: "curseur-altéré!" }));

  assert.equal(invalidLimit.status, 400);
  assert.equal(invalidLimit.body.code, "INVALID_PAGE_SIZE");
  assert.equal(invalidCursor.status, 400);
  assert.equal(invalidCursor.body.code, "INVALID_CURSOR");
});

test("get_reviews retourne 404 quand le professionnel est absent ou inactif", async () => {
  seed({
    Professionnel: [{ _id: "pro_inactive", title: "Masqué", isActive: false }],
  });

  const absent = await get_reviews(request({ professionalId: "pro_absent" }));
  const inactive = await get_reviews(request({ professionalId: "pro_inactive" }));

  for (const result of [absent, inactive]) {
    assert.equal(result.status, 404);
    assert.equal(result.body.success, false);
    assert.equal(result.body.code, "PROFESSIONAL_NOT_FOUND");
  }
});

test("get_partners publie uniquement les partenaires actifs et officiels", async () => {
  seed({
    Partenaires: [
      {
        _id: "partner_001",
        title: "Partenaire Alpha",
        isActive: true,
        isOfficial: true,
        website: "https://alpha.example.ca",
        internalAccountId: "account-secret-alpha",
      },
      {
        _id: "partner_002",
        title: "Partenaire inactif",
        isActive: false,
        isOfficial: true,
      },
      {
        _id: "partner_003",
        title: "Partenaire non officiel",
        isActive: true,
        isOfficial: false,
      },
      {
        _id: "partner_004",
        title: "Partenaire Bravo",
        isActive: true,
        isOfficial: true,
        internalAccountId: "account-secret-bravo",
      },
    ],
  });

  const result = await get_partners(request({ limit: "1" }));

  assert.equal(result.status, 200);
  assert.deepEqual(result.body.partners, [{
    _id: "partner_001",
    title: "Partenaire Alpha",
    website: "https://alpha.example.ca",
    isOfficial: true,
    isActive: true,
  }]);
  assert.equal(JSON.stringify(result.body).includes("internalAccountId"), false);
  assert.equal(result.body.pagination.limit, 1);
  assert.equal(result.body.pagination.has_more, true);
  assert.equal(typeof result.body.pagination.next_cursor, "string");
});

test("get_offers publie uniquement les offres actives avec une projection publique", async () => {
  seed({
    OffresPartenaire: [
      {
        _id: "offer_001",
        title: "Rabais installation",
        partnerId: "partner_001",
        isActive: true,
        internalMargin: 42,
      },
      {
        _id: "offer_002",
        title: "Brouillon",
        partnerId: "partner_001",
        isActive: false,
      },
      {
        _id: "offer_003",
        title: "État absent",
        partnerId: "partner_001",
      },
    ],
  });

  const result = await get_offers(request({ limit: "25" }));

  assert.equal(result.status, 200);
  assert.deepEqual(result.body.offers, [{
    _id: "offer_001",
    title: "Rabais installation",
    partnerId: "partner_001",
  }]);
  assert.equal(JSON.stringify(result.body).includes("internalMargin"), false);
  assert.deepEqual(result.body.pagination, {
    limit: 25,
    has_more: false,
    next_cursor: null,
  });
});

test("post_engagementEvent enregistre un événement ROI minimal avec un horodatage serveur", async () => {
  seed({
    Professionnel: [{ _id: "pro_001", title: "Cabinet Alpha", isActive: true }],
  });
  const body = {
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174010",
    type: "professional_view",
    professionalId: "pro_001",
    placement: "detail",
    locale: "fr",
  };

  const result = await post_engagementEvent(engagementRequest(body));

  assert.equal(result.status, 201);
  assert.equal(result.body.received, true);
  const events = __wixDataTest.items("EngagementEvents");
  assert.equal(events.length, 1);
  assert.match(events[0]._id, /^eng_[a-f0-9]{32}$/u);
  assert.match(events[0].contentHash, /^[a-f0-9]{64}$/u);
  assert.equal(events[0].professionalId, "pro_001");
  assert.equal(events[0].type, "professional_view");
  assert.equal(events[0].trustLevel, "client_reported_unverified");
  assert.equal(events[0].receivedAt instanceof Date, true);
  assert.equal(Object.hasOwn(events[0], "eventId"), false);
  assert.equal(Object.hasOwn(events[0], "email"), false);

  const insert = __wixDataTest.calls.find(
    (call) => call.type === "insert" && call.collection === "EngagementEvents",
  );
  assert.deepEqual(insert.options, { suppressAuth: true });
});

test("post_engagementEvent est idempotent et refuse un même eventId au contenu différent", async () => {
  seed({
    Professionnel: [{ _id: "pro_001", title: "Cabinet Alpha", isActive: true }],
  });
  const body = {
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174011",
    type: "professional_click",
    professionalId: "pro_001",
    placement: "home_featured",
    locale: "en",
  };

  const createdResult = await post_engagementEvent(engagementRequest(body));
  const duplicateResult = await post_engagementEvent(engagementRequest(body));
  const conflictResult = await post_engagementEvent(engagementRequest({
    ...body,
    locale: "fr",
  }));

  assert.equal(createdResult.status, 201);
  assert.equal(duplicateResult.status, 200);
  assert.equal(duplicateResult.body.duplicate, true);
  assert.equal(conflictResult.status, 409);
  assert.equal(conflictResult.body.code, "ENGAGEMENT_EVENT_CONFLICT");
  assert.equal(__wixDataTest.items("EngagementEvents").length, 1);
});

test("persistEngagementEvent relit après toute erreur d'insertion", async () => {
  const record = {
    _id: "eng_1234567890abcdef1234567890abcdef",
    version: 1,
    type: "professional_view",
    professionalId: "pro_001",
    placement: "detail",
    contentHash: "a".repeat(64),
    receivedAt: new Date("2026-09-23T14:00:00.000Z"),
  };
  const insertError = new Error("Wix write timeout");

  let reads = 0;
  const sameContent = await persistEngagementEvent(record, {
    findExisting: async () => {
      reads += 1;
      return reads === 1 ? null : { ...record };
    },
    insertRecord: async () => {
      throw insertError;
    },
  });
  assert.deepEqual(sameContent, { duplicate: true });
  assert.equal(reads, 2);

  reads = 0;
  await assert.rejects(
    persistEngagementEvent(record, {
      findExisting: async () => {
        reads += 1;
        return reads === 1 ? null : { ...record, contentHash: "b".repeat(64) };
      },
      insertRecord: async () => {
        throw insertError;
      },
    }),
    (error) => error?.code === "ENGAGEMENT_EVENT_CONFLICT" && error?.status === 409,
  );

  reads = 0;
  await assert.rejects(
    persistEngagementEvent(record, {
      findExisting: async () => {
        reads += 1;
        return null;
      },
      insertRecord: async () => {
        throw insertError;
      },
    }),
    (error) => error?.code === "ENGAGEMENT_PERSISTENCE_UNCERTAIN" && error?.status === 503,
  );
  assert.equal(reads, 2);
});

test("persistEngagementEvent journalise sans donnée sensible une insertion ambiguë récupérée", async () => {
  const rawEventId = "00000000-0000-4000-8000-000000000123";
  const email = "fixture@example.invalid";
  const professionalId = "pro_fixture_001";
  const record = buildEngagementEventRecord({
    version: 1,
    eventId: rawEventId,
    type: "professional_view",
    professionalId,
    placement: "detail",
    locale: "fr",
  }, new Date("2030-01-01T00:00:00.000Z"));
  const insertError = Object.assign(
    new Error(`Wix write timeout after commit for ${email}`),
    { code: "private-token-123" },
  );
  const recoveredLogs = [];
  let reads = 0;

  const result = await persistEngagementEvent(record, {
    findExisting: async () => {
      reads += 1;
      return reads === 1 ? null : { ...record };
    },
    insertRecord: async () => {
      throw insertError;
    },
    logRecovered: (entry) => recoveredLogs.push(entry),
  });

  assert.deepEqual(result, { duplicate: true });

  assert.equal(reads, 2);
  assert.deepEqual(recoveredLogs, [{
    event: "engagement_persistence_recovered",
    recordId: record._id,
    eventType: record.type,
    errorCode: "INSERT_ERROR",
  }]);

  const [logEntry] = recoveredLogs;
  for (const forbiddenField of [
    "record",
    "contentHash",
    "professionalId",
    "eventId",
    "email",
    "message",
  ]) {
    assert.equal(Object.hasOwn(logEntry, forbiddenField), false);
  }
  const serializedLog = JSON.stringify(logEntry);
  assert.equal(serializedLog.includes(rawEventId), false);
  assert.equal(serializedLog.includes(email), false);
  assert.equal(serializedLog.includes(professionalId), false);
  assert.equal(serializedLog.includes(insertError.message), false);
  assert.equal(serializedLog.includes(insertError.code), false);
});

test("persistEngagementEvent reste idempotent si le logger de récupération échoue", async () => {
  const record = buildEngagementEventRecord({
    version: 1,
    eventId: "00000000-0000-4000-8000-000000000124",
    type: "search",
    placement: "directory",
    resultsBucket: "0",
    searchKind: "category",
  }, new Date("2030-01-01T00:01:00.000Z"));
  let reads = 0;

  const result = await persistEngagementEvent(record, {
    findExisting: async () => {
      reads += 1;
      return reads === 1 ? null : { ...record };
    },
    insertRecord: async () => {
      throw Object.assign(new Error("already exists"), { code: "WDE0074" });
    },
    logRecovered: () => {
      throw new Error("logging unavailable");
    },
  });

  assert.deepEqual(result, { duplicate: true });
  assert.equal(reads, 2);
});

test("persistEngagementEvent ne journalise pas le doublon normal", async () => {
  const record = buildEngagementEventRecord({
    version: 1,
    eventId: "00000000-0000-4000-8000-000000000125",
    type: "search",
    placement: "directory",
    resultsBucket: "1-5",
    searchKind: "text",
  }, new Date("2030-01-01T00:02:00.000Z"));
  let insertCalled = false;
  let recoveryLogCount = 0;

  const result = await persistEngagementEvent(record, {
    findExisting: async () => ({ ...record }),
    insertRecord: async () => {
      insertCalled = true;
      return record;
    },
    logRecovered: () => {
      recoveryLogCount += 1;
    },
  });

  assert.deepEqual(result, { duplicate: true });

  assert.equal(insertCalled, false);
  assert.equal(recoveryLogCount, 0);
});

test("persistEngagementEvent retourne 503 si la relecture après erreur échoue", async () => {
  const record = {
    _id: "eng_1234567890abcdef1234567890abcdef",
    contentHash: "a".repeat(64),
  };
  let reads = 0;

  await assert.rejects(
    persistEngagementEvent(record, {
      findExisting: async () => {
        reads += 1;
        if (reads === 1) return null;
        throw new Error("Wix read timeout");
      },
      insertRecord: async () => {
        throw new Error("Wix write timeout");
      },
    }),
    (error) => error?.code === "ENGAGEMENT_PERSISTENCE_UNCERTAIN" && error?.status === 503,
  );
  assert.equal(reads, 2);
});

test("post_engagementEvent valide la fiche active et rejette les PII", async () => {
  seed({
    Professionnel: [{ _id: "pro_inactive", title: "Masqué", isActive: false }],
  });
  const base = {
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174012",
    type: "contact",
    placement: "detail",
    channel: "website",
  };
  const absent = await post_engagementEvent(engagementRequest({
    ...base,
    professionalId: "pro_absent",
  }));
  const inactive = await post_engagementEvent(engagementRequest({
    ...base,
    eventId: "123e4567-e89b-42d3-a456-426614174013",
    professionalId: "pro_inactive",
  }));
  const pii = await post_engagementEvent(engagementRequest({
    ...base,
    eventId: "123e4567-e89b-42d3-a456-426614174014",
    professionalId: "pro_inactive",
    email: "owner@example.ca",
  }));

  for (const result of [absent, inactive]) {
    assert.equal(result.status, 404);
    assert.equal(result.body.code, "PROFESSIONAL_NOT_FOUND");
  }
  assert.equal(pii.status, 400);
  assert.equal(pii.body.code, "INVALID_ENGAGEMENT_EVENT");
  assert.equal(__wixDataTest.items("EngagementEvents").length, 0);
});

test("post_engagementEvent applique son limiteur dédié", async () => {
  seed({
    Professionnel: [{ _id: "pro_001", title: "Cabinet Alpha", isActive: true }],
  });
  const first = await post_engagementEvent(engagementRequest({
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174015",
    type: "professional_impression",
    professionalId: "pro_001",
    placement: "directory",
  }));
  assert.equal(first.status, 201);
  assert.equal(__wixDataTest.items("ApiRateLimits")[0].limit, 60);

  const saturatedLimit = {
    ...__wixDataTest.items("ApiRateLimits")[0],
    count: 999,
    windowStartedAtMs: Date.now(),
  };
  seed({
    ApiRateLimits: [saturatedLimit],
    Professionnel: [{ _id: "pro_001", title: "Cabinet Alpha", isActive: true }],
  });
  const limited = await post_engagementEvent(engagementRequest({
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174016",
    type: "professional_impression",
    professionalId: "pro_001",
    placement: "directory",
  }));

  assert.equal(limited.status, 429);
  assert.equal(limited.body.code, "RATE_LIMITED");
  assert.equal(__wixDataTest.items("EngagementEvents").length, 0);
});

test("les handlers use_* distinguent OPTIONS des méthodes non autorisées", () => {
  const preflight = use_categories(request({}, { method: "OPTIONS" }));
  const rejected = use_professionals(request({}, { method: "POST" }));
  const searchPreflight = use_searchProfessionals(request({}, { method: "OPTIONS" }));
  const legacySearchPreflight = use_search_professionals(request({}, { method: "OPTIONS" }));
  const rejectedSearch = use_searchProfessionals(request({}, { method: "POST" }));
  const engagementPreflight = use_engagementEvent(request({}, { method: "OPTIONS" }));
  const rejectedEngagement = use_engagementEvent(request({}, { method: "GET" }));

  assert.equal(preflight.status, 204);
  assert.equal(preflight.body, null);
  assert.equal(preflight.headers["Access-Control-Allow-Methods"], "GET, OPTIONS");
  assert.equal(rejected.status, 405);
  assert.equal(rejected.body.code, "METHOD_NOT_ALLOWED");
  assert.equal(searchPreflight.status, 204);
  assert.equal(searchPreflight.headers["Access-Control-Allow-Methods"], "GET, OPTIONS");
  assert.equal(legacySearchPreflight.status, 204);
  assert.equal(rejectedSearch.status, 405);
  assert.equal(rejectedSearch.body.code, "METHOD_NOT_ALLOWED");
  assert.equal(engagementPreflight.status, 204);
  assert.equal(engagementPreflight.headers["Access-Control-Allow-Methods"], "POST, OPTIONS");
  assert.equal(rejectedEngagement.status, 405);
  assert.equal(rejectedEngagement.body.code, "METHOD_NOT_ALLOWED");
});

test("le répertoire masque les droits magasin expirés ou révoqués même si la modération reste active", async () => {
  const future = new Date(Date.now() + 60_000).toISOString();
  const past = new Date(Date.now() - 1).toISOString();
  seed({
    Professionnel: [
      {
        _id: "pro_apple_active",
        title: "Apple visible",
        isActive: true,
        sponsor: true,
        paymentProvider: "apple",
        entitlementStatus: "active",
        entitlementExpiresAt: future,
      },
      {
        _id: "pro_google_expired",
        title: "Google expiré",
        isActive: true,
        sponsor: true,
        paymentProvider: "google",
        entitlementStatus: "active",
        entitlementExpiresAt: past,
      },
      {
        _id: "pro_apple_revoked",
        title: "Apple révoqué",
        isActive: true,
        sponsor: true,
        paymentProvider: "apple",
        entitlementStatus: "revoked",
        entitlementExpiresAt: future,
      },
      {
        _id: "pro_stripe_legacy",
        title: "Stripe historique",
        isActive: true,
        sponsor: true,
        paymentProvider: "stripe",
      },
    ],
  });

  const result = await get_professionals(request({ featured: "true", limit: "25" }));

  assert.equal(result.status, 200);
  assert.deepEqual(result.body.professionals.map((item) => item._id), [
    "pro_apple_active",
    "pro_stripe_legacy",
  ]);
  assert.equal(JSON.stringify(result.body).includes("pro_google_expired"), false);
  assert.equal(JSON.stringify(result.body).includes("pro_apple_revoked"), false);
});

test("post_createStoreCheckout retourne un account_token dérivé sans le persister", async () => {
  const body = {
    ...storeRegistration(),
    planId: "premium",
    store: "app_store",
  };
  const draft = createStoreCheckoutDraft(body, TEST_SIGNING_SECRET, Date.now());
  const persisted = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  seed({
    PaymentCheckouts: [persisted],
    SousCategorie: [{ _id: "legal-services", isActive: true }],
  });

  const result = await post_createStoreCheckout(storePostRequest(body));

  assert.equal(result.status, 200);
  assert.equal(result.body.success, true);
  assert.equal(result.body.checkout_id, persisted._id);
  assert.equal(result.body.store, "app_store");
  assert.equal(result.body.product_id, "ca.indexcanada.app.premium.annual");
  assert.equal(result.body.account_token, deriveStoreAccountToken(persisted, TEST_SIGNING_SECRET));
  assert.match(result.body.account_token, /^[a-f0-9-]{36}$/u);
  const stored = __wixDataTest.items("PaymentCheckouts")[0];
  assert.equal(JSON.stringify(stored).includes(result.body.account_token), false);
  assert.equal(Object.hasOwn(stored, "appAccountToken"), false);
  assert.equal(Object.hasOwn(stored, "verificationData"), false);
});

test("post_confirmStorePurchase livre un droit idempotent avant une fiche toujours à modérer", async () => {
  const body = {
    ...storeRegistration(),
    planId: "premium",
    store: "google_play",
  };
  const draft = createStoreCheckoutDraft(body, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  seed({ PaymentCheckouts: [checkout] });
  let verificationCount = 0;
  let acknowledgementCount = 0;
  const purchaseStartedAt = new Date(Date.now() - 60_000).toISOString();
  const purchaseExpiresAt = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString();
  const dependencies = {
    async verifyGoogle() {
      verificationCount += 1;
      return {
        packageName: APP_BUNDLE_ID,
        subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
        acknowledgementState: verificationCount === 1
          ? "ACKNOWLEDGEMENT_STATE_PENDING"
          : "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        startTime: purchaseStartedAt,
        lineItems: [{
          productId: "ca.indexcanada.app.premium.annual",
          expiryTime: purchaseExpiresAt,
          latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
          autoRenewingPlan: { autoRenewEnabled: true },
        }],
        externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
        etag: "etag-1",
      };
    },
    async acknowledgeGoogle() {
      acknowledgementCount += 1;
    },
  };
  const confirmation = {
    checkoutId: checkout._id,
    store: "google_play",
    productId: "ca.indexcanada.app.premium.annual",
    verificationData: "purchase-token-never-persisted",
    purchaseId: "GPA.1234-5678-9012-34567",
  };

  const first = await post_confirmStorePurchase(storePostRequest(confirmation), dependencies);
  const replay = await post_confirmStorePurchase(storePostRequest(confirmation), dependencies);

  assert.equal(first.status, 200);
  assert.equal(first.body.complete_purchase, true);
  assert.equal(first.body.status, "pending_review");
  assert.equal(first.body.data.isActive, false);
  assert.equal(first.body.entitlement.status, "active");
  assert.equal(replay.status, 200);
  assert.equal(replay.body.idempotent, true);
  assert.equal(acknowledgementCount, 1);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  const professional = __wixDataTest.items("Professionnel")[0];
  assert.equal(professional.registrationStatus, "pending_review");
  assert.equal(professional.isActive, false);
  assert.equal(professional.entitlementStatus, "active");
  for (const collection of ["PaymentCheckouts", "Entitlements", "Professionnel"]) {
    const serialized = JSON.stringify(__wixDataTest.items(collection));
    assert.equal(serialized.includes("purchase-token-never-persisted"), false);
    assert.equal(serialized.includes(accountToken), false);
  }
});

test("la confirmation répare la fiche après une panne survenue après l'Entitlement", async () => {
  const draft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400301" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  const rawToken = "initial-saga-retry-token-never-persisted";
  const providerResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(Date.now() - 60_000).toISOString(),
    lineItems: [{
      productId: checkout.storeProductId,
      expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.6666-6666-6666-66666",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    etag: "initial-saga-etag",
  };
  const confirmation = {
    checkoutId: checkout._id,
    store: "google_play",
    productId: checkout.storeProductId,
    verificationData: rawToken,
  };
  const providerDependencies = {
    verifyGoogle: async () => providerResponse,
    acknowledgeGoogle: async () => assert.fail("achat déjà acquitté"),
  };
  seed({ PaymentCheckouts: [checkout] });

  const failed = await post_confirmStorePurchase(storePostRequest(confirmation), {
    ...providerDependencies,
    finalizeProfessional: async () => {
      throw new Error("panne injectée après Entitlement");
    },
  });
  assert.equal(failed.status, 500);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  assert.equal(__wixDataTest.items("Professionnel").length, 0);

  const repaired = await post_confirmStorePurchase(
    storePostRequest(confirmation),
    providerDependencies,
  );
  assert.equal(repaired.status, 200);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  const entitlement = __wixDataTest.items("Entitlements")[0];
  const professional = __wixDataTest.items("Professionnel")[0];
  const finalizedCheckout = __wixDataTest.items("PaymentCheckouts")[0];
  assert.equal(professional._id, entitlement.professionalId);
  assert.equal(professional.entitlementId, entitlement._id);
  assert.equal(professional.checkoutId, checkout._id);
  assert.equal(finalizedCheckout.entitlementId, entitlement._id);
  assert.equal(finalizedCheckout.professionalId, professional._id);
  const persisted = JSON.stringify({ entitlement, professional, finalizedCheckout });
  assert.equal(persisted.includes(rawToken), false);
  assert.equal(persisted.includes(accountToken), false);
});

test("post_restoreStorePurchase retrouve le droit par le hash fournisseur sans checkout en entrée", async () => {
  const body = {
    ...storeRegistration(),
    planId: "premium",
    store: "google_play",
  };
  const draft = createStoreCheckoutDraft(body, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  const purchaseStartedAt = new Date(Date.now() - 60_000).toISOString();
  const purchaseExpiresAt = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString();
  const providerResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: purchaseStartedAt,
    lineItems: [{
      productId: "ca.indexcanada.app.premium.annual",
      expiryTime: purchaseExpiresAt,
      latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    etag: "restore-etag",
  };
  seed({ PaymentCheckouts: [checkout] });
  const confirmation = {
    checkoutId: checkout._id,
    store: "google_play",
    productId: "ca.indexcanada.app.premium.annual",
    verificationData: "restored-purchase-token",
    purchaseId: "GPA.1234-5678-9012-34567",
  };
  const dependencies = {
    verifyGoogle: async () => providerResponse,
    acknowledgeGoogle: async () => assert.fail("la preuve est déjà acquittée"),
  };
  const confirmed = await post_confirmStorePurchase(
    storePostRequest(confirmation),
    dependencies,
  );
  assert.equal(confirmed.status, 200);

  const restored = await post_restoreStorePurchase(storePostRequest({
    store: confirmation.store,
    productId: confirmation.productId,
    verificationData: confirmation.verificationData,
    purchaseId: confirmation.purchaseId,
  }), dependencies);

  assert.equal(restored.status, 200);
  assert.equal(restored.body.restored, true);
  assert.equal(restored.body.checkout_id, checkout._id);
  assert.equal(restored.body.data.professionalId, confirmed.body.data.professionalId);
  assert.equal(restored.body.data.isActive, false);
  assert.equal(restored.body.status, "pending_review");
  assert.equal(__wixDataTest.items("PaymentCheckouts").length, 1);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  const persisted = JSON.stringify({
    checkouts: __wixDataTest.items("PaymentCheckouts"),
    entitlements: __wixDataTest.items("Entitlements"),
    professionals: __wixDataTest.items("Professionnel"),
  });
  assert.equal(persisted.includes("restored-purchase-token"), false);
  assert.equal(persisted.includes(accountToken), false);
});

test("post_restoreStorePurchase récupère idempotemment un achat interrompu avant tout Entitlement", async () => {
  const draft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400099" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  seed({ PaymentCheckouts: [checkout] });
  const restoration = {
    store: "google_play",
    productId: "ca.indexcanada.app.premium.annual",
    verificationData: "interrupted-http-purchase-token",
    purchaseId: "client-hint-does-not-bind-google",
  };
  const dependencies = {
    verifyGoogle: async () => ({
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      startTime: new Date(Date.now() - 60_000).toISOString(),
      lineItems: [{
        productId: restoration.productId,
        expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
        autoRenewingPlan: { autoRenewEnabled: true },
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
      etag: "interrupted-http-etag",
    }),
    acknowledgeGoogle: async () => assert.fail("déjà acquitté"),
  };

  const first = await post_restoreStorePurchase(storePostRequest(restoration), dependencies);
  const replay = await post_restoreStorePurchase(storePostRequest(restoration), dependencies);

  assert.equal(first.status, 200);
  assert.equal(first.body.complete_purchase, true);
  assert.equal(first.body.restored, true);
  assert.equal(replay.status, 200);
  assert.equal(replay.body.idempotent, true);
  assert.equal(__wixDataTest.items("PaymentCheckouts").length, 1);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  const persisted = JSON.stringify({
    checkouts: __wixDataTest.items("PaymentCheckouts"),
    entitlements: __wixDataTest.items("Entitlements"),
    professionals: __wixDataTest.items("Professionnel"),
  });
  assert.equal(persisted.includes(restoration.verificationData), false);
  assert.equal(persisted.includes(accountToken), false);
});

test("post_restoreStorePurchase refuse une référence de compte CMS ambiguë", async () => {
  const draft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400100" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  seed({
    PaymentCheckouts: [
      checkout,
      { ...checkout, _id: `chk_${"f".repeat(32)}` },
    ],
  });
  const result = await post_restoreStorePurchase(storePostRequest({
    store: "google_play",
    productId: checkout.storeProductId,
    verificationData: "ambiguous-http-purchase-token",
  }), {
    verifyGoogle: async () => ({
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      startTime: new Date(Date.now() - 60_000).toISOString(),
      lineItems: [{
        productId: checkout.storeProductId,
        expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
        autoRenewingPlan: { autoRenewEnabled: true },
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    }),
    acknowledgeGoogle: async () => {},
  });

  assert.equal(result.status, 409);
  assert.equal(result.body.code, "STORE_ACCOUNT_REFERENCE_AMBIGUOUS");
  assert.equal(__wixDataTest.items("Entitlements").length, 0);
  assert.equal(__wixDataTest.items("Professionnel").length, 0);
});

test("post_googlePlayRtdn traite une révocation une seule fois sans modifier l'approbation", async () => {
  const body = {
    ...storeRegistration(),
    planId: "premium",
    store: "google_play",
  };
  const draft = createStoreCheckoutDraft(body, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  const subscription = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(Date.now() - 60_000).toISOString(),
    lineItems: [{
      productId: "ca.indexcanada.app.premium.annual",
      expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.1234-5678-9012-34567",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
    etag: "rtdn-etag",
  };
  seed({ PaymentCheckouts: [checkout] });
  const confirmation = {
    checkoutId: checkout._id,
    store: "google_play",
    productId: "ca.indexcanada.app.premium.annual",
    verificationData: "rtdn-purchase-token-never-persisted",
    purchaseId: "GPA.1234-5678-9012-34567",
  };
  const providerDependencies = {
    verifyGoogle: async () => subscription,
    acknowledgeGoogle: async () => assert.fail("déjà acquitté"),
  };
  assert.equal((await post_confirmStorePurchase(
    storePostRequest(confirmation),
    providerDependencies,
  )).status, 200);
  const approved = {
    ...__wixDataTest.items("Professionnel")[0],
    isActive: true,
    registrationStatus: "approved",
  };
  seed({
    PaymentCheckouts: __wixDataTest.items("PaymentCheckouts"),
    Entitlements: __wixDataTest.items("Entitlements"),
    Professionnel: [approved],
  });
  const rtdnData = Buffer.from(JSON.stringify({
    version: "1.0",
    packageName: APP_BUNDLE_ID,
    eventTimeMillis: String(Date.now() - 1_000),
    subscriptionNotification: {
      version: "1.0",
      notificationType: 12,
      purchaseToken: confirmation.verificationData,
      subscriptionId: confirmation.productId,
    },
  }), "utf8").toString("base64");
  const pushBody = {
    message: {
      data: rtdnData,
      messageId: "9876543210123456",
      publishTime: new Date().toISOString(),
    },
    subscription: "projects/index-canada/subscriptions/play-rtdn",
  };
  const pushRequest = storePostRequest(pushBody);
  pushRequest.headers.authorization = "Bearer header.payload.signature";
  const dependencies = {
    ...providerDependencies,
    expectedSubscription: pushBody.subscription,
    verifyGooglePush: async (authorization) => assert.equal(
      authorization,
      "Bearer header.payload.signature",
    ),
  };

  const first = await post_googlePlayRtdn(pushRequest, dependencies);
  const replay = await post_googlePlayRtdn(pushRequest, dependencies);

  const obsoletePayload = JSON.parse(Buffer.from(rtdnData, "base64").toString("utf8"));
  obsoletePayload.eventTimeMillis = String(Date.now() - 5_000);
  obsoletePayload.subscriptionNotification.notificationType = 2;
  const obsoleteRequest = storePostRequest({
    ...pushBody,
    message: {
      ...pushBody.message,
      messageId: "obsolete-renewal-9876543210",
      data: Buffer.from(JSON.stringify(obsoletePayload), "utf8").toString("base64"),
    },
  });
  obsoleteRequest.headers.authorization = "Bearer header.payload.signature";
  const obsoleteReplay = await post_googlePlayRtdn(obsoleteRequest, dependencies);

  assert.equal(first.status, 200);
  assert.equal(first.body.received, true);
  assert.equal(replay.status, 200);
  assert.equal(replay.body.idempotent, true);
  assert.equal(obsoleteReplay.status, 200);
  assert.equal(__wixDataTest.items("PaymentEvents").length, 2);
  assert.equal(
    __wixDataTest.items("PaymentEvents").every((event) => event.status === "processed"),
    true,
  );
  assert.equal(__wixDataTest.items("Entitlements")[0].status, "revoked");
  const professional = __wixDataTest.items("Professionnel")[0];
  assert.equal(professional.isActive, true);
  assert.equal(professional.registrationStatus, "approved");
  assert.equal(professional.entitlementStatus, "revoked");
  assert.equal(professional.paymentStatus, "revoked");
  const persisted = JSON.stringify({
    events: __wixDataTest.items("PaymentEvents"),
    entitlements: __wixDataTest.items("Entitlements"),
    professionals: __wixDataTest.items("Professionnel"),
  });
  assert.equal(persisted.includes(confirmation.verificationData), false);
  assert.equal(persisted.includes(accountToken), false);
});

test("un RTDN-first répare la fiche manquante après une panne post-Entitlement", async () => {
  const draft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400302" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  const rawToken = "rtdn-first-saga-token-never-persisted";
  const subscriptionName = "projects/index-canada/subscriptions/play-rtdn";
  const eventAt = Date.now();
  const data = Buffer.from(JSON.stringify({
    version: "1.0",
    packageName: APP_BUNDLE_ID,
    eventTimeMillis: String(eventAt),
    subscriptionNotification: {
      version: "1.0",
      notificationType: 4,
      purchaseToken: rawToken,
      subscriptionId: checkout.storeProductId,
    },
  }), "utf8").toString("base64");
  const push = storePostRequest({
    message: {
      data,
      messageId: "rtdn-first-saga-message-123456",
      publishTime: new Date(eventAt).toISOString(),
    },
    subscription: subscriptionName,
  });
  push.headers.authorization = "Bearer header.payload.signature";
  const providerDependencies = {
    expectedSubscription: subscriptionName,
    verifyGooglePush: async () => {},
    verifyGoogle: async () => ({
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      startTime: new Date(eventAt - 60_000).toISOString(),
      lineItems: [{
        productId: checkout.storeProductId,
        expiryTime: new Date(eventAt + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.7777-7777-7777-77777",
        autoRenewingPlan: { autoRenewEnabled: true },
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: accountToken },
      etag: "rtdn-first-saga-etag",
    }),
    acknowledgeGoogle: async () => assert.fail("achat déjà acquitté"),
  };
  seed({ PaymentCheckouts: [checkout] });

  const failed = await post_googlePlayRtdn(push, {
    ...providerDependencies,
    projectProfessional: async () => {
      throw new Error("panne RTDN injectée après Entitlement");
    },
  });
  assert.equal(failed.status, 500);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  assert.equal(__wixDataTest.items("Professionnel").length, 0);
  assert.equal(__wixDataTest.items("PaymentEvents")[0].status, "processing");

  const repaired = await post_googlePlayRtdn(push, providerDependencies);
  assert.equal(repaired.status, 200);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  assert.equal(__wixDataTest.items("PaymentEvents")[0].status, "processed");
  const entitlement = __wixDataTest.items("Entitlements")[0];
  const professional = __wixDataTest.items("Professionnel")[0];
  assert.equal(professional._id, entitlement.professionalId);
  assert.equal(professional.entitlementId, entitlement._id);
  assert.equal(professional.checkoutId, checkout._id);
  const persisted = JSON.stringify({
    events: __wixDataTest.items("PaymentEvents"),
    entitlement,
    professional,
  });
  assert.equal(persisted.includes(rawToken), false);
  assert.equal(persisted.includes(accountToken), false);
});

test("un remplacement RTDN répare la fiche initiale manquante depuis le checkout racine", async () => {
  const premiumProduct = "ca.indexcanada.app.premium.annual";
  const professionalProduct = "ca.indexcanada.app.professional.annual";
  const initialToken = "root-saga-initial-token-never-persisted";
  const replacementToken = "root-saga-replacement-token-never-persisted";
  const initialDraft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400401" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const initialCheckout = buildPersistedCheckoutDraft(
    initialDraft,
    { profile: "", gallery: [] },
  );
  const initialAccountToken = deriveStoreAccountToken(initialCheckout, TEST_SIGNING_SECRET);
  const initialResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(Date.now() - 60_000).toISOString(),
    lineItems: [{
      productId: premiumProduct,
      expiryTime: new Date(Date.now() + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.4141-4141-4141-41414",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: initialAccountToken },
  };
  seed({ PaymentCheckouts: [initialCheckout] });
  const failedInitial = await post_confirmStorePurchase(storePostRequest({
    checkoutId: initialCheckout._id,
    store: "google_play",
    productId: premiumProduct,
    verificationData: initialToken,
  }), {
    verifyGoogle: async () => initialResponse,
    acknowledgeGoogle: async () => assert.fail("achat initial déjà acquitté"),
    finalizeProfessional: async () => {
      throw new Error("panne initiale injectée avant la fiche");
    },
  });
  assert.equal(failedInitial.status, 500);
  assert.equal(__wixDataTest.items("Entitlements").length, 1);
  assert.equal(__wixDataTest.items("Professionnel").length, 0);
  assert.equal(
    __wixDataTest.items("Entitlements")[0].rootCheckoutId,
    initialCheckout._id,
  );

  const replacementDraft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400402" }),
    planId: "professional",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const replacementCheckout = buildPersistedCheckoutDraft(
    replacementDraft,
    { profile: "", gallery: [] },
  );
  const replacementAccountToken = deriveStoreAccountToken(
    replacementCheckout,
    TEST_SIGNING_SECRET,
  );
  seed({
    PaymentCheckouts: [
      ...__wixDataTest.items("PaymentCheckouts"),
      replacementCheckout,
    ],
    Entitlements: __wixDataTest.items("Entitlements"),
  });

  const eventAt = Date.now() + 1_000;
  const data = Buffer.from(JSON.stringify({
    version: "1.0",
    packageName: APP_BUNDLE_ID,
    eventTimeMillis: String(eventAt),
    subscriptionNotification: {
      version: "1.0",
      notificationType: 4,
      purchaseToken: replacementToken,
      subscriptionId: professionalProduct,
    },
  }), "utf8").toString("base64");
  const push = storePostRequest({
    message: {
      data,
      messageId: "root-saga-replacement-message-123456",
      publishTime: new Date(eventAt).toISOString(),
    },
    subscription: "projects/index-canada/subscriptions/play-rtdn",
  });
  push.headers.authorization = "Bearer header.payload.signature";
  const acknowledgements = [];
  const repaired = await post_googlePlayRtdn(push, {
    expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
    verifyGooglePush: async () => {},
    verifyGoogle: async () => ({
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
      linkedPurchaseToken: initialToken,
      startTime: initialResponse.startTime,
      lineItems: [{
        productId: professionalProduct,
        expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.4242-4242-4242-42424",
        autoRenewingPlan: { autoRenewEnabled: true },
        itemReplacement: {
          productId: premiumProduct,
          replacementMode: "WITH_TIME_PRORATION",
        },
      }],
      externalAccountIdentifiers: {
        obfuscatedExternalAccountId: replacementAccountToken,
      },
      etag: "root-saga-replacement-etag",
    }),
    acknowledgeGoogle: async (value) => acknowledgements.push(value),
  });

  assert.equal(repaired.status, 200);
  assert.deepEqual(acknowledgements, [{
    purchaseToken: replacementToken,
    productId: professionalProduct,
  }]);
  const [entitlement] = __wixDataTest.items("Entitlements");
  const [professional] = __wixDataTest.items("Professionnel");
  assert.equal(entitlement.rootCheckoutId, initialCheckout._id);
  assert.equal(entitlement.checkoutId, replacementCheckout._id);
  assert.equal(professional._id, entitlement.professionalId);
  assert.equal(professional.checkoutId, replacementCheckout._id);
  assert.equal(professional.entitlementId, entitlement._id);
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  const checkouts = __wixDataTest.items("PaymentCheckouts");
  assert.equal(checkouts.find((item) => item._id === initialCheckout._id)?.entitlementId, entitlement._id);
  assert.equal(checkouts.find((item) => item._id === initialCheckout._id)?.professionalId, professional._id);
  assert.equal(checkouts.find((item) => item._id === replacementCheckout._id)?.entitlementId, entitlement._id);
  assert.equal(checkouts.find((item) => item._id === replacementCheckout._id)?.professionalId, professional._id);
  const persisted = JSON.stringify({ entitlement, professional, checkouts });
  assert.equal(persisted.includes(initialToken), false);
  assert.equal(persisted.includes(replacementToken), false);
});

test("Google RTDN migre un remplacement différé sans doubler la fiche et ignore l'ancien token expiré", async () => {
  const professionalDraft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400101" }),
    planId: "professional",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const professionalCheckout = buildPersistedCheckoutDraft(
    professionalDraft,
    { profile: "", gallery: [] },
  );
  const professionalAccountToken = deriveStoreAccountToken(
    professionalCheckout,
    TEST_SIGNING_SECRET,
  );
  const initialToken = "initial-purchase-token-never-persisted";
  const replacementToken = "replacement-purchase-token-never-persisted";
  const premiumProduct = "ca.indexcanada.app.premium.annual";
  const professionalProduct = "ca.indexcanada.app.professional.annual";
  const initialSubscription = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(Date.now() - 60_000).toISOString(),
    lineItems: [{
      productId: professionalProduct,
      expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: professionalAccountToken },
    etag: "initial-plan-etag",
  };
  seed({ PaymentCheckouts: [professionalCheckout] });
  assert.equal((await post_confirmStorePurchase(storePostRequest({
    checkoutId: professionalCheckout._id,
    store: "google_play",
    productId: professionalProduct,
    verificationData: initialToken,
  }), {
    verifyGoogle: async () => initialSubscription,
    acknowledgeGoogle: async () => assert.fail("déjà acquitté"),
  })).status, 200);
  const originalEntitlement = __wixDataTest.items("Entitlements")[0];
  const originalProfessional = __wixDataTest.items("Professionnel")[0];
  const approved = {
    ...originalProfessional,
    isActive: true,
    registrationStatus: "approved",
  };

  const replacementDraft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400101" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const replacementCheckout = buildPersistedCheckoutDraft(
    replacementDraft,
    { profile: "", gallery: [] },
  );
  const replacementAccountToken = deriveStoreAccountToken(
    replacementCheckout,
    TEST_SIGNING_SECRET,
  );
  seed({
    PaymentCheckouts: [
      ...__wixDataTest.items("PaymentCheckouts"),
      replacementCheckout,
    ],
    Entitlements: __wixDataTest.items("Entitlements"),
    Professionnel: [approved],
  });

  const deferredExpiry = new Date(Date.now() + 60_000).toISOString();
  const deferredSubscription = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    linkedPurchaseToken: initialToken,
    lineItems: [{
      productId: professionalProduct,
      expiryTime: deferredExpiry,
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: false },
      deferredItemReplacement: { productId: premiumProduct },
    }, {
      productId: premiumProduct,
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: replacementAccountToken },
    etag: "deferred-plan-etag",
  };
  const deliverRtdn = async ({
    token,
    subscriptionId,
    notificationType,
    messageId,
    eventTime,
    response,
    acknowledgeGoogle = async () => assert.fail("déjà acquitté"),
    extraDependencies = {},
  }) => {
    const data = Buffer.from(JSON.stringify({
      version: "1.0",
      packageName: APP_BUNDLE_ID,
      eventTimeMillis: String(eventTime),
      subscriptionNotification: {
        version: "1.0",
        notificationType,
        purchaseToken: token,
        subscriptionId,
      },
    }), "utf8").toString("base64");
    const push = storePostRequest({
      message: {
        data,
        messageId,
        publishTime: new Date(eventTime).toISOString(),
      },
      subscription: "projects/index-canada/subscriptions/play-rtdn",
    });
    push.headers.authorization = "Bearer header.payload.signature";
    return post_googlePlayRtdn(push, {
      expectedSubscription: "projects/index-canada/subscriptions/play-rtdn",
      verifyGooglePush: async () => {},
      verifyGoogle: async () => response,
      acknowledgeGoogle,
      ...extraDependencies,
    });
  };

  const firstEventAt = Date.now() + 1_000;
  const acknowledgements = [];
  const failedDeferred = await deliverRtdn({
    token: replacementToken,
    subscriptionId: professionalProduct,
    notificationType: 4,
    messageId: "deferred-replacement-message-123456",
    eventTime: firstEventAt,
    response: deferredSubscription,
    acknowledgeGoogle: async (value) => acknowledgements.push(value),
    extraDependencies: {
      projectReplacementProfessional: async () => {
        throw new Error("panne X vers Y injectée après Entitlement");
      },
    },
  });
  assert.equal(failedDeferred.status, 500);
  assert.equal(__wixDataTest.items("Entitlements")[0].checkoutId, replacementCheckout._id);
  assert.equal(__wixDataTest.items("Professionnel")[0].checkoutId, professionalCheckout._id);
  assert.deepEqual(acknowledgements, []);
  const deferred = await deliverRtdn({
    token: replacementToken,
    subscriptionId: professionalProduct,
    notificationType: 4,
    messageId: "deferred-replacement-message-123456",
    eventTime: firstEventAt,
    response: deferredSubscription,
    acknowledgeGoogle: async (value) => acknowledgements.push(value),
  });
  assert.equal(deferred.status, 200);
  assert.deepEqual(acknowledgements, [{
    purchaseToken: replacementToken,
    productId: professionalProduct,
  }]);
  let entitlement = __wixDataTest.items("Entitlements")[0];
  assert.equal(entitlement._id, originalEntitlement._id);
  assert.equal(entitlement.professionalId, originalProfessional._id);
  assert.equal(entitlement.checkoutId, replacementCheckout._id);
  assert.equal(entitlement.planId, "professional");
  assert.equal(entitlement.productId, professionalProduct);
  assert.equal(entitlement.pendingPlanId, "premium");
  assert.equal(entitlement.pendingProductId, premiumProduct);
  assert.equal(entitlement.pendingEffectiveAt, deferredExpiry);
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  assert.equal(__wixDataTest.items("Professionnel")[0].checkoutId, replacementCheckout._id);
  assert.equal(__wixDataTest.items("Professionnel")[0].plan, "professional");
  assert.equal(__wixDataTest.items("Professionnel")[0].sponsor, true);
  assert.equal(__wixDataTest.items("Professionnel")[0].isActive, true);
  assert.equal(__wixDataTest.items("Professionnel")[0].registrationStatus, "approved");

  const confirmation = await post_confirmStorePurchase(storePostRequest({
    checkoutId: replacementCheckout._id,
    store: "google_play",
    productId: premiumProduct,
    verificationData: replacementToken,
  }), {
    verifyGoogle: async () => ({
      ...deferredSubscription,
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    }),
    acknowledgeGoogle: async () => assert.fail("le RTDN a déjà acquitté le nouveau token"),
  });
  assert.equal(confirmation.status, 200);
  assert.equal(confirmation.body.data.planId, "professional");
  assert.equal(confirmation.body.data.pendingPlanId, "premium");
  assert.equal(confirmation.body.entitlement.plan_id, "professional");
  assert.equal(confirmation.body.entitlement.pending_plan_id, "premium");

  const renewedSubscription = {
    ...deferredSubscription,
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: initialSubscription.startTime,
    lineItems: [{
      productId: professionalProduct,
      expiryTime: new Date(Date.now() - 1_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1111-1111-1111-11111",
      autoRenewingPlan: { autoRenewEnabled: false },
    }, {
      productId: premiumProduct,
      expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.2222-2222-2222-22222",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    etag: "effective-renewal-etag",
  };
  const renewed = await deliverRtdn({
    token: replacementToken,
    subscriptionId: premiumProduct,
    notificationType: 2,
    messageId: "effective-renewal-message-123456",
    eventTime: firstEventAt + 1_000,
    response: renewedSubscription,
  });
  assert.equal(renewed.status, 200);
  entitlement = __wixDataTest.items("Entitlements")[0];
  assert.equal(entitlement.planId, "premium");
  assert.equal(entitlement.productId, premiumProduct);
  assert.equal(entitlement.pendingPlanId, "");
  assert.equal(entitlement.pendingProductId, "");
  assert.equal(entitlement.pendingEffectiveAt, "");
  assert.equal(__wixDataTest.items("Professionnel")[0].plan, "premium");
  assert.equal(__wixDataTest.items("Professionnel")[0].sponsor, false);
  assert.equal(__wixDataTest.items("Professionnel")[0].isActive, true);
  assert.equal(__wixDataTest.items("Professionnel")[0].registrationStatus, "approved");

  const expiredOldToken = await deliverRtdn({
    token: initialToken,
    subscriptionId: professionalProduct,
    notificationType: 13,
    messageId: "expired-old-token-message-123456",
    eventTime: firstEventAt + 2_000,
    response: {
      ...initialSubscription,
      subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
      lineItems: [{
        ...initialSubscription.lineItems[0],
        expiryTime: new Date(Date.now() - 1_000).toISOString(),
        autoRenewingPlan: { autoRenewEnabled: false },
      }],
    },
  });
  assert.equal(expiredOldToken.status, 200);
  assert.equal(expiredOldToken.body.ignored, true);
  assert.equal(__wixDataTest.items("Entitlements")[0].status, "active");
  assert.equal(__wixDataTest.items("Entitlements")[0].planId, "premium");
  assert.equal(__wixDataTest.items("Professionnel")[0].entitlementStatus, "active");
  assert.equal(
    __wixDataTest.items("PaymentEvents")
      .find((event) => event.eventType === "SUBSCRIPTION_EXPIRED")?.outcome,
    "superseded_purchase_token",
  );

  const secondReplacementToken = "second-replacement-token-never-persisted";
  const upgradeDraft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400102" }),
    planId: "professional",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const upgradeCheckout = buildPersistedCheckoutDraft(
    upgradeDraft,
    { profile: "", gallery: [] },
  );
  const upgradeAccountToken = deriveStoreAccountToken(
    upgradeCheckout,
    TEST_SIGNING_SECRET,
  );
  seed({
    PaymentCheckouts: [
      ...__wixDataTest.items("PaymentCheckouts"),
      upgradeCheckout,
    ],
    PaymentEvents: __wixDataTest.items("PaymentEvents"),
    Entitlements: __wixDataTest.items("Entitlements"),
    Professionnel: __wixDataTest.items("Professionnel"),
  });
  const secondAcknowledgements = [];
  const failedSecondReplacement = await deliverRtdn({
    token: secondReplacementToken,
    subscriptionId: professionalProduct,
    notificationType: 4,
    messageId: "second-replacement-message-123456",
    eventTime: firstEventAt + 3_000,
    response: {
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
      linkedPurchaseToken: replacementToken,
      startTime: initialSubscription.startTime,
      lineItems: [{
        productId: professionalProduct,
        expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.3333-3333-3333-33333",
        autoRenewingPlan: { autoRenewEnabled: true },
        itemReplacement: {
          productId: premiumProduct,
          replacementMode: "WITH_TIME_PRORATION",
        },
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: upgradeAccountToken },
      etag: "second-replacement-etag",
    },
    acknowledgeGoogle: async (value) => secondAcknowledgements.push(value),
    extraDependencies: {
      projectReplacementProfessional: async () => {
        throw new Error("panne Y vers Z injectée après Entitlement");
      },
    },
  });
  assert.equal(failedSecondReplacement.status, 500);
  assert.equal(__wixDataTest.items("Entitlements")[0].checkoutId, upgradeCheckout._id);
  assert.equal(__wixDataTest.items("Professionnel")[0].checkoutId, replacementCheckout._id);
  assert.deepEqual(secondAcknowledgements, []);
  const secondReplacement = await deliverRtdn({
    token: secondReplacementToken,
    subscriptionId: professionalProduct,
    notificationType: 4,
    messageId: "second-replacement-message-123456",
    eventTime: firstEventAt + 3_000,
    response: {
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
      linkedPurchaseToken: replacementToken,
      startTime: initialSubscription.startTime,
      lineItems: [{
        productId: professionalProduct,
        expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.3333-3333-3333-33333",
        autoRenewingPlan: { autoRenewEnabled: true },
        itemReplacement: {
          productId: premiumProduct,
          replacementMode: "WITH_TIME_PRORATION",
        },
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: upgradeAccountToken },
      etag: "second-replacement-etag",
    },
    acknowledgeGoogle: async (value) => secondAcknowledgements.push(value),
  });
  assert.equal(secondReplacement.status, 200);
  assert.deepEqual(secondAcknowledgements, [{
    purchaseToken: secondReplacementToken,
    productId: professionalProduct,
  }]);
  entitlement = __wixDataTest.items("Entitlements")[0];
  assert.equal(entitlement._id, originalEntitlement._id);
  assert.equal(entitlement.professionalId, originalProfessional._id);
  assert.equal(entitlement.checkoutId, upgradeCheckout._id);
  assert.equal(entitlement.planId, "professional");
  assert.equal(entitlement.pendingPlanId, "");
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  assert.equal(__wixDataTest.items("Professionnel")[0].checkoutId, upgradeCheckout._id);

  const expiredMiddleToken = await deliverRtdn({
    token: replacementToken,
    subscriptionId: premiumProduct,
    notificationType: 13,
    messageId: "expired-middle-token-message-123456",
    eventTime: firstEventAt + 4_000,
    response: {
      ...renewedSubscription,
      subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
      lineItems: [{
        ...renewedSubscription.lineItems[0],
        expiryTime: new Date(Date.now() - 2_000).toISOString(),
        autoRenewingPlan: { autoRenewEnabled: false },
      }, {
        ...renewedSubscription.lineItems[1],
        expiryTime: new Date(Date.now() - 1_000).toISOString(),
        autoRenewingPlan: { autoRenewEnabled: false },
      }],
    },
  });
  assert.equal(expiredMiddleToken.status, 200);
  assert.equal(expiredMiddleToken.body.ignored, true);
  assert.equal(__wixDataTest.items("Entitlements")[0].status, "active");
  assert.equal(__wixDataTest.items("Entitlements")[0].planId, "professional");
  assert.equal(
    __wixDataTest.items("PaymentEvents")
      .filter((event) => event.eventType === "SUBSCRIPTION_EXPIRED")
      .every((event) => event.outcome === "superseded_purchase_token"),
    true,
  );
  const persisted = JSON.stringify({
    events: __wixDataTest.items("PaymentEvents"),
    checkouts: __wixDataTest.items("PaymentCheckouts"),
    entitlements: __wixDataTest.items("Entitlements"),
    professionals: __wixDataTest.items("Professionnel"),
  });
  assert.equal(persisted.includes(initialToken), false);
  assert.equal(persisted.includes(replacementToken), false);
  assert.equal(persisted.includes(secondReplacementToken), false);
});

test("la chaîne X vers Y vers Z répare le checkout Y resté incomplet après migration du profil", async () => {
  const premiumProduct = "ca.indexcanada.app.premium.annual";
  const professionalProduct = "ca.indexcanada.app.professional.annual";
  const xToken = "interrupted-x-token-never-persisted";
  const yToken = "interrupted-y-token-never-persisted";
  const zToken = "interrupted-z-token-never-persisted";
  const xCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400501" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now()), { profile: "", gallery: [] });
  const xAccountToken = deriveStoreAccountToken(xCheckout, TEST_SIGNING_SECRET);
  const initialResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(Date.now() - 60_000).toISOString(),
    lineItems: [{
      productId: premiumProduct,
      expiryTime: new Date(Date.now() + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.5151-5151-5151-51515",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: xAccountToken },
  };
  seed({ PaymentCheckouts: [xCheckout] });
  assert.equal((await post_confirmStorePurchase(storePostRequest({
    checkoutId: xCheckout._id,
    store: "google_play",
    productId: premiumProduct,
    verificationData: xToken,
  }), {
    verifyGoogle: async () => initialResponse,
    acknowledgeGoogle: async () => assert.fail("achat X déjà acquitté"),
  })).status, 200);

  const yCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400502" }),
    planId: "professional",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now()), { profile: "", gallery: [] });
  const yAccountToken = deriveStoreAccountToken(yCheckout, TEST_SIGNING_SECRET);
  seed({
    PaymentCheckouts: [...__wixDataTest.items("PaymentCheckouts"), yCheckout],
    Entitlements: __wixDataTest.items("Entitlements"),
    Professionnel: __wixDataTest.items("Professionnel"),
  });
  assert.equal((await post_confirmStorePurchase(storePostRequest({
    checkoutId: yCheckout._id,
    store: "google_play",
    productId: professionalProduct,
    verificationData: yToken,
  }), {
    verifyGoogle: async () => ({
      ...initialResponse,
      linkedPurchaseToken: xToken,
      lineItems: [{
        productId: professionalProduct,
        expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
        latestSuccessfulOrderId: "GPA.5252-5252-5252-52525",
        autoRenewingPlan: { autoRenewEnabled: true },
        itemReplacement: {
          productId: premiumProduct,
          replacementMode: "WITH_TIME_PRORATION",
        },
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: yAccountToken },
      etag: "interrupted-y-etag",
    }),
    acknowledgeGoogle: async () => assert.fail("achat Y déjà acquitté"),
  })).status, 200);
  const yEntitlement = __wixDataTest.items("Entitlements")[0];
  const migratedProfessional = __wixDataTest.items("Professionnel")[0];
  assert.equal(migratedProfessional.checkoutId, yCheckout._id);

  // État exact d'une panne après la migration de la fiche, mais avant le
  // patch final du checkout Y : le droit et la fiche pointent Y, ses liens
  // locaux ne sont pas encore écrits.
  const interruptedCheckouts = __wixDataTest.items("PaymentCheckouts").map((item) => (
    item._id === yCheckout._id
      ? {
        ...item,
        status: "store_purchase_pending",
        professionalId: "",
        entitlementId: "",
        finalizedAt: "",
      }
      : item
  ));
  const zCheckout = buildPersistedCheckoutDraft(createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400503" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now()), { profile: "", gallery: [] });
  const zAccountToken = deriveStoreAccountToken(zCheckout, TEST_SIGNING_SECRET);
  seed({
    PaymentCheckouts: [...interruptedCheckouts, zCheckout],
    Entitlements: [yEntitlement],
    Professionnel: [migratedProfessional],
  });
  const deferredExpiry = new Date(Date.now() + 60_000).toISOString();
  const zResult = await post_confirmStorePurchase(storePostRequest({
    checkoutId: zCheckout._id,
    store: "google_play",
    productId: premiumProduct,
    verificationData: zToken,
  }), {
    verifyGoogle: async () => ({
      packageName: APP_BUNDLE_ID,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      linkedPurchaseToken: yToken,
      lineItems: [{
        productId: professionalProduct,
        expiryTime: deferredExpiry,
        latestSuccessfulOrderId: "GPA.5252-5252-5252-52525",
        autoRenewingPlan: { autoRenewEnabled: false },
        deferredItemReplacement: { productId: premiumProduct },
      }, {
        productId: premiumProduct,
      }],
      externalAccountIdentifiers: { obfuscatedExternalAccountId: zAccountToken },
      etag: "interrupted-z-etag",
    }),
    acknowledgeGoogle: async () => assert.fail("achat Z déjà acquitté"),
  });

  assert.equal(zResult.status, 200);
  const [entitlement] = __wixDataTest.items("Entitlements");
  const [professional] = __wixDataTest.items("Professionnel");
  const checkouts = __wixDataTest.items("PaymentCheckouts");
  const repairedY = checkouts.find((item) => item._id === yCheckout._id);
  const finalizedZ = checkouts.find((item) => item._id === zCheckout._id);
  assert.equal(entitlement.rootCheckoutId, xCheckout._id);
  assert.equal(entitlement.checkoutId, zCheckout._id);
  assert.equal(professional.checkoutId, zCheckout._id);
  assert.equal(repairedY.entitlementId, entitlement._id);
  assert.equal(repairedY.professionalId, professional._id);
  assert.equal(finalizedZ.entitlementId, entitlement._id);
  assert.equal(finalizedZ.professionalId, professional._id);
  assert.equal(__wixDataTest.items("Professionnel").length, 1);
  const persisted = JSON.stringify({ entitlement, professional, checkouts });
  assert.equal(persisted.includes(xToken), false);
  assert.equal(persisted.includes(yToken), false);
  assert.equal(persisted.includes(zToken), false);
});

test("un remplacement refuse toute fiche ou checkout prédécesseur non lié au même droit", async () => {
  const premiumProduct = "ca.indexcanada.app.premium.annual";
  const professionalProduct = "ca.indexcanada.app.professional.annual";
  const initialToken = "takeover-initial-token-never-persisted";
  const replacementToken = "takeover-replacement-token-never-persisted";
  const initialDraft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400303" }),
    planId: "premium",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const initialCheckout = buildPersistedCheckoutDraft(
    initialDraft,
    { profile: "", gallery: [] },
  );
  const initialAccountToken = deriveStoreAccountToken(initialCheckout, TEST_SIGNING_SECRET);
  const initialResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    startTime: new Date(Date.now() - 60_000).toISOString(),
    lineItems: [{
      productId: premiumProduct,
      expiryTime: new Date(Date.now() + 60_000).toISOString(),
      latestSuccessfulOrderId: "GPA.1010-1010-1010-10101",
      autoRenewingPlan: { autoRenewEnabled: true },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: initialAccountToken },
  };
  seed({ PaymentCheckouts: [initialCheckout] });
  assert.equal((await post_confirmStorePurchase(storePostRequest({
    checkoutId: initialCheckout._id,
    store: "google_play",
    productId: premiumProduct,
    verificationData: initialToken,
  }), {
    verifyGoogle: async () => initialResponse,
    acknowledgeGoogle: async () => assert.fail("achat déjà acquitté"),
  })).status, 200);

  const originalCheckout = __wixDataTest.items("PaymentCheckouts")[0];
  const originalEntitlement = __wixDataTest.items("Entitlements")[0];
  const originalProfessional = __wixDataTest.items("Professionnel")[0];
  const replacementDraft = createStoreCheckoutDraft({
    ...storeRegistration({ professionalId: "temp_1758812400304" }),
    planId: "professional",
    store: "google_play",
  }, TEST_SIGNING_SECRET, Date.now());
  const replacementCheckout = buildPersistedCheckoutDraft(
    replacementDraft,
    { profile: "", gallery: [] },
  );
  const replacementAccountToken = deriveStoreAccountToken(
    replacementCheckout,
    TEST_SIGNING_SECRET,
  );
  const replacementResponse = {
    packageName: APP_BUNDLE_ID,
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    linkedPurchaseToken: initialToken,
    startTime: initialResponse.startTime,
    lineItems: [{
      productId: professionalProduct,
      expiryTime: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
      latestSuccessfulOrderId: "GPA.2020-2020-2020-20202",
      autoRenewingPlan: { autoRenewEnabled: true },
      itemReplacement: {
        productId: premiumProduct,
        replacementMode: "WITH_TIME_PRORATION",
      },
    }],
    externalAccountIdentifiers: { obfuscatedExternalAccountId: replacementAccountToken },
  };
  const replacementConfirmation = {
    checkoutId: replacementCheckout._id,
    store: "google_play",
    productId: professionalProduct,
    verificationData: replacementToken,
  };
  const replacementDependencies = {
    verifyGoogle: async () => replacementResponse,
    acknowledgeGoogle: async () => assert.fail("aucun acquittement après rejet"),
  };

  seed({
    PaymentCheckouts: [originalCheckout, replacementCheckout],
    Entitlements: [originalEntitlement],
    Professionnel: [{
      ...originalProfessional,
      entitlementId: `ent_${"f".repeat(32)}`,
    }],
  });
  const foreignProfessional = await post_confirmStorePurchase(
    storePostRequest(replacementConfirmation),
    replacementDependencies,
  );
  assert.equal(foreignProfessional.status, 409);
  assert.equal(foreignProfessional.body.code, "PAYMENT_ALREADY_USED");
  assert.equal(__wixDataTest.items("Professionnel")[0].checkoutId, originalCheckout._id);
  assert.equal(__wixDataTest.items("PaymentCheckouts")[1].professionalId, "");

  seed({
    PaymentCheckouts: [{
      ...originalCheckout,
      entitlementId: `ent_${"e".repeat(32)}`,
    }, replacementCheckout],
    Entitlements: [originalEntitlement],
    Professionnel: [originalProfessional],
  });
  const foreignPredecessor = await post_confirmStorePurchase(
    storePostRequest(replacementConfirmation),
    replacementDependencies,
  );
  assert.equal(foreignPredecessor.status, 409);
  assert.equal(foreignPredecessor.body.code, "PAYMENT_ALREADY_USED");
  assert.equal(__wixDataTest.items("Professionnel")[0].checkoutId, originalCheckout._id);
  assert.equal(__wixDataTest.items("PaymentCheckouts")[1].professionalId, "");
});

test("post_appStoreServerNotificationV2 traite une expiration JWS validée", async () => {
  const body = {
    ...storeRegistration({ professionalId: "temp_1758812400001" }),
    planId: "premium",
    store: "app_store",
  };
  const draft = createStoreCheckoutDraft(body, TEST_SIGNING_SECRET, Date.now());
  const checkout = buildPersistedCheckoutDraft(draft, { profile: "", gallery: [] });
  const accountToken = deriveStoreAccountToken(checkout, TEST_SIGNING_SECRET);
  const activeTransaction = {
    bundleId: APP_BUNDLE_ID,
    productId: "ca.indexcanada.app.premium.annual",
    appAccountToken: accountToken,
    environment: "Production",
    transactionId: "2000000912345678",
    originalTransactionId: "2000000812345678",
    purchaseDate: Date.now() - 60_000,
    expiresDate: Date.now() + 60_000,
    signedDate: Date.now() - 500,
    type: "Auto-Renewable Subscription",
  };
  seed({ PaymentCheckouts: [checkout] });
  assert.equal((await post_confirmStorePurchase(storePostRequest({
    checkoutId: checkout._id,
    store: "app_store",
    productId: activeTransaction.productId,
    verificationData: "active.transaction.jws",
    purchaseId: activeTransaction.transactionId,
  }), {
    verifyApple: async () => activeTransaction,
  })).status, 200);
  const expiredTransaction = {
    ...activeTransaction,
    expiresDate: Date.now() - 1,
    signedDate: Date.now(),
  };
  const notification = {
    notificationType: "EXPIRED",
    subtype: "VOLUNTARY",
    notificationUUID: "123e4567-e89b-42d3-a456-426614174099",
    version: "2.0",
    signedDate: Date.now(),
    data: {
      bundleId: APP_BUNDLE_ID,
      environment: "Production",
      status: 2,
      signedTransactionInfo: "expired.transaction.jws",
    },
  };
  const result = await post_appStoreServerNotificationV2(storePostRequest({
    signedPayload: "expired.notification.jws",
  }), {
    verifyAppleNotification: async () => notification,
    verifyAppleTransaction: async () => expiredTransaction,
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.received, true);
  assert.equal(__wixDataTest.items("Entitlements")[0].status, "expired");
  assert.equal(__wixDataTest.items("Professionnel")[0].entitlementStatus, "expired");
  assert.equal(__wixDataTest.items("Professionnel")[0].isActive, false);
  assert.equal(JSON.stringify(__wixDataTest.items("PaymentEvents"))
    .includes("expired.notification.jws"), false);
});

test("les routes magasin refusent toute méthode autre que POST", () => {
  assert.equal(use_createStoreCheckout(request()).status, 405);
  assert.equal(use_confirmStorePurchase(request()).status, 405);
  assert.equal(use_restoreStorePurchase(request()).status, 405);
  assert.equal(use_appStoreServerNotificationV2(request()).status, 405);
  assert.equal(use_googlePlayRtdn(request()).status, 405);
  assert.equal(use_createStoreCheckout(request({}, { method: "OPTIONS" })).status, 204);
  assert.equal(use_confirmStorePurchase(request({}, { method: "OPTIONS" })).status, 204);
  assert.equal(use_restoreStorePurchase(request({}, { method: "OPTIONS" })).status, 204);
  assert.equal(use_appStoreServerNotificationV2(request({}, { method: "OPTIONS" })).status, 204);
  assert.equal(use_googlePlayRtdn(request({}, { method: "OPTIONS" })).status, 204);
});
