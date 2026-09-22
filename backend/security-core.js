import {
  createHash,
  createHmac,
  timingSafeEqual,
} from "crypto";

export const PLAN_CATALOG = Object.freeze({
  basic: Object.freeze({
    id: "basic",
    amountCents: 0,
    currency: "cad",
    requiresPayment: false,
    durationDays: 365,
    labelFr: "Plan Basique",
    labelEn: "Basic Plan",
    capabilities: Object.freeze({
      profileImage: true,
      galleryMax: 0,
      coupon: false,
      featured: false,
    }),
    featuresFr: Object.freeze([
      "Profil professionnel",
      "Informations de contact",
      "Photo de profil",
      "Avis clients",
      "Visibilité standard",
    ]),
    featuresEn: Object.freeze([
      "Professional profile",
      "Contact information",
      "Profile photo",
      "Customer reviews",
      "Standard visibility",
    ]),
  }),
  premium: Object.freeze({
    id: "premium",
    amountCents: 4999,
    currency: "cad",
    requiresPayment: true,
    durationDays: 365,
    labelFr: "Plan Premium",
    labelEn: "Premium Plan",
    capabilities: Object.freeze({
      profileImage: true,
      galleryMax: 5,
      coupon: true,
      featured: false,
    }),
    featuresFr: Object.freeze([
      "Tout du plan Basique",
      "Galerie de 5 photos",
      "Résumé d'activité mis en avant",
      "Support prioritaire",
      "Coupons de réduction exclusifs",
    ]),
    featuresEn: Object.freeze([
      "Everything from Basic",
      "Gallery of 5 photos",
      "Featured business summary",
      "Priority support",
      "Exclusive discount coupons",
    ]),
  }),
  professional: Object.freeze({
    id: "professional",
    amountCents: 11999,
    currency: "cad",
    requiresPayment: true,
    durationDays: 365,
    labelFr: "Plan En Vedette",
    labelEn: "Featured Plan",
    capabilities: Object.freeze({
      profileImage: true,
      galleryMax: 5,
      coupon: true,
      featured: true,
    }),
    featuresFr: Object.freeze([
      "Tout du plan Premium",
      "Mise en avant sur la page d'accueil",
      "Priorité dans les résultats",
      "Support prioritaire",
      "Personnalisation avancée",
    ]),
    featuresEn: Object.freeze([
      "Everything from Premium",
      "Featured on the home page",
      "Priority in search results",
      "Priority support",
      "Advanced customization",
    ]),
  }),
});

export const FREE_TOKEN_PREFIX = "free_session_";
export const FREE_TOKEN_TTL_SECONDS = 30 * 60;
export const CHECKOUT_TTL_SECONDS = 24 * 60 * 60;
export const MAX_REQUEST_CHARS = 500_000;
export const MAX_PROFILE_IMAGE_CHARS = 100_000;
export const MAX_GALLERY_IMAGE_CHARS = 90_000;
export const MAX_TOTAL_IMAGE_CHARS = 420_000;
export const MAX_CHECKOUT_CHARS = 480_000;
export const MEDIA_STORAGE_VERSION = 1;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/u;
const CATEGORY_PATTERN = /^[\p{L}\p{N}_-]{1,80}$/u;
const TEMP_ID_PATTERN = /^temp_[A-Za-z0-9_-]{8,80}$/u;
const WIX_ID_PATTERN = /^[A-Za-z0-9_-]{1,100}$/u;
const PAYMENT_INTENT_PATTERN = /^pi_[A-Za-z0-9_]{10,80}$/u;
const BASE64_PATTERN = /^[A-Za-z0-9+/]*={0,2}$/u;
const WIX_IMAGE_URL_PATTERN = /^wix:image:\/\/v1\/[A-Za-z0-9][A-Za-z0-9._~-]{0,255}(?:\/[^#\s<>"']{1,512})?(?:#[A-Za-z0-9=&%._~-]{1,1024})?$/u;
const IMAGE_EXTENSION_BY_MIME = Object.freeze({
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
});

export class InputError extends Error {
  constructor(code = "INVALID_INPUT") {
    super(code);
    this.name = "InputError";
    this.code = code;
  }
}

function assertPlainObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError();
  }
  return value;
}

function cleanText(value, { required = false, min = 0, max, code = "INVALID_INPUT" }) {
  if (value === undefined || value === null) {
    if (required) throw new InputError(code);
    return "";
  }
  if (typeof value !== "string") throw new InputError(code);

  const cleaned = value
    .normalize("NFKC")
    .replace(/[\u0000-\u001F\u007F]/gu, " ")
    .replace(/[<>]/gu, "")
    .replace(/\s+/gu, " ")
    .trim();

  if ((required && cleaned.length < Math.max(1, min)) || cleaned.length > max) {
    throw new InputError(code);
  }
  return cleaned;
}

function normalizeEmail(value) {
  const email = cleanText(value, {
    required: true,
    min: 5,
    max: 254,
    code: "INVALID_REGISTRATION",
  }).toLowerCase();
  if (!EMAIL_PATTERN.test(email)) throw new InputError("INVALID_REGISTRATION");
  return email;
}

function normalizePhone(value) {
  const phone = cleanText(value, {
    required: true,
    min: 8,
    max: 25,
    code: "INVALID_REGISTRATION",
  });
  if (!/^[+()0-9 .-]+$/u.test(phone)) throw new InputError("INVALID_REGISTRATION");
  const digits = phone.replace(/\D/gu, "");
  if (digits.length < 8 || digits.length > 15) {
    throw new InputError("INVALID_REGISTRATION");
  }
  return phone;
}

function normalizeUrl(value) {
  const raw = cleanText(value, { max: 2048, code: "INVALID_REGISTRATION" });
  if (!raw) return "";
  const candidate = /^[a-z][a-z0-9+.-]*:/iu.test(raw) ? raw : `https://${raw}`;
  let parsed;
  try {
    parsed = new URL(candidate);
  } catch (_error) {
    throw new InputError("INVALID_REGISTRATION");
  }
  if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname) {
    throw new InputError("INVALID_REGISTRATION");
  }
  return parsed.toString();
}

function firstDefined(sources, fieldNames) {
  for (const source of sources) {
    if (!source || typeof source !== "object" || Array.isArray(source)) continue;
    for (const fieldName of fieldNames) {
      if (source[fieldName] !== undefined && source[fieldName] !== null) {
        return source[fieldName];
      }
    }
  }
  return undefined;
}

export function normalizeRegistrationInput(rawBody) {
  const body = assertPlainObject(rawBody);
  const metadata = body.metadata && typeof body.metadata === "object" && !Array.isArray(body.metadata)
    ? body.metadata
    : {};
  const registrationData = body.registrationData
    && typeof body.registrationData === "object"
    && !Array.isArray(body.registrationData)
    ? body.registrationData
    : {};
  const sources = [body, metadata, registrationData];

  const sourceRegistrationId = cleanText(
    firstDefined(sources, ["professionalId", "sourceRegistrationId"]),
    { required: true, min: 13, max: 85, code: "INVALID_REGISTRATION_ID" },
  );
  if (!TEMP_ID_PATTERN.test(sourceRegistrationId)) {
    throw new InputError("EXISTING_PROFILE_NOT_ALLOWED");
  }

  const categoryId = cleanText(firstDefined(sources, ["categoryId", "category"]), {
    required: true,
    min: 1,
    max: 80,
    code: "INVALID_REGISTRATION",
  });
  if (!CATEGORY_PATTERN.test(categoryId)) throw new InputError("INVALID_REGISTRATION");

  return Object.freeze({
    sourceRegistrationId,
    email: normalizeEmail(firstDefined(sources, ["email"])),
    businessName: cleanText(firstDefined(sources, ["businessName"]), {
      required: true,
      min: 2,
      max: 120,
      code: "INVALID_REGISTRATION",
    }),
    categoryId,
    ville: cleanText(firstDefined(sources, ["ville", "city"]), {
      required: true,
      min: 2,
      max: 120,
      code: "INVALID_REGISTRATION",
    }),
    phone: normalizePhone(firstDefined(sources, ["phone"])),
    address: cleanText(firstDefined(sources, ["address"]), {
      required: true,
      min: 3,
      max: 250,
      code: "INVALID_REGISTRATION",
    }),
    description: cleanText(firstDefined(sources, ["description", "businessSummary"]), {
      max: 1000,
      code: "INVALID_REGISTRATION",
    }),
    website: normalizeUrl(firstDefined(sources, ["website"])),
    facebook: normalizeUrl(firstDefined(sources, ["facebook"])),
    instagram: normalizeUrl(firstDefined(sources, ["instagram"])),
    linkedin: normalizeUrl(firstDefined(sources, ["linkedin"])),
    tiktok: normalizeUrl(firstDefined(sources, ["tiktok"])),
    youtube: normalizeUrl(firstDefined(sources, ["youtube"])),
    whatsapp: normalizeUrl(firstDefined(sources, ["whatsapp"])),
  });
}

export function getPlan(planId) {
  if (typeof planId !== "string" || !Object.prototype.hasOwnProperty.call(PLAN_CATALOG, planId)) {
    throw new InputError("INVALID_PLAN");
  }
  return PLAN_CATALOG[planId];
}

export function projectPaymentPlans() {
  return Object.values(PLAN_CATALOG).map((plan) => Object.freeze({
    id: plan.id,
    amount: plan.amountCents,
    currency: plan.currency,
    requires_payment: plan.requiresPayment,
    duration_days: plan.durationDays,
    label: Object.freeze({ fr: plan.labelFr, en: plan.labelEn }),
    capabilities: Object.freeze({
      profile_image: plan.capabilities.profileImage,
      gallery_max: plan.capabilities.galleryMax,
      coupon: plan.capabilities.coupon,
      featured: plan.capabilities.featured,
    }),
    features: Object.freeze({
      fr: Object.freeze([...plan.featuresFr]),
      en: Object.freeze([...plan.featuresEn]),
    }),
  }));
}

export function sha256(value) {
  return createHash("sha256").update(String(value), "utf8").digest("hex");
}

export function registrationFingerprint(registration) {
  const normalized = normalizeRegistrationInput(registration);
  return sha256(JSON.stringify(normalized));
}

export function normalizeCouponInput(rawBody, nowMs = Date.now()) {
  const body = assertPlainObject(rawBody);
  const registrationData = body.registrationData
    && typeof body.registrationData === "object"
    && !Array.isArray(body.registrationData)
    ? body.registrationData
    : {};
  const sources = [body, registrationData];
  const raw = {
    title: firstDefined(sources, ["couponTitle"]),
    titleEn: firstDefined(sources, ["couponTitleEn", "couponTitleEN"]),
    code: firstDefined(sources, ["couponCode"]),
    description: firstDefined(sources, ["couponDescription"]),
    descriptionEn: firstDefined(sources, ["couponDescriptionEn", "couponDescriptionEN"]),
    expirationDate: firstDefined(sources, ["couponExpirationDate"]),
  };
  const hasCoupon = Object.values(raw).some((value) => value !== undefined && value !== null && value !== "");
  if (!hasCoupon) return null;

  const code = cleanText(raw.code, {
    required: true,
    min: 3,
    max: 32,
    code: "INVALID_COUPON",
  }).toUpperCase();
  if (!/^[A-Z0-9_-]{3,32}$/u.test(code)) throw new InputError("INVALID_COUPON");

  let expirationDate = "";
  if (raw.expirationDate !== undefined && raw.expirationDate !== null && raw.expirationDate !== "") {
    const value = cleanText(raw.expirationDate, {
      required: true,
      min: 10,
      max: 40,
      code: "INVALID_COUPON",
    });
    if (!/^\d{4}-\d{2}-\d{2}(?:T.*Z)?$/u.test(value)) throw new InputError("INVALID_COUPON");
    const timestamp = Date.parse(value);
    if (!Number.isFinite(timestamp) || timestamp <= nowMs || timestamp > nowMs + 5 * 366 * 24 * 60 * 60 * 1000) {
      throw new InputError("INVALID_COUPON");
    }
    expirationDate = new Date(timestamp).toISOString();
  }

  return Object.freeze({
    title: cleanText(raw.title, {
      required: true,
      min: 2,
      max: 120,
      code: "INVALID_COUPON",
    }),
    titleEn: cleanText(raw.titleEn, { max: 120, code: "INVALID_COUPON" }),
    code,
    description: cleanText(raw.description, {
      required: true,
      min: 5,
      max: 500,
      code: "INVALID_COUPON",
    }),
    descriptionEn: cleanText(raw.descriptionEn, { max: 500, code: "INVALID_COUPON" }),
    expirationDate,
  });
}

export function validatePlanCapabilities(plan, images, coupon) {
  if (!plan || !plan.capabilities || !images || !Array.isArray(images.gallery)) {
    throw new InputError("INVALID_CHECKOUT");
  }
  if (images.profile && !plan.capabilities.profileImage) {
    throw new InputError("PLAN_CAPABILITY_VIOLATION");
  }
  if (images.gallery.length > plan.capabilities.galleryMax) {
    throw new InputError("PLAN_CAPABILITY_VIOLATION");
  }
  if (coupon && !plan.capabilities.coupon) {
    throw new InputError("PLAN_CAPABILITY_VIOLATION");
  }
  return true;
}

function normalizeImageHashManifest(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError("INVALID_CHECKOUT");
  }
  const profile = value.profile ?? "";
  const gallery = value.gallery;
  if (
    typeof profile !== "string"
    || (profile && !/^[a-f0-9]{64}$/u.test(profile))
    || !Array.isArray(gallery)
    || gallery.some((hash) => typeof hash !== "string" || !/^[a-f0-9]{64}$/u.test(hash))
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  return Object.freeze({ profile, gallery: Object.freeze([...gallery]) });
}

function buildImageHashManifest(images) {
  if (
    !images
    || typeof images !== "object"
    || Array.isArray(images)
    || typeof images.profile !== "string"
    || !Array.isArray(images.gallery)
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  const profile = images.profile
    ? createHash("sha256")
      .update(decodeStoredImage(images.profile, MAX_PROFILE_IMAGE_CHARS).buffer)
      .digest("hex")
    : "";
  const gallery = images.gallery.map((image) => createHash("sha256")
    .update(decodeStoredImage(image, MAX_GALLERY_IMAGE_CHARS).buffer)
    .digest("hex"));
  return Object.freeze({ profile, gallery: Object.freeze(gallery) });
}

export function checkoutFingerprint({
  plan,
  registration,
  images,
  imageHashes,
  coupon,
}) {
  const normalizedRegistration = normalizeRegistrationInput(registration);
  const hashes = imageHashes
    ? normalizeImageHashManifest(imageHashes)
    : buildImageHashManifest(images);
  return sha256(JSON.stringify({
    version: 2,
    mediaStorageVersion: MEDIA_STORAGE_VERSION,
    planId: plan.id,
    registration: normalizedRegistration,
    coupon: coupon ?? null,
    profileImageHash: hashes.profile,
    galleryImageHashes: hashes.gallery,
  }));
}

export function buildCheckoutId(reference) {
  return `chk_${sha256(reference).slice(0, 32)}`;
}

export function createCheckoutDraft(rawBody, nowMs = Date.now()) {
  validateRequestSize(rawBody);
  const plan = getPlan(rawBody.planId);
  const registration = normalizeRegistrationInput(rawBody);
  const images = normalizeImages(rawBody);
  const coupon = normalizeCouponInput(rawBody, nowMs);
  validatePlanCapabilities(plan, images, coupon);
  const imageHashes = buildImageHashManifest(images);
  const fingerprint = checkoutFingerprint({
    plan,
    registration,
    imageHashes,
    coupon,
  });
  const checkoutId = buildCheckoutId(
    `${plan.id}:${registration.sourceRegistrationId}:${fingerprint}`,
  );
  const draft = {
    _id: checkoutId,
    version: 2,
    mediaStorageVersion: MEDIA_STORAGE_VERSION,
    status: "created",
    planId: plan.id,
    amountCents: plan.amountCents,
    currency: plan.currency,
    fingerprint,
    sourceRegistrationId: registration.sourceRegistrationId,
    registration,
    images: Object.freeze({ profile: images.profile, gallery: Object.freeze([...images.gallery]) }),
    imageHashes,
    coupon,
    paymentIntentId: "",
    professionalId: "",
    paymentAttempt: 0,
    createdAt: new Date(nowMs).toISOString(),
    expiresAt: new Date(nowMs + CHECKOUT_TTL_SECONDS * 1000).toISOString(),
  };
  if (JSON.stringify(draft).length > MAX_CHECKOUT_CHARS) {
    throw new InputError("PAYLOAD_TOO_LARGE");
  }
  return Object.freeze(draft);
}

export function assertCheckoutNotExpired(checkout, nowMs = Date.now()) {
  const storedCheckout = assertPlainObject(checkout);
  if (!Number.isFinite(nowMs) || typeof storedCheckout.expiresAt !== "string") {
    throw new InputError("INVALID_CHECKOUT");
  }
  const expiresAtMs = Date.parse(storedCheckout.expiresAt);
  if (!Number.isFinite(expiresAtMs)) throw new InputError("INVALID_CHECKOUT");
  if (expiresAtMs <= nowMs) throw new InputError("CHECKOUT_EXPIRED");
  return true;
}

export function evaluateRateLimit(previous, nowMs, { limit, windowMs }) {
  if (!Number.isInteger(limit) || limit < 1 || !Number.isInteger(windowMs) || windowMs < 1000) {
    throw new Error("INVALID_RATE_LIMIT_CONFIG");
  }
  const hasActiveWindow = previous
    && Number.isFinite(Number(previous.windowStartedAtMs))
    && nowMs >= Number(previous.windowStartedAtMs)
    && nowMs < Number(previous.windowStartedAtMs) + windowMs;
  const windowStartedAtMs = hasActiveWindow ? Number(previous.windowStartedAtMs) : nowMs;
  const count = hasActiveWindow ? Number(previous.count ?? 0) + 1 : 1;
  const retryAfterSeconds = Math.max(
    0,
    Math.ceil((windowStartedAtMs + windowMs - nowMs) / 1000),
  );
  return Object.freeze({
    allowed: count <= limit,
    count,
    limit,
    windowStartedAtMs,
    expiresAt: new Date(windowStartedAtMs + windowMs).toISOString(),
    retryAfterSeconds,
  });
}

export function validatePaymentIntentBinding(paymentIntent, checkout) {
  if (!paymentIntent || typeof paymentIntent !== "object" || !checkout || typeof checkout !== "object") {
    throw new InputError("UNTRUSTED_PAYMENT_INTENT");
  }
  const plan = getPlan(checkout.planId);
  const metadata = paymentIntent.metadata ?? {};
  if (
    !plan.requiresPayment
    || typeof paymentIntent.id !== "string"
    || !PAYMENT_INTENT_PATTERN.test(paymentIntent.id)
    || (checkout.paymentIntentId && checkout.paymentIntentId !== paymentIntent.id)
    || metadata.checkoutVersion !== "2"
    || metadata.checkoutId !== checkout._id
    || metadata.checkoutFingerprint !== checkout.fingerprint
    || metadata.planId !== plan.id
    || metadata.expectedAmountCents !== String(plan.amountCents)
    || metadata.currency !== plan.currency
    || paymentIntent.currency?.toLowerCase() !== plan.currency
    || paymentIntent.amount !== plan.amountCents
  ) {
    throw new InputError("UNTRUSTED_PAYMENT_INTENT");
  }
  return plan;
}

export function validatePaymentIntentForCheckout(paymentIntent, checkout) {
  const plan = validatePaymentIntentBinding(paymentIntent, checkout);
  if (
    paymentIntent.status !== "succeeded"
    || paymentIntent.amount_received !== plan.amountCents
  ) {
    throw new InputError("UNTRUSTED_PAYMENT_INTENT");
  }
  return plan;
}

export function classifyPaymentIntentWebhook(paymentIntent) {
  if (!paymentIntent || typeof paymentIntent !== "object" || Array.isArray(paymentIntent)) {
    throw new InputError("UNTRUSTED_PAYMENT_INTENT");
  }
  const metadata = paymentIntent.metadata;
  if (metadata !== undefined && (!metadata || typeof metadata !== "object" || Array.isArray(metadata))) {
    throw new InputError("UNTRUSTED_PAYMENT_INTENT");
  }
  const normalizedMetadata = metadata ?? {};
  const bindingFields = [
    "checkoutVersion",
    "checkoutId",
    "checkoutFingerprint",
    "planId",
    "expectedAmountCents",
    "currency",
  ];
  const hasIndexCanadaBinding = bindingFields.some((field) => (
    Object.prototype.hasOwnProperty.call(normalizedMetadata, field)
  ));
  if (normalizedMetadata.checkoutVersion === "2") return "linked";
  if (hasIndexCanadaBinding) throw new InputError("UNTRUSTED_PAYMENT_INTENT");
  return "foreign";
}

function encodeBase64Url(value) {
  return Buffer.from(value, "utf8")
    .toString("base64")
    .replace(/=/gu, "")
    .replace(/\+/gu, "-")
    .replace(/\//gu, "_");
}

function decodeBase64Url(value) {
  if (!/^[A-Za-z0-9_-]+$/u.test(value)) throw new InputError("INVALID_CONFIRMATION_TOKEN");
  const normalized = value.replace(/-/gu, "+").replace(/_/gu, "/");
  const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(`${normalized}${padding}`, "base64");
}

function assertSigningSecret(secret) {
  if (typeof secret !== "string" || Buffer.byteLength(secret, "utf8") < 32) {
    throw new Error("CHECKOUT_SIGNING_SECRET_INVALID");
  }
}

function sign(encodedPayload, secret) {
  return createHmac("sha256", secret)
    .update(encodedPayload, "utf8")
    .digest("base64")
    .replace(/=/gu, "")
    .replace(/\+/gu, "-")
    .replace(/\//gu, "_");
}

function signaturesMatch(expectedSignature, suppliedSignature) {
  if (
    typeof suppliedSignature !== "string"
    || !/^[A-Za-z0-9_-]+$/u.test(suppliedSignature)
    || suppliedSignature.length !== expectedSignature.length
  ) {
    return false;
  }

  // Compare the canonical base64url representation. Comparing only decoded
  // bytes would also accept non-canonical variants of the final character.
  const expected = Buffer.from(expectedSignature, "utf8");
  const supplied = Buffer.from(suppliedSignature, "utf8");
  return timingSafeEqual(expected, supplied);
}

export function createFreeConfirmationToken(registration, secret, nowMs = Date.now()) {
  assertSigningSecret(secret);
  const normalized = normalizeRegistrationInput(registration);
  const issuedAt = Math.floor(nowMs / 1000);
  const fingerprint = sha256(JSON.stringify(normalized));
  const payload = {
    v: 1,
    planId: "basic",
    sid: normalized.sourceRegistrationId,
    fp: fingerprint,
    jti: sha256(`free:${normalized.sourceRegistrationId}:${fingerprint}`).slice(0, 32),
    iat: issuedAt,
    exp: issuedAt + FREE_TOKEN_TTL_SECONDS,
  };
  const encodedPayload = encodeBase64Url(JSON.stringify(payload));
  const signature = sign(encodedPayload, secret);

  return Object.freeze({
    token: `${FREE_TOKEN_PREFIX}${encodedPayload}.${signature}`,
    expiresAt: new Date(payload.exp * 1000).toISOString(),
    payload: Object.freeze(payload),
  });
}

export function verifyFreeConfirmationToken(token, registration, secret, nowMs = Date.now()) {
  assertSigningSecret(secret);
  if (typeof token !== "string" || token.length > 1000 || !token.startsWith(FREE_TOKEN_PREFIX)) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }
  const compact = token.slice(FREE_TOKEN_PREFIX.length);
  const parts = compact.split(".");
  if (parts.length !== 2 || !signaturesMatch(sign(parts[0], secret), parts[1])) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }

  let payload;
  try {
    payload = JSON.parse(decodeBase64Url(parts[0]).toString("utf8"));
  } catch (_error) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }

  const nowSeconds = Math.floor(nowMs / 1000);
  if (
    !payload
    || payload.v !== 1
    || payload.planId !== "basic"
    || typeof payload.iat !== "number"
    || typeof payload.exp !== "number"
    || payload.iat > nowSeconds + 60
    || payload.exp <= nowSeconds
    || payload.exp - payload.iat !== FREE_TOKEN_TTL_SECONDS
    || typeof payload.jti !== "string"
    || !/^[a-f0-9]{32}$/u.test(payload.jti)
  ) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }

  const normalized = normalizeRegistrationInput(registration);
  const fingerprint = sha256(JSON.stringify(normalized));
  if (payload.sid !== normalized.sourceRegistrationId || payload.fp !== fingerprint) {
    throw new InputError("REGISTRATION_MISMATCH");
  }
  return Object.freeze(payload);
}

export function createFreeCheckoutToken(checkout, secret, nowMs = Date.now()) {
  assertSigningSecret(secret);
  if (
    !checkout
    || checkout.version !== 2
    || checkout.planId !== "basic"
    || !/^chk_[a-f0-9]{32}$/u.test(checkout._id)
    || !/^[a-f0-9]{64}$/u.test(checkout.fingerprint)
    || !TEMP_ID_PATTERN.test(checkout.sourceRegistrationId)
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  const issuedAt = Math.floor(nowMs / 1000);
  const payload = {
    v: 2,
    planId: "basic",
    checkoutId: checkout._id,
    sid: checkout.sourceRegistrationId,
    fp: checkout.fingerprint,
    jti: sha256(`free-checkout:${checkout._id}:${checkout.fingerprint}`).slice(0, 32),
    iat: issuedAt,
    exp: issuedAt + FREE_TOKEN_TTL_SECONDS,
  };
  const encodedPayload = encodeBase64Url(JSON.stringify(payload));
  return Object.freeze({
    token: `${FREE_TOKEN_PREFIX}${encodedPayload}.${sign(encodedPayload, secret)}`,
    expiresAt: new Date(payload.exp * 1000).toISOString(),
    payload: Object.freeze(payload),
  });
}

export function verifyFreeCheckoutToken(token, secret, nowMs = Date.now()) {
  assertSigningSecret(secret);
  if (typeof token !== "string" || token.length > 1200 || !token.startsWith(FREE_TOKEN_PREFIX)) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }
  const parts = token.slice(FREE_TOKEN_PREFIX.length).split(".");
  if (parts.length !== 2 || !signaturesMatch(sign(parts[0], secret), parts[1])) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }
  let payload;
  try {
    payload = JSON.parse(decodeBase64Url(parts[0]).toString("utf8"));
  } catch (_error) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }
  const nowSeconds = Math.floor(nowMs / 1000);
  if (
    !payload
    || payload.v !== 2
    || payload.planId !== "basic"
    || !/^chk_[a-f0-9]{32}$/u.test(payload.checkoutId)
    || !TEMP_ID_PATTERN.test(payload.sid)
    || !/^[a-f0-9]{64}$/u.test(payload.fp)
    || !/^[a-f0-9]{32}$/u.test(payload.jti)
    || typeof payload.iat !== "number"
    || typeof payload.exp !== "number"
    || payload.iat > nowSeconds + 60
    || payload.exp <= nowSeconds
    || payload.exp - payload.iat !== FREE_TOKEN_TTL_SECONDS
  ) {
    throw new InputError("INVALID_CONFIRMATION_TOKEN");
  }
  return Object.freeze(payload);
}

export function classifyConfirmationReference(value) {
  if (typeof value !== "string" || !value) throw new InputError("INVALID_PAYMENT_REFERENCE");
  if (value.startsWith("free_plan_")) throw new InputError("LEGACY_FREE_TOKEN_DISABLED");
  if (value.startsWith(FREE_TOKEN_PREFIX)) return "free";
  if (PAYMENT_INTENT_PATTERN.test(value)) return "stripe";
  throw new InputError("INVALID_PAYMENT_REFERENCE");
}

export function validateRequestSize(body) {
  if (JSON.stringify(assertPlainObject(body)).length > MAX_REQUEST_CHARS) {
    throw new InputError("PAYLOAD_TOO_LARGE");
  }
}

function detectImageMime(buffer) {
  if (buffer.length >= 8 && buffer.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    return "image/png";
  }
  if (buffer.length >= 3 && buffer[0] === 255 && buffer[1] === 216 && buffer[2] === 255) {
    return "image/jpeg";
  }
  if (
    buffer.length >= 12
    && buffer.subarray(0, 4).toString("ascii") === "RIFF"
    && buffer.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return "image/webp";
  }
  throw new InputError("INVALID_IMAGE");
}

export function normalizeImageDataUrl(value, maxChars) {
  if (value === undefined || value === null || value === "") return "";
  if (typeof value !== "string" || !value.trim()) throw new InputError("INVALID_IMAGE");
  let encoded = value.trim();
  const dataUrlMatch = encoded.match(/^data:image\/(png|jpe?g|webp);base64,(.+)$/isu);
  if (dataUrlMatch) encoded = dataUrlMatch[2];
  encoded = encoded.replace(/\s/gu, "");
  if (encoded.length < 16 || encoded.length > maxChars || encoded.length % 4 === 1 || !BASE64_PATTERN.test(encoded)) {
    throw new InputError("INVALID_IMAGE");
  }

  const buffer = Buffer.from(encoded, "base64");
  if (buffer.length < 32) throw new InputError("INVALID_IMAGE");
  const mime = detectImageMime(buffer);
  return `data:${mime};base64,${buffer.toString("base64")}`;
}

export function normalizeImages(rawBody) {
  const body = assertPlainObject(rawBody);
  const registrationData = body.registrationData
    && typeof body.registrationData === "object"
    && !Array.isArray(body.registrationData)
    ? body.registrationData
    : {};
  const profileRaw = body.profileImageBase64 ?? registrationData.profileImageBase64;
  const galleryRaw = body.galleryImagesBase64 ?? registrationData.galleryImagesBase64 ?? [];
  if (!Array.isArray(galleryRaw) || galleryRaw.length > 5) throw new InputError("INVALID_IMAGE");

  const profile = normalizeImageDataUrl(profileRaw, MAX_PROFILE_IMAGE_CHARS);
  const gallery = galleryRaw.map((image) => normalizeImageDataUrl(image, MAX_GALLERY_IMAGE_CHARS));
  if (gallery.some((image) => !image)) throw new InputError("INVALID_IMAGE");
  const totalChars = profile.length + gallery.reduce((sum, image) => sum + image.length, 0);
  if (totalChars > MAX_TOTAL_IMAGE_CHARS) throw new InputError("PAYLOAD_TOO_LARGE");
  return Object.freeze({ profile, gallery: Object.freeze(gallery) });
}

function decodeStoredImage(value, maxChars) {
  const normalized = normalizeImageDataUrl(value, maxChars);
  if (!normalized || normalized !== value) throw new InputError("INVALID_CHECKOUT");
  const separator = normalized.indexOf(",");
  const mimeType = normalized.slice(5, normalized.indexOf(";", 5));
  const buffer = Buffer.from(normalized.slice(separator + 1), "base64");
  if (detectImageMime(buffer) !== mimeType || !IMAGE_EXTENSION_BY_MIME[mimeType]) {
    throw new InputError("INVALID_CHECKOUT");
  }
  return { buffer, mimeType };
}

function buildMediaUploadDescriptor({
  checkoutId,
  professionalId,
  kind,
  index,
  value,
  maxChars,
}) {
  const { buffer, mimeType } = decodeStoredImage(value, maxChars);
  const digest = createHash("sha256").update(buffer).digest("hex");
  const extension = IMAGE_EXTENSION_BY_MIME[mimeType];
  const prefix = kind === "profile"
    ? "profile"
    : `gallery-${String(index + 1).padStart(2, "0")}`;
  return Object.freeze({
    checkoutId,
    professionalId,
    kind,
    index,
    path: `/index-canada/professionals/${professionalId}`,
    fileName: `${prefix}-${digest.slice(0, 24)}.${extension}`,
    mimeType,
    buffer,
  });
}

function imageHashManifestsEqual(left, right) {
  return left.profile === right.profile
    && left.gallery.length === right.gallery.length
    && left.gallery.every((hash, index) => hash === right.gallery[index]);
}

function validateTransientCheckout(checkout) {
  const transientCheckout = assertPlainObject(checkout);
  if (
    transientCheckout.version !== 2
    || transientCheckout.mediaStorageVersion !== MEDIA_STORAGE_VERSION
    || typeof transientCheckout._id !== "string"
    || !/^chk_[a-f0-9]{32}$/u.test(transientCheckout._id)
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  const plan = getPlan(transientCheckout.planId);
  const registration = normalizeRegistrationInput(transientCheckout.registration);
  const images = transientCheckout.images;
  if (
    !images
    || typeof images !== "object"
    || Array.isArray(images)
    || typeof images.profile !== "string"
    || !Array.isArray(images.gallery)
    || images.gallery.some((image) => typeof image !== "string" || !image)
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  validatePlanCapabilities(plan, images, transientCheckout.coupon ?? null);
  const computedHashes = buildImageHashManifest(images);
  const storedHashes = normalizeImageHashManifest(transientCheckout.imageHashes);
  const fingerprint = checkoutFingerprint({
    plan,
    registration,
    imageHashes: storedHashes,
    coupon: transientCheckout.coupon ?? null,
  });
  if (
    !imageHashManifestsEqual(computedHashes, storedHashes)
    || transientCheckout.fingerprint !== fingerprint
    || transientCheckout.amountCents !== plan.amountCents
    || transientCheckout.currency !== plan.currency
    || transientCheckout.sourceRegistrationId !== registration.sourceRegistrationId
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  return { plan, registration, images, imageHashes: storedHashes };
}

/**
 * Produit un plan d'envoi déterministe à partir des images déjà validées du
 * checkout. Aucun contenu binaire ni URL de retour Wix n'est persisté ici.
 */
export function buildMediaUploadPlan(checkout) {
  const transientCheckout = assertPlainObject(checkout);
  const { images } = validateTransientCheckout(transientCheckout);

  const professionalId = buildProfessionalId(`checkout:${transientCheckout._id}`);
  const uploads = [];
  if (images.profile) {
    uploads.push(buildMediaUploadDescriptor({
      checkoutId: transientCheckout._id,
      professionalId,
      kind: "profile",
      index: 0,
      value: images.profile,
      maxChars: MAX_PROFILE_IMAGE_CHARS,
    }));
  }
  images.gallery.forEach((value, index) => {
    uploads.push(buildMediaUploadDescriptor({
      checkoutId: transientCheckout._id,
      professionalId,
      kind: "gallery",
      index,
      value,
      maxChars: MAX_GALLERY_IMAGE_CHARS,
    }));
  });
  return Object.freeze({
    professionalId,
    path: `/index-canada/professionals/${professionalId}`,
    uploads: Object.freeze(uploads),
  });
}

export function normalizeWixImageUrl(value) {
  if (typeof value !== "string") throw new InputError("INVALID_MEDIA_REFERENCE");
  const normalized = value.trim();
  if (
    normalized !== value
    || normalized.length > 2048
    || !WIX_IMAGE_URL_PATTERN.test(normalized)
  ) {
    throw new InputError("INVALID_MEDIA_REFERENCE");
  }
  return normalized;
}

export function selectOrphanedMediaUrls(uploadedUrls, protectedUrls = []) {
  if (!Array.isArray(uploadedUrls) || !Array.isArray(protectedUrls)) {
    throw new InputError("INVALID_MEDIA_REFERENCE");
  }
  const protectedSet = new Set(protectedUrls.map(normalizeWixImageUrl));
  const candidates = uploadedUrls.map(normalizeWixImageUrl);
  return Object.freeze(
    [...new Set(candidates)].filter((url) => !protectedSet.has(url)),
  );
}

function normalizeUploadedImageReferences(expectedImages, uploadedImages) {
  if (!uploadedImages || typeof uploadedImages !== "object" || Array.isArray(uploadedImages)) {
    throw new InputError("INVALID_MEDIA_REFERENCE");
  }
  const rawProfile = uploadedImages.profile ?? "";
  const rawGallery = uploadedImages.gallery ?? [];
  if (
    typeof rawProfile !== "string"
    || !Array.isArray(rawGallery)
    || Boolean(expectedImages.profile) !== Boolean(rawProfile)
    || rawGallery.length !== expectedImages.gallery.length
  ) {
    throw new InputError("INVALID_MEDIA_REFERENCE");
  }
  const profile = rawProfile ? normalizeWixImageUrl(rawProfile) : "";
  const gallery = rawGallery.map(normalizeWixImageUrl);
  return Object.freeze({ profile, gallery: Object.freeze(gallery) });
}

export function buildPersistedCheckoutDraft(checkout, uploadedImages) {
  const transientCheckout = assertPlainObject(checkout);
  const { imageHashes } = validateTransientCheckout(transientCheckout);
  const media = normalizeUploadedImageReferences(imageHashes, uploadedImages);
  const persisted = {
    ...transientCheckout,
    images: media,
    imageHashes,
  };
  validatePersistedCheckout(persisted);
  if (JSON.stringify(persisted).length > MAX_CHECKOUT_CHARS) {
    throw new InputError("PAYLOAD_TOO_LARGE");
  }
  return Object.freeze(persisted);
}

export function validatePersistedCheckout(checkout) {
  const storedCheckout = assertPlainObject(checkout);
  if (
    storedCheckout.version !== 2
    || storedCheckout.mediaStorageVersion !== MEDIA_STORAGE_VERSION
    || typeof storedCheckout._id !== "string"
    || !/^chk_[a-f0-9]{32}$/u.test(storedCheckout._id)
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  const plan = getPlan(storedCheckout.planId);
  const registration = normalizeRegistrationInput(storedCheckout.registration);
  const imageHashes = normalizeImageHashManifest(storedCheckout.imageHashes);
  const media = normalizeUploadedImageReferences(imageHashes, storedCheckout.images);
  validatePlanCapabilities(plan, media, storedCheckout.coupon ?? null);
  const fingerprint = checkoutFingerprint({
    plan,
    registration,
    imageHashes,
    coupon: storedCheckout.coupon ?? null,
  });
  if (
    storedCheckout.fingerprint !== fingerprint
    || storedCheckout.amountCents !== plan.amountCents
    || storedCheckout.currency !== plan.currency
    || storedCheckout.sourceRegistrationId !== registration.sourceRegistrationId
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  return plan;
}

export function buildProfessionalId(reference) {
  return `idx_${sha256(reference).slice(0, 32)}`;
}

export function buildProfessionalRecord(
  checkout,
  paymentId,
  nowMs = Date.now(),
) {
  const storedCheckout = assertPlainObject(checkout);
  const plan = validatePersistedCheckout(storedCheckout);
  const registration = normalizeRegistrationInput(storedCheckout.registration);
  const media = normalizeUploadedImageReferences(
    storedCheckout.imageHashes,
    storedCheckout.images,
  );
  if (
    typeof storedCheckout._id !== "string"
    || !/^chk_[a-f0-9]{32}$/u.test(storedCheckout._id)
    || typeof paymentId !== "string"
    || paymentId.length > 120
    || (plan.requiresPayment && !PAYMENT_INTENT_PATTERN.test(paymentId))
    || (!plan.requiresPayment && paymentId !== `free:${storedCheckout._id}`)
  ) {
    throw new InputError("INVALID_CHECKOUT");
  }
  const now = new Date(nowMs);
  if (!Number.isFinite(now.getTime())) throw new InputError("INVALID_CHECKOUT");
  const expiryDate = new Date(now.getTime() + plan.durationDays * 24 * 60 * 60 * 1000);
  const record = {
    _id: buildProfessionalId(`checkout:${storedCheckout._id}`),
    checkoutId: storedCheckout._id,
    title: registration.businessName,
    email: registration.email,
    plan: plan.id,
    isActive: false,
    paymentId,
    paymentStatus: plan.requiresPayment ? "paid" : "not_required",
    registrationStatus: "pending_review",
    amountPaid: plan.amountCents / 100,
    paymentCurrency: plan.currency,
    expiryDate: expiryDate.toISOString(),
    createdAt: now.toISOString(),
    subtitle: registration.description,
    ville: registration.ville,
    address: registration.address,
    numroDeTlphone: registration.phone,
    siteWeb: registration.website,
    lienFacebook: registration.facebook,
    lienInstagram: registration.instagram,
    linkedin: registration.linkedin,
    lienTiktok: registration.tiktok,
    lienYoutube: registration.youtube,
    lienWhatsapp: registration.whatsapp,
    sponsor: plan.capabilities.featured,
    sousCatgorie: registration.categoryId,
    image: media.profile,
    registrationFingerprint: storedCheckout.fingerprint,
    sourceRegistrationId: storedCheckout.sourceRegistrationId,
  };
  media.gallery.forEach((image, index) => {
    record[`galerieImage${index + 1}`] = image;
  });
  if (storedCheckout.coupon && plan.capabilities.coupon) {
    record.couponTitle = storedCheckout.coupon.title;
    record.couponTitleEn = storedCheckout.coupon.titleEn;
    record.couponCode = storedCheckout.coupon.code;
    record.couponDescription = storedCheckout.coupon.description;
    record.couponDescriptionEn = storedCheckout.coupon.descriptionEn;
    if (storedCheckout.coupon.expirationDate) {
      record.couponExpirationDate = storedCheckout.coupon.expirationDate;
    }
  }
  return Object.freeze(record);
}

export function normalizeSearchParams(query = {}) {
  const search = cleanText(query.search, { max: 100, code: "INVALID_SEARCH" });
  const category = cleanText(query.category, { max: 80, code: "INVALID_SEARCH" });
  const city = cleanText(query.city, { max: 100, code: "INVALID_SEARCH" });
  let limit = 100;
  if (query.limit !== undefined && query.limit !== null && query.limit !== "") {
    const rawLimit = String(query.limit);
    if (!/^\d{1,3}$/u.test(rawLimit)) throw new InputError("INVALID_SEARCH");
    limit = Number.parseInt(rawLimit, 10);
    if (limit < 1 || limit > 100) throw new InputError("INVALID_SEARCH");
  }
  return Object.freeze({ search, category, city, limit });
}

export function directorySearchText(value) {
  if (typeof value === "string") return value;
  if (!value || typeof value !== "object" || Array.isArray(value)) return "";
  return [
    value._id,
    value.formatted,
    value.formattedAddress,
    value.city,
    value.streetAddress?.formattedAddressLine,
  ].filter((part) => typeof part === "string").join(" ");
}

export function normalizeFeaturedFilter(value) {
  if (value === undefined || value === null || value === "") return null;
  if (value === true || value === "true" || value === "1") return true;
  if (value === false || value === "false" || value === "0") return false;
  throw new InputError("INVALID_SEARCH");
}

export function normalizeProfessionalIdFilter(value) {
  const professionalId = cleanText(value, {
    required: true,
    min: 1,
    max: 100,
    code: "INVALID_SEARCH",
  });
  if (!WIX_ID_PATTERN.test(professionalId)) throw new InputError("INVALID_SEARCH");
  return professionalId;
}

export function normalizeProfessionalIdsFilter(value) {
  if (value === undefined || value === null || value === "") return Object.freeze([]);
  const values = Array.isArray(value) ? value : [value];
  const ids = values.flatMap((entry) => {
    if (typeof entry !== "string") throw new InputError("INVALID_SEARCH");
    return entry.split(",");
  });
  if (
    ids.length < 1
    || ids.length > 50
    || ids.some((id) => id.trim() !== id || !WIX_ID_PATTERN.test(id))
  ) {
    throw new InputError("INVALID_SEARCH");
  }
  const uniqueIds = [...new Set(ids)].sort();
  if (uniqueIds.length > 50) throw new InputError("INVALID_SEARCH");
  return Object.freeze(uniqueIds);
}

export function normalizeReviewInput(rawBody) {
  const body = assertPlainObject(rawBody);
  const professionalId = cleanText(body.professionnelId, {
    required: true,
    min: 1,
    max: 100,
    code: "INVALID_REVIEW",
  });
  if (!WIX_ID_PATTERN.test(professionalId)) throw new InputError("INVALID_REVIEW");
  const rating = Number(body.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new InputError("INVALID_REVIEW");
  }
  return Object.freeze({
    professionalId,
    auteurNom: cleanText(body.auteurNom, {
      required: true,
      min: 2,
      max: 80,
      code: "INVALID_REVIEW",
    }),
    rating,
    title: cleanText(body.title, {
      required: true,
      min: 2,
      max: 120,
      code: "INVALID_REVIEW",
    }),
    message: cleanText(body.message, {
      required: true,
      min: 5,
      max: 2000,
      code: "INVALID_REVIEW",
    }),
  });
}

function pick(source, fields) {
  const result = {};
  for (const field of fields) {
    if (source[field] !== undefined && source[field] !== null) result[field] = source[field];
  }
  return result;
}

export function toPublicProfessional(item) {
  return pick(item, [
    "_id", "title", "subtitle", "ville", "address", "numroDeTlphone", "image",
    "mediagallery", "gallery", "sousCatgorie", "category", "sousCategorie", "speciality",
    "plan", "averageRating", "reviewCount", "couponTitle", "couponTitleEn", "couponCode",
    "couponExpirationDate", "couponDescription", "couponDescriptionEn", "galerieImage1",
    "galerieImage2", "galerieImage3", "galerieImage4", "galerieImage5", "email", "siteWeb",
    "lienFacebook", "lienInstagram", "linkedin", "lienWhatsapp", "lienTiktok", "lienYoutube",
    "isActive", "sponsor",
  ]);
}

export function isReviewPublic(item) {
  if (!item || typeof item !== "object") return false;
  return item.isApproved === true || item.moderationStatus === "approved";
}

export function reviewProfessionalId(item) {
  if (!item || typeof item !== "object" || Array.isArray(item)) return "";
  const value = item.professionalId ?? item.professionnelId ?? item.image;
  if (typeof value === "string") return value;
  return value && typeof value === "object" && typeof value._id === "string"
    ? value._id
    : "";
}

export function isCategoryEnabled(item) {
  return Boolean(
    item
    && typeof item === "object"
    && !Array.isArray(item)
    && item.isActive !== false
    && item.disabled !== true
    && item.isDisabled !== true,
  );
}

export function toPublicReview(item) {
  const projected = pick(item, [
    "_id", "professionalId", "auteurNom", "rating", "message", "title",
    "dateCreation", "dateCreationFormatted",
  ]);
  const professionalId = reviewProfessionalId(item);
  if (professionalId) projected.professionalId = professionalId;
  return projected;
}

export function toPublicSubCategory(item) {
  return pick(item, [
    "_id", "title", "titleEn", "image", "imageEn", "icon", "iconEn",
  ]);
}

export function toPublicPartner(item) {
  return pick(item, [
    "_id", "title", "titleEn", "description", "descriptionEn", "logo", "category",
    "website", "banner", "isOfficial", "isFeatured", "displayOrder", "isActive", "createdAt",
  ]);
}

export function toPublicOffer(item) {
  return pick(item, [
    "_id", "title", "titleEn", "description", "descriptionEn", "image", "link",
    "startDate", "endDate", "isExclusive", "isRecommended", "partnerId",
  ]);
}
