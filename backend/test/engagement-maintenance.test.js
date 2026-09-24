import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { register } from "node:module";
import test from "node:test";

register("./wix-test-loader.mjs", import.meta.url);

const { __wixDataTest } = await import("wix-data");
const {
  purgeApiRateLimitsBefore,
  purgeExpiredApiRateLimits,
  purgeEngagementEventsBefore,
  purgeExpiredEngagementEvents,
} = await import("../engagement-maintenance.js");

test("la purge supprime seulement les événements antérieurs à la rétention", async () => {
  __wixDataTest.reset({
    EngagementEvents: [
      { _id: "old_1", _createdDate: new Date("2025-08-01T00:00:00.000Z") },
      { _id: "old_2", _createdDate: new Date("2025-08-31T23:59:59.999Z") },
      { _id: "boundary", _createdDate: new Date("2025-09-01T00:00:00.000Z") },
      { _id: "recent", _createdDate: new Date("2026-09-01T00:00:00.000Z") },
    ],
  });

  const result = await purgeEngagementEventsBefore(
    new Date("2025-09-01T00:00:00.000Z"),
  );

  assert.deepEqual(result, {
    attempted: 2,
    removed: 2,
    batches: 1,
    hasMore: false,
    errors: [],
  });
  assert.deepEqual(
    __wixDataTest.items("EngagementEvents").map((item) => item._id),
    ["boundary", "recent"],
  );
  const removeCall = __wixDataTest.calls.find((call) => call.type === "bulkRemove");
  assert.deepEqual([...removeCall.itemIds].sort(), ["old_1", "old_2"]);
  assert.deepEqual(removeCall.options, { suppressAuth: true });
});

test("la purge vide retourne un résultat déterministe sans suppression", async () => {
  __wixDataTest.reset({ EngagementEvents: [] });
  const result = await purgeEngagementEventsBefore(
    new Date("2025-09-01T00:00:00.000Z"),
  );

  assert.deepEqual(result, {
    attempted: 0,
    removed: 0,
    batches: 0,
    hasMore: false,
    errors: [],
  });
  assert.equal(__wixDataTest.calls.some((call) => call.type === "bulkRemove"), false);
});

test("la purge rejette une date de coupure invalide", async () => {
  await assert.rejects(
    () => purgeEngagementEventsBefore(new Date("invalid")),
    /cutoff/,
  );
});

test("la purge compte seulement les suppressions confirmées et expose les erreurs partielles", async () => {
  __wixDataTest.reset({
    EngagementEvents: [
      { _id: "old_ok", _createdDate: new Date("2025-08-01T00:00:00.000Z") },
      { _id: "old_error", _createdDate: new Date("2025-08-02T00:00:00.000Z") },
    ],
  });
  __wixDataTest.setBulkRemoveResults([
    {
      removedItemIds: ["old_ok"],
      errors: [{ itemId: "old_error", error: { code: "WDE_PARTIAL" } }],
    },
  ]);

  const result = await purgeEngagementEventsBefore(
    new Date("2025-09-01T00:00:00.000Z"),
  );

  assert.equal(result.attempted, 2);
  assert.equal(result.removed, 1);
  assert.equal(result.batches, 1);
  assert.equal(result.hasMore, true);
  assert.deepEqual(result.errors, [
    {
      collection: "EngagementEvents",
      itemId: "old_error",
      code: "WDE_PARTIAL",
    },
  ]);
  assert.deepEqual(
    __wixDataTest.items("EngagementEvents").map((item) => item._id),
    ["old_error"],
  );
});

test("la purge traite plusieurs lots tout en respectant la borne configurée", async () => {
  const items = Array.from({ length: 2_005 }, (_, index) => ({
    _id: `old_${String(index).padStart(4, "0")}`,
    _createdDate: new Date("2025-08-01T00:00:00.000Z"),
  }));
  __wixDataTest.reset({ EngagementEvents: items });

  const result = await purgeEngagementEventsBefore(
    new Date("2025-09-01T00:00:00.000Z"),
    { maxBatches: 2 },
  );

  assert.deepEqual(result, {
    attempted: 2_000,
    removed: 2_000,
    batches: 2,
    hasMore: true,
    errors: [],
  });
  assert.equal(__wixDataTest.items("EngagementEvents").length, 5);
});

test("les tâches quotidiennes purgent séparément événements et limiteurs", async () => {
  __wixDataTest.reset({
    EngagementEvents: [
      { _id: "event_old", _createdDate: new Date("2025-08-01T00:00:00.000Z") },
      { _id: "event_recent", _createdDate: new Date("2026-09-22T00:00:00.000Z") },
    ],
    ApiRateLimits: [
      { _id: "rate_old", expiresAt: "2026-09-22T23:59:59.999Z" },
      { _id: "rate_boundary", expiresAt: "2026-09-23T00:00:00.000Z" },
      { _id: "rate_future", expiresAt: "2026-09-23T00:01:00.000Z" },
    ],
  });

  const directRateResult = await purgeApiRateLimitsBefore(
    new Date("2026-09-23T00:00:00.000Z"),
  );
  assert.equal(directRateResult.removed, 1);
  assert.deepEqual(
    __wixDataTest.items("ApiRateLimits").map((item) => item._id),
    ["rate_boundary", "rate_future"],
  );

  const result = await purgeExpiredEngagementEvents({
    nowMs: Date.parse("2026-09-23T00:00:00.000Z"),
  });

  assert.equal(result.engagementEvents.removed, 1);
  assert.equal(result.hasMore, false);
  assert.equal(result.errorCount, 0);
  assert.equal(result.ok, true);

  const rateResult = await purgeExpiredApiRateLimits({
    nowMs: Date.parse("2026-09-23T00:00:00.000Z"),
  });
  assert.equal(rateResult.apiRateLimits.removed, 0);
  assert.equal(rateResult.hasMore, false);
  assert.equal(rateResult.ok, true);
});

test("une tâche bornée avec reliquat signale un état non sain", async () => {
  __wixDataTest.reset({
    EngagementEvents: Array.from({ length: 1_001 }, (_, index) => ({
      _id: `event_${index}`,
      _createdDate: new Date("2025-01-01T00:00:00.000Z"),
    })),
  });

  const result = await purgeExpiredEngagementEvents({
    nowMs: Date.parse("2026-09-23T00:00:00.000Z"),
    maxBatches: 1,
  });
  assert.equal(result.hasMore, true);
  assert.equal(result.ok, false);
});

test("la rétention Wix est programmée chaque jour", async () => {
  const jobs = JSON.parse(
    await readFile(new URL("../jobs.config", import.meta.url), "utf8"),
  );
  const engagementJob = jobs.jobs.find(
    (job) => job.functionName === "purgeExpiredEngagementEvents",
  );
  const rateLimitJob = jobs.jobs.find(
    (job) => job.functionName === "purgeExpiredApiRateLimits",
  );

  assert.equal(engagementJob.executionConfig.time, "04:15");
  assert.equal(rateLimitJob.executionConfig.time, "04:45");
  assert.equal(Object.hasOwn(engagementJob.executionConfig, "dayOfWeek"), false);
  assert.equal(Object.hasOwn(rateLimitJob.executionConfig, "dayOfWeek"), false);
});
