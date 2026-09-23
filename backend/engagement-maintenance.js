import wixData from "wix-data";

const ENGAGEMENT_COLLECTION = "EngagementEvents";
const RATE_LIMIT_COLLECTION = "ApiRateLimits";
const DATA_OPTIONS = Object.freeze({ suppressAuth: true, consistentRead: true });
const DELETE_OPTIONS = Object.freeze({ suppressAuth: true });
const RETENTION_DAYS = 400;
const DAY_MS = 24 * 60 * 60 * 1000;
const BATCH_SIZE = 1000;
const MAX_BATCHES_PER_RUN = 25;

function validatePurgeOptions(cutoff, maxBatches) {
  if (!(cutoff instanceof Date) || !Number.isFinite(cutoff.getTime())) {
    throw new Error("cutoff doit être une date valide.");
  }
  if (!Number.isInteger(maxBatches) || maxBatches < 1 || maxBatches > 100) {
    throw new Error("maxBatches est invalide.");
  }
}

function normalizeBulkError(collection, entry) {
  const itemId = typeof entry?.itemId === "string"
    ? entry.itemId
    : typeof entry?.item?._id === "string"
      ? entry.item._id
      : typeof entry?.item === "string"
        ? entry.item
        : null;
  const code = String(entry?.error?.code ?? entry?.code ?? "BULK_REMOVE_FAILED")
    .slice(0, 100);
  return { collection, itemId, code };
}

function inspectBulkRemoveResult(collection, attemptedIds, result) {
  const attempted = new Set(attemptedIds);
  const removedItemIds = Array.isArray(result?.removedItemIds)
    ? [...new Set(result.removedItemIds.filter((id) => attempted.has(id)))]
    : [];
  const errors = Array.isArray(result?.errors)
    ? result.errors.map((entry) => normalizeBulkError(collection, entry))
    : [];
  const accountedIds = new Set([
    ...removedItemIds,
    ...errors.map((entry) => entry.itemId).filter(Boolean),
  ]);
  for (const itemId of attemptedIds) {
    if (!accountedIds.has(itemId)) {
      errors.push({ collection, itemId, code: "UNCONFIRMED_REMOVAL" });
    }
  }
  return { removedItemIds, errors };
}

function logPartialRemoval(collection, attempted, removed, errors) {
  if (errors.length === 0 && attempted === removed) return;
  console.error(JSON.stringify({
    event: "retention_bulk_remove_partial",
    collection,
    attempted,
    removed,
    errorCount: errors.length,
    errorCodes: [...new Set(errors.map((entry) => entry.code))],
  }));
}

async function hasExpiredItems(collection, field, cutoffValue) {
  const result = await wixData
    .query(collection)
    .lt(field, cutoffValue)
    .limit(1)
    .find(DATA_OPTIONS);
  return result.items.length > 0;
}

async function purgeCollectionBefore(
  { collection, field, cutoffValue },
  { maxBatches = MAX_BATCHES_PER_RUN } = {},
) {
  let attempted = 0;
  let removed = 0;
  let batches = 0;
  let hasMore = false;
  const errors = [];

  while (batches < maxBatches) {
    const page = await wixData
      .query(collection)
      .lt(field, cutoffValue)
      .ascending(field)
      .limit(BATCH_SIZE)
      .find(DATA_OPTIONS);
    const ids = [...new Set(page.items.map((item) => item?._id).filter(Boolean))];
    if (ids.length === 0) break;

    const result = await wixData.bulkRemove(collection, ids, DELETE_OPTIONS);
    const inspected = inspectBulkRemoveResult(collection, ids, result);
    attempted += ids.length;
    removed += inspected.removedItemIds.length;
    batches += 1;
    errors.push(...inspected.errors);
    logPartialRemoval(
      collection,
      ids.length,
      inspected.removedItemIds.length,
      inspected.errors,
    );

    // Un échec partiel resterait en tête de la requête suivante. On arrête ce
    // passage borné et on laisse la tâche quotidienne le reprendre.
    if (inspected.removedItemIds.length !== ids.length || inspected.errors.length > 0) {
      hasMore = true;
      break;
    }
  }

  if (batches === maxBatches || hasMore) {
    hasMore = await hasExpiredItems(collection, field, cutoffValue);
  }

  return { attempted, removed, batches, hasMore, errors };
}

export async function purgeEngagementEventsBefore(
  cutoff,
  { maxBatches = MAX_BATCHES_PER_RUN } = {},
) {
  validatePurgeOptions(cutoff, maxBatches);
  return purgeCollectionBefore(
    {
      collection: ENGAGEMENT_COLLECTION,
      field: "_createdDate",
      cutoffValue: cutoff,
    },
    { maxBatches },
  );
}

export async function purgeApiRateLimitsBefore(
  cutoff,
  { maxBatches = MAX_BATCHES_PER_RUN } = {},
) {
  validatePurgeOptions(cutoff, maxBatches);
  return purgeCollectionBefore(
    {
      collection: RATE_LIMIT_COLLECTION,
      field: "expiresAt",
      cutoffValue: cutoff.toISOString(),
    },
    { maxBatches },
  );
}

function scheduledResult(collectionKey, result) {
  const errorCount = result.errors.length;
  return {
    [collectionKey]: result,
    hasMore: result.hasMore,
    errorCount,
    ok: errorCount === 0 && !result.hasMore,
  };
}

/** Tâche Wix quotidienne dédiée à la rétention des événements ROI. */
export async function purgeExpiredEngagementEvents({
  nowMs = Date.now(),
  maxBatches = MAX_BATCHES_PER_RUN,
} = {}) {
  if (!Number.isFinite(nowMs)) throw new Error("nowMs est invalide.");
  const engagementCutoff = new Date(nowMs - RETENTION_DAYS * DAY_MS);

  try {
    const engagementEvents = await purgeEngagementEventsBefore(
      engagementCutoff,
      { maxBatches },
    );
    const result = scheduledResult("engagementEvents", engagementEvents);
    console.info(JSON.stringify({
      event: "engagement_retention_completed",
      engagementRemoved: engagementEvents.removed,
      hasMore: result.hasMore,
      errorCount: result.errorCount,
    }));
    return result;
  } catch (error) {
    console.error(JSON.stringify({
      event: "engagement_retention_failed",
      code: String(error?.code ?? error?.name ?? "ERROR").slice(0, 100),
    }));
    throw error;
  }
}

/** Tâche Wix quotidienne séparée pour ne pas affamer le nettoyage anti-abus. */
export async function purgeExpiredApiRateLimits({
  nowMs = Date.now(),
  maxBatches = MAX_BATCHES_PER_RUN,
} = {}) {
  if (!Number.isFinite(nowMs)) throw new Error("nowMs est invalide.");

  try {
    const apiRateLimits = await purgeApiRateLimitsBefore(
      new Date(nowMs),
      { maxBatches },
    );
    const result = scheduledResult("apiRateLimits", apiRateLimits);
    console.info(JSON.stringify({
      event: "api_rate_limit_retention_completed",
      rateLimitsRemoved: apiRateLimits.removed,
      hasMore: result.hasMore,
      errorCount: result.errorCount,
    }));
    return result;
  } catch (error) {
    console.error(JSON.stringify({
      event: "api_rate_limit_retention_failed",
      code: String(error?.code ?? error?.name ?? "ERROR").slice(0, 100),
    }));
    throw error;
  }
}
