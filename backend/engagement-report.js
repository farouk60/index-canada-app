const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_REPORT_DAYS = 366;
const PROFESSIONAL_ID_PATTERN = /^[A-Za-z0-9_-]{1,100}$/;
const REPORT_TYPES = new Set([
  "professional_impression",
  "professional_click",
  "professional_view",
  "contact",
  "coupon_copy",
]);
const CONTACT_CHANNELS = Object.freeze(["phone", "website", "map"]);
const PLACEMENTS = Object.freeze([
  "directory",
  "home_featured",
  "detail",
]);

function parseUtcDay(value, field) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${field} doit respecter YYYY-MM-DD.`);
  }
  const timestamp = Date.parse(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(timestamp) || new Date(timestamp).toISOString().slice(0, 10) !== value) {
    throw new Error(`${field} est invalide.`);
  }
  return timestamp;
}

function emptyMetrics() {
  return {
    impressions: 0,
    clicks: 0,
    views: 0,
    contacts: 0,
    couponCopies: 0,
  };
}

function increment(metrics, type) {
  if (type === "professional_impression") metrics.impressions += 1;
  if (type === "professional_click") metrics.clicks += 1;
  if (type === "professional_view") metrics.views += 1;
  if (type === "contact") metrics.contacts += 1;
  if (type === "coupon_copy") metrics.couponCopies += 1;
}

function ratio(numerator, denominator) {
  if (denominator === 0) return 0;
  return Number((numerator / denominator).toFixed(4));
}

function eventTimestamp(item) {
  const value = item?._createdDate;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "string" || typeof value === "number") {
    return new Date(value).getTime();
  }
  return Number.NaN;
}

/**
 * Produit une projection agrégée, sans exposer les événements ni leurs IDs.
 * Les ratios décrivent des actions, et non des visiteurs ou ventes attribués.
 */
export function buildEngagementReport(items, { professionalId, from, to }) {
  if (!Array.isArray(items)) throw new Error("items doit être un tableau.");
  if (typeof professionalId !== "string" || !PROFESSIONAL_ID_PATTERN.test(professionalId)) {
    throw new Error("professionalId est invalide.");
  }

  const fromMs = parseUtcDay(from, "from");
  const toMs = parseUtcDay(to, "to");
  if (toMs < fromMs) throw new Error("La période est inversée.");
  const dayCount = Math.floor((toMs - fromMs) / DAY_MS) + 1;
  if (dayCount > MAX_REPORT_DAYS) {
    throw new Error("La période ne peut pas dépasser 366 jours.");
  }
  const exclusiveEndMs = toMs + DAY_MS;

  const totals = {
    ...emptyMetrics(),
    contactsByChannel: { phone: 0, website: 0, map: 0 },
  };
  const dayIndex = new Map();
  const byDay = [];
  for (let offset = 0; offset < dayCount; offset += 1) {
    const date = new Date(fromMs + offset * DAY_MS).toISOString().slice(0, 10);
    const metrics = { date, ...emptyMetrics() };
    dayIndex.set(date, metrics);
    byDay.push(metrics);
  }

  const byPlacement = Object.fromEntries(
    PLACEMENTS.map((placement) => [placement, emptyMetrics()]),
  );

  for (const item of items) {
    if (item?.professionalId !== professionalId || !REPORT_TYPES.has(item?.type)) continue;
    const timestamp = eventTimestamp(item);
    if (!Number.isFinite(timestamp) || timestamp < fromMs || timestamp >= exclusiveEndMs) continue;

    increment(totals, item.type);
    const date = new Date(timestamp).toISOString().slice(0, 10);
    increment(dayIndex.get(date), item.type);

    if (Object.hasOwn(byPlacement, item.placement)) {
      increment(byPlacement[item.placement], item.type);
    }
    if (item.type === "contact" && CONTACT_CHANNELS.includes(item.channel)) {
      totals.contactsByChannel[item.channel] += 1;
    }
  }

  return {
    version: 1,
    professionalId,
    period: { from, to },
    totals,
    ratios: {
      homeFeaturedClicksPerImpression: ratio(
        byPlacement.home_featured.clicks,
        byPlacement.home_featured.impressions,
      ),
      attributedViewsPerImpression: ratio(
        byPlacement.home_featured.views + byPlacement.directory.views,
        byPlacement.home_featured.impressions + byPlacement.directory.impressions,
      ),
      contactActionsPerView: ratio(totals.contacts, totals.views),
      couponCopiesPerView: ratio(totals.couponCopies, totals.views),
    },
    byDay,
    byPlacement,
    dataQuality: {
      trustLevel: "client_reported_unverified",
      eligibleForBilling: false,
    },
    notice: "Interactions anonymes déclarées par les clients; aucun visiteur unique, aucune vente attribuée et aucune base de facturation.",
  };
}
