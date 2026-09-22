import { createHash } from "crypto";

export const DIRECTORY_COLLECTION_LIMITS = Object.freeze({
  Professionnel: 10_000,
  Reviews: 10_000,
  SousCategorie: 2_000,
  Partenaires: 2_000,
  OffresPartenaire: 2_000,
});

const DIRECTORY_CURSOR_VERSION = 1;
const DIRECTORY_CURSOR_MAX_CHARS = 512;
const DIRECTORY_FILTER_KEY_MAX_CHARS = 2_000;
const DIRECTORY_ID_PATTERN = /^[A-Za-z0-9_-]{1,100}$/u;

export class DirectoryPaginationInputError extends Error {
  constructor(code) {
    super(code);
    this.name = "DirectoryPaginationInputError";
    this.code = code;
  }
}

export class DirectoryDatasetLimitError extends Error {
  constructor({ collection, maxItems, itemCount, minimumItemCount, pageCount }) {
    super(`La collection ${collection} dépasse le plafond de ${maxItems} éléments`);
    this.name = "DirectoryDatasetLimitError";
    this.code = "DIRECTORY_DATASET_LIMIT_EXCEEDED";
    this.collection = collection;
    this.maxItems = maxItems;
    this.itemCount = itemCount;
    this.minimumItemCount = minimumItemCount;
    this.pageCount = pageCount;
  }
}

function collectionLimit(collection, override) {
  const maxItems = override ?? DIRECTORY_COLLECTION_LIMITS[collection];
  if (!Number.isSafeInteger(maxItems) || maxItems < 1) {
    throw new RangeError(`Plafond invalide ou absent pour la collection ${collection}`);
  }
  return maxItems;
}

function validatePage(page, collection) {
  if (!page || typeof page !== "object" || !Array.isArray(page.items)) {
    throw new TypeError(`Page Wix invalide pour la collection ${collection}`);
  }
  if (typeof page.hasNext !== "function") {
    throw new TypeError(`hasNext() est absent pour la collection ${collection}`);
  }
}

function normalizeCursorContext(collection, filterKey = "") {
  if (
    typeof collection !== "string"
    || collection.trim() !== collection
    || collection.length < 1
    || collection.length > 80
    || typeof filterKey !== "string"
    || filterKey.length > DIRECTORY_FILTER_KEY_MAX_CHARS
  ) {
    throw new DirectoryPaginationInputError("INVALID_CURSOR_CONTEXT");
  }
  return createHash("sha256")
    .update(`${collection}\n${filterKey}`, "utf8")
    .digest("hex");
}

function encodeBase64Url(value) {
  return Buffer.from(value, "utf8")
    .toString("base64")
    .replace(/=/gu, "")
    .replace(/\+/gu, "-")
    .replace(/\//gu, "_");
}

function decodeCanonicalBase64Url(value) {
  if (
    typeof value !== "string"
    || value.length < 1
    || value.length > DIRECTORY_CURSOR_MAX_CHARS
    || !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    throw new DirectoryPaginationInputError("INVALID_CURSOR");
  }
  const normalized = value.replace(/-/gu, "+").replace(/_/gu, "/");
  const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
  const decoded = Buffer.from(`${normalized}${padding}`, "base64").toString("utf8");
  if (encodeBase64Url(decoded) !== value) {
    throw new DirectoryPaginationInputError("INVALID_CURSOR");
  }
  return decoded;
}

/**
 * Produit un curseur opaque lié à une collection et aux filtres normalisés.
 * Le curseur n'accorde aucun droit : les filtres de visibilité sont toujours
 * réappliqués côté Wix et en mémoire lors de la page suivante.
 */
export function createDirectoryCursor({ collection, filterKey = "", lastId }) {
  if (typeof lastId !== "string" || !DIRECTORY_ID_PATTERN.test(lastId)) {
    throw new DirectoryPaginationInputError("INVALID_CURSOR_POSITION");
  }
  const payload = JSON.stringify({
    v: DIRECTORY_CURSOR_VERSION,
    c: collection,
    f: normalizeCursorContext(collection, filterKey),
    l: lastId,
  });
  return encodeBase64Url(payload);
}

export function parseDirectoryCursor(cursor, { collection, filterKey = "" }) {
  let payload;
  try {
    payload = JSON.parse(decodeCanonicalBase64Url(cursor));
  } catch (error) {
    if (error instanceof DirectoryPaginationInputError) throw error;
    throw new DirectoryPaginationInputError("INVALID_CURSOR");
  }
  if (
    !payload
    || typeof payload !== "object"
    || Array.isArray(payload)
    || Object.keys(payload).sort().join(",") !== "c,f,l,v"
    || payload.v !== DIRECTORY_CURSOR_VERSION
    || payload.c !== collection
    || payload.f !== normalizeCursorContext(collection, filterKey)
    || typeof payload.l !== "string"
    || !DIRECTORY_ID_PATTERN.test(payload.l)
  ) {
    throw new DirectoryPaginationInputError("INVALID_CURSOR");
  }
  return Object.freeze({ lastId: payload.l });
}

export function normalizeDirectoryPageRequest(
  query = {},
  {
    collection,
    filterKey = "",
    defaultLimit = 25,
    maxLimit = 100,
  },
) {
  if (!query || typeof query !== "object" || Array.isArray(query)) {
    throw new DirectoryPaginationInputError("INVALID_PAGINATION");
  }
  if (!Number.isSafeInteger(defaultLimit) || defaultLimit < 1 || !Number.isSafeInteger(maxLimit) || maxLimit < defaultLimit) {
    throw new RangeError("Configuration de pagination invalide");
  }
  let limit = defaultLimit;
  if (query.limit !== undefined && query.limit !== null && query.limit !== "") {
    const rawLimit = String(query.limit);
    if (!/^\d{1,3}$/u.test(rawLimit)) {
      throw new DirectoryPaginationInputError("INVALID_PAGE_SIZE");
    }
    limit = Number.parseInt(rawLimit, 10);
    if (limit < 1 || limit > maxLimit) {
      throw new DirectoryPaginationInputError("INVALID_PAGE_SIZE");
    }
  }
  const cursor = query.cursor;
  const lastId = cursor === undefined || cursor === null || cursor === ""
    ? null
    : parseDirectoryCursor(cursor, { collection, filterKey }).lastId;
  return Object.freeze({ limit, lastId });
}

export function buildDirectoryPage(
  rawItems,
  {
    collection,
    filterKey = "",
    limit,
    isVisible = () => true,
    project = (item) => item,
  },
) {
  if (!Array.isArray(rawItems) || !Number.isSafeInteger(limit) || limit < 1) {
    throw new TypeError("Résultat de pagination invalide");
  }
  if (typeof isVisible !== "function" || typeof project !== "function") {
    throw new TypeError("Fonctions de pagination invalides");
  }
  const window = rawItems.slice(0, limit);
  if (window.some((item) => !item || typeof item !== "object" || !DIRECTORY_ID_PATTERN.test(item._id))) {
    throw new TypeError(`Identifiant Wix invalide pour la collection ${collection}`);
  }
  const hasMore = rawItems.length > limit;
  const nextCursor = hasMore
    ? createDirectoryCursor({
      collection,
      filterKey,
      lastId: window[window.length - 1]._id,
    })
    : null;
  return Object.freeze({
    items: Object.freeze(window.filter(isVisible).map(project)),
    pagination: Object.freeze({
      limit,
      hasMore,
      nextCursor,
    }),
  });
}

/**
 * Réunit les pages successives d'un résultat Wix en conservant leur ordre.
 *
 * Le plafond est obligatoire : il provient de DIRECTORY_COLLECTION_LIMITS ou
 * d'un override explicite. Une collection trop grande provoque une erreur au
 * lieu de produire silencieusement une réponse partielle.
 */
export async function collectAllPages(firstPagePromise, { collection, maxItems } = {}) {
  if (typeof collection !== "string" || collection.trim() === "") {
    throw new TypeError("Le nom de collection est obligatoire");
  }

  const normalizedCollection = collection.trim();
  const resolvedMaxItems = collectionLimit(normalizedCollection, maxItems);
  const items = [];
  let page = await firstPagePromise;
  let pageCount = 0;

  while (true) {
    validatePage(page, normalizedCollection);
    pageCount += 1;

    const projectedItemCount = items.length + page.items.length;
    if (projectedItemCount > resolvedMaxItems) {
      throw new DirectoryDatasetLimitError({
        collection: normalizedCollection,
        maxItems: resolvedMaxItems,
        itemCount: items.length,
        minimumItemCount: projectedItemCount,
        pageCount,
      });
    }

    items.push(...page.items);
    const hasMore = Boolean(await page.hasNext());
    if (!hasMore) {
      return {
        items,
        metadata: Object.freeze({
          collection: normalizedCollection,
          pageCount,
          itemCount: items.length,
          maxItems: resolvedMaxItems,
          complete: true,
        }),
      };
    }

    if (items.length >= resolvedMaxItems) {
      throw new DirectoryDatasetLimitError({
        collection: normalizedCollection,
        maxItems: resolvedMaxItems,
        itemCount: items.length,
        minimumItemCount: items.length + 1,
        pageCount,
      });
    }

    if (typeof page.next !== "function") {
      throw new TypeError(`next() est absent pour la collection ${normalizedCollection}`);
    }
    page = await page.next();
  }
}
