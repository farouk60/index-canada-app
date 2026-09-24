import assert from "node:assert/strict";
import { register } from "node:module";
import test from "node:test";

register("./wix-test-loader.mjs", import.meta.url);

const { __wixDataTest } = await import("wix-data");
const { Permissions } = await import("wix-web-module");
const {
  getEngagementReport,
  MAX_SYNC_REPORT_EVENTS,
} = await import("../engagement-report.web.js");

test("le rapport Wix est réservé aux administrateurs et ne retourne que des agrégats", async () => {
  __wixDataTest.reset({
    EngagementEvents: [
      {
        _id: "evt_1",
        eventIdHash: "secret-internal-id",
        professionalId: "pro_123",
        type: "professional_view",
        placement: "detail",
        _createdDate: new Date("2026-09-02T10:00:00.000Z"),
      },
      {
        _id: "evt_2",
        professionalId: "pro_other",
        type: "contact",
        channel: "phone",
        placement: "detail",
        _createdDate: new Date("2026-09-02T11:00:00.000Z"),
      },
    ],
  });

  assert.equal(getEngagementReport.permission, Permissions.Admin);
  const report = await getEngagementReport({
    professionalId: "pro_123",
    from: "2026-09-01",
    to: "2026-09-03",
  });

  assert.equal(report.totals.views, 1);
  assert.equal(report.totals.contacts, 0);
  assert.equal("eventIdHash" in report, false);
  assert.equal("events" in report, false);

  const findCall = __wixDataTest.calls.find(
    (call) => call.type === "find" && call.collection === "EngagementEvents",
  );
  assert.deepEqual(findCall.options, { suppressAuth: true, consistentRead: true });
});

test("le rapport pagine tous les événements sous le plafond synchrone", async () => {
  const items = Array.from({ length: 2_005 }, (_, index) => ({
    _id: `evt_${index}`,
    professionalId: "pro_paged",
    type: "professional_impression",
    placement: "directory",
    _createdDate: new Date("2026-09-02T10:00:00.000Z"),
  }));
  __wixDataTest.reset({ EngagementEvents: items });

  const report = await getEngagementReport({
    professionalId: "pro_paged",
    from: "2026-09-01",
    to: "2026-09-03",
  });

  assert.equal(report.totals.impressions, 2_005);
  assert.equal(
    __wixDataTest.calls.filter((call) => call.type === "next").length,
    2,
  );
});

test("le rapport refuse explicitement un volume excessif avant de charger une page", async () => {
  const items = Array.from({ length: MAX_SYNC_REPORT_EVENTS + 1 }, (_, index) => ({
    _id: `evt_limit_${index}`,
    professionalId: "pro_limit",
    type: "professional_impression",
    placement: "directory",
    _createdDate: new Date("2026-09-02T10:00:00.000Z"),
  }));
  __wixDataTest.reset({ EngagementEvents: items });

  await assert.rejects(
    () => getEngagementReport({
      professionalId: "pro_limit",
      from: "2026-09-01",
      to: "2026-09-03",
    }),
    /REPORT_EVENT_LIMIT_EXCEEDED/,
  );

  const calls = __wixDataTest.calls;
  assert.equal(calls.some((call) => call.type === "count"), true);
  assert.equal(calls.some((call) => call.type === "find"), false);
});
