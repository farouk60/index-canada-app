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
  post_engagementEvent,
  use_categories,
  use_engagementEvent,
  use_professionals,
  use_search_professionals,
  use_searchProfessionals,
} = await import("../http-functions.js");
const { buildEngagementEventRecord } = await import("../security-core.js");

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
    SousCategorie: [],
    Professionnel: [],
    Reviews: [],
    Partenaires: [],
    OffresPartenaire: [],
    ...data,
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
