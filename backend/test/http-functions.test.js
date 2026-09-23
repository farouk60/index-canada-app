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
  use_categories,
  use_professionals,
  use_search_professionals,
  use_searchProfessionals,
} = await import("../http-functions.js");

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

function seed(data = {}) {
  __wixDataTest.reset({
    ApiRateLimits: [],
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

test("les handlers use_* distinguent OPTIONS des méthodes non autorisées", () => {
  const preflight = use_categories(request({}, { method: "OPTIONS" }));
  const rejected = use_professionals(request({}, { method: "POST" }));
  const searchPreflight = use_searchProfessionals(request({}, { method: "OPTIONS" }));
  const legacySearchPreflight = use_search_professionals(request({}, { method: "OPTIONS" }));
  const rejectedSearch = use_searchProfessionals(request({}, { method: "POST" }));

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
});
