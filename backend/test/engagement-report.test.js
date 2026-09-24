import test from "node:test";
import assert from "node:assert/strict";

import { buildEngagementReport } from "../engagement-report.js";

const event = (overrides = {}) => ({
  professionalId: "pro_123",
  type: "professional_view",
  placement: "directory",
  _createdDate: new Date("2026-09-02T12:00:00.000Z"),
  ...overrides,
});

test("buildEngagementReport agrège les interactions par jour, canal et placement", () => {
  const report = buildEngagementReport(
    [
      event({
        type: "professional_impression",
        placement: "home_featured",
        _createdDate: "2026-09-01T12:00:00.000Z",
      }),
      event({ type: "professional_impression", _createdDate: "2026-09-01T13:00:00.000Z" }),
      event({ type: "professional_click", placement: "home_featured" }),
      event({ type: "professional_view" }),
      event({ type: "contact", channel: "phone" }),
      event({ type: "contact", channel: "website" }),
      event({ type: "coupon_copy" }),
      event({ professionalId: "pro_other", type: "contact", channel: "map" }),
      event({ type: "search" }),
      event({ type: "contact", channel: "map", _createdDate: "2026-09-04T00:00:00.000Z" }),
    ],
    {
      professionalId: "pro_123",
      from: "2026-09-01",
      to: "2026-09-03",
    },
  );

  assert.deepEqual(report.period, { from: "2026-09-01", to: "2026-09-03" });
  assert.deepEqual(report.totals, {
    impressions: 2,
    clicks: 1,
    views: 1,
    contacts: 2,
    couponCopies: 1,
    contactsByChannel: { phone: 1, website: 1, map: 0 },
  });
  assert.deepEqual(report.ratios, {
    homeFeaturedClicksPerImpression: 1,
    attributedViewsPerImpression: 0.5,
    contactActionsPerView: 2,
    couponCopiesPerView: 1,
  });
  assert.equal(report.byDay.length, 3);
  assert.deepEqual(report.byDay[2], {
    date: "2026-09-03",
    impressions: 0,
    clicks: 0,
    views: 0,
    contacts: 0,
    couponCopies: 0,
  });
  assert.equal(report.byPlacement.home_featured.clicks, 1);
  assert.equal(report.byPlacement.directory.contacts, 2);
  assert.deepEqual(report.dataQuality, {
    trustLevel: "client_reported_unverified",
    eligibleForBilling: false,
  });
  assert.equal(
    report.notice,
    "Interactions anonymes déclarées par les clients; aucun visiteur unique, aucune vente attribuée et aucune base de facturation.",
  );
  assert.equal("events" in report, false);
});

test("buildEngagementReport retourne des ratios nuls sans dénominateur", () => {
  const report = buildEngagementReport([], {
    professionalId: "pro_123",
    from: "2026-09-01",
    to: "2026-09-01",
  });

  assert.deepEqual(report.ratios, {
    homeFeaturedClicksPerImpression: 0,
    attributedViewsPerImpression: 0,
    contactActionsPerView: 0,
    couponCopiesPerView: 0,
  });
});

test("buildEngagementReport exclut les vues directes du ratio attribué", () => {
  const report = buildEngagementReport(
    [
      event({ type: "professional_impression", placement: "directory" }),
      event({ type: "professional_view", placement: "directory" }),
      event({ type: "professional_view", placement: "detail" }),
    ],
    {
      professionalId: "pro_123",
      from: "2026-09-01",
      to: "2026-09-03",
    },
  );

  assert.equal(report.totals.views, 2);
  assert.equal(report.ratios.attributedViewsPerImpression, 1);
});

test("buildEngagementReport rejette les identifiants et périodes invalides", () => {
  assert.throws(
    () => buildEngagementReport([], { professionalId: "", from: "2026-09-01", to: "2026-09-02" }),
    /professionalId/,
  );
  assert.throws(
    () => buildEngagementReport([], { professionalId: "pro_123", from: "09-01-2026", to: "2026-09-02" }),
    /from/,
  );
  assert.throws(
    () => buildEngagementReport([], { professionalId: "pro_123", from: "2026-09-03", to: "2026-09-02" }),
    /période/,
  );
  assert.throws(
    () => buildEngagementReport([], { professionalId: "pro_123", from: "2025-01-01", to: "2026-09-02" }),
    /366 jours/,
  );
});
