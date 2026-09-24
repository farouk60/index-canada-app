import wixData from "wix-data";
import { Permissions, webMethod } from "wix-web-module";

import { buildEngagementReport } from "backend/engagement-report";

const ENGAGEMENT_COLLECTION = "EngagementEvents";
const DATA_OPTIONS = Object.freeze({ suppressAuth: true, consistentRead: true });
const PAGE_SIZE = 1000;
export const MAX_SYNC_REPORT_EVENTS = 10_000;
const DAY_MS = 24 * 60 * 60 * 1000;

function reportQuery({ professionalId, fromDate, exclusiveEndDate }) {
  return wixData
    .query(ENGAGEMENT_COLLECTION)
    .eq("professionalId", professionalId)
    .ge("_createdDate", fromDate)
    .lt("_createdDate", exclusiveEndDate);
}

function reportLimitError() {
  const error = new Error(
    `REPORT_EVENT_LIMIT_EXCEEDED: réduisez la période (maximum ${MAX_SYNC_REPORT_EVENTS} événements).`,
  );
  error.code = "REPORT_EVENT_LIMIT_EXCEEDED";
  return error;
}

async function loadEvents({ professionalId, from, to }) {
  const emptyReport = buildEngagementReport([], { professionalId, from, to });
  const fromDate = new Date(`${emptyReport.period.from}T00:00:00.000Z`);
  const exclusiveEndDate = new Date(
    Date.parse(`${emptyReport.period.to}T00:00:00.000Z`) + DAY_MS,
  );

  const query = reportQuery({ professionalId, fromDate, exclusiveEndDate });
  const eventCount = await query.count(DATA_OPTIONS);
  if (eventCount > MAX_SYNC_REPORT_EVENTS) throw reportLimitError();

  let page = await query
    .ascending("_createdDate")
    .limit(PAGE_SIZE)
    .find(DATA_OPTIONS);

  const items = [];
  while (true) {
    if (items.length + page.items.length > MAX_SYNC_REPORT_EVENTS) {
      throw reportLimitError();
    }
    items.push(...page.items);
    if (!page.hasNext()) break;
    page = await page.next();
  }
  return items;
}

/** Rapport privé : Wix vérifie que l'appelant est propriétaire ou collaborateur. */
export const getEngagementReport = webMethod(
  Permissions.Admin,
  async ({ professionalId, from, to }) => {
    const items = await loadEvents({ professionalId, from, to });
    return buildEngagementReport(items, { professionalId, from, to });
  },
);
