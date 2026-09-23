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

const DATA_OPTIONS = Object.freeze({ suppressAuth: true });
const CONSISTENT_DATA_OPTIONS = Object.freeze({ suppressAuth: true, consistentRead: true });
const CHECKOUT_COLLECTION = "PaymentCheckouts";
const RATE_LIMIT_COLLECTION = "ApiRateLimits";
const CHECKOUT_VERSION = "2";
const STRIPE_SECRET_NAME = "STRIPE_SECRET_KEY";
const STRIPE_WEBHOOK_SECRET_NAME = "STRIPE_WEBHOOK_SECRET";
const CHECKOUT_SIGNING_SECRET_NAME = "CHECKOUT_SIGNING_SECRET";

const RATE_LIMITS = Object.freeze({
  directory: Object.freeze({ limit: 120, windowMs: 60_000, failClosed: false }),
  search: Object.freeze({ limit: 60, windowMs: 60_000, failClosed: false }),
  plans: Object.freeze({ limit: 120, windowMs: 60_000, failClosed: false }),
  review: Object.freeze({ limit: 5, windowMs: 60 * 60_000, failClosed: true }),
  checkout: Object.freeze({ limit: 10, windowMs: 15 * 60_000, failClosed: true }),
  confirmation: Object.freeze({ limit: 20, windowMs: 15 * 60_000, failClosed: true }),
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
let webhookSecretPromise;

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
      .filter((item) => item.isActive === true)
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
        totalProfessionnels: professionalsResult.items.filter((item) => item.isActive === true).length,
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
      .filter((item) => item.isActive === true)
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
  if (!item || item.isActive !== true || !professionalMatches(item, filters)) return false;
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
    if (!professional || professional.isActive !== true) {
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
    if (!professional || professional.isActive !== true) {
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

async function finalizeCheckout(checkout, { plan, paymentId }) {
  // Wix Data cannot atomically insert the profile and update the checkout.
  // A deterministic profile id makes a retry repair the second write safely.
  validateStoredCheckout(checkout);
  const professionalId = buildProfessionalId(`checkout:${checkout._id}`);
  const existing = await findById("Professionnel", professionalId, { consistentRead: true });
  if (existing) {
    if (existing.checkoutId !== checkout._id) {
      throw new PaymentFlowError("PAYMENT_ALREADY_USED", 409);
    }
    const repairedCheckout = checkout.status === "finalized"
      && checkout.professionalId === professionalId
      ? checkout
      : await updateCheckout(checkout, {
        status: "finalized",
        paymentIntentId: plan.requiresPayment ? paymentId : checkout.paymentIntentId,
        professionalId,
        finalizedAt: new Date().toISOString(),
      });
    return { checkout: repairedCheckout, professional: existing, idempotent: true };
  }

  const record = buildProfessionalRecord(checkout, paymentId);
  const saved = await insertProfessionalOnce(record);
  const finalizedCheckout = await updateCheckout(checkout, {
    status: "finalized",
    paymentIntentId: plan.requiresPayment ? paymentId : checkout.paymentIntentId,
    professionalId: saved.item._id,
    finalizedAt: new Date().toISOString(),
  });
  return { checkout: finalizedCheckout, professional: saved.item, idempotent: saved.idempotent };
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

export { get_data as data_get };
export { get_searchProfessionals as searchProfessionals_get };
export { get_categories as categories_get };
export { get_professionals as professionals_get };
export { get_reviews as reviews_get };
export { get_partners as partners_get };
export { get_offers as offers_get };
export { get_paymentPlans as paymentPlans_get };
export { post_review as review_post };
export { post_createPaymentIntent as createPaymentIntent_post };
export { post_confirmPayment as confirmPayment_post };
export { post_stripeWebhook as stripeWebhook_post };
