import test from "node:test";
import assert from "node:assert/strict";
import {
  FREE_TOKEN_PREFIX,
  InputError,
  MEDIA_STORAGE_VERSION,
  assertCheckoutNotExpired,
  buildEngagementEventRecord,
  buildMediaUploadPlan,
  buildPersistedCheckoutDraft,
  buildProfessionalId,
  buildProfessionalRecord,
  classifyConfirmationReference,
  classifyPaymentIntentWebhook,
  createCheckoutDraft,
  createFreeConfirmationToken,
  createFreeCheckoutToken,
  directorySearchText,
  evaluateRateLimit,
  getPlan,
  isCategoryEnabled,
  isReviewPublic,
  normalizeEngagementEvent,
  normalizeImageDataUrl,
  normalizeFeaturedFilter,
  normalizeProfessionalIdFilter,
  normalizeProfessionalIdsFilter,
  normalizeRegistrationInput,
  normalizeReviewInput,
  normalizeSearchParams,
  normalizeWixImageUrl,
  projectPaymentPlans,
  registrationFingerprint,
  reviewProfessionalId,
  selectOrphanedMediaUrls,
  toPublicProfessional,
  toPublicReview,
  validatePaymentIntentBinding,
  validatePaymentIntentForCheckout,
  validatePersistedCheckout,
  verifyFreeCheckoutToken,
  verifyFreeConfirmationToken,
} from "../security-core.js";

const SIGNING_SECRET = "test-only-secret-with-at-least-thirty-two-characters";
const NOW = Date.UTC(2026, 8, 17, 12, 0, 0);

function registration(overrides = {}) {
  return {
    professionalId: "temp_1758100000000",
    email: "owner@example.ca",
    businessName: "Cabinet Exemple",
    categoryId: "legal-services",
    ville: "Montréal",
    phone: "+1 514 555 0101",
    address: "100 rue Exemple, Montréal",
    description: "Conseils pour les nouveaux arrivants",
    website: "https://example.ca",
    ...overrides,
  };
}

function expectInputError(callback, code) {
  assert.throws(callback, (error) => error instanceof InputError && error.code === code);
}

function pngDataUrl(byteLength = 64) {
  const image = Buffer.alloc(byteLength, 0);
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(image);
  return `data:image/png;base64,${image.toString("base64")}`;
}

function uploadedReferences(uploadPlan) {
  const references = { profile: "", gallery: [] };
  for (const upload of uploadPlan.uploads) {
    const url = `wix:image://v1/abc123~mv2.png/${upload.fileName}#originWidth=8&originHeight=8`;
    if (upload.kind === "profile") references.profile = url;
    else references.gallery[upload.index] = url;
  }
  return references;
}

test("le catalogue serveur est l'unique source des montants", () => {
  const basic = getPlan("basic");
  assert.deepEqual({
    id: basic.id,
    amountCents: basic.amountCents,
    currency: basic.currency,
    requiresPayment: basic.requiresPayment,
    durationDays: basic.durationDays,
  }, {
    id: "basic",
    amountCents: 0,
    currency: "cad",
    requiresPayment: false,
    durationDays: 365,
  });
  assert.equal(basic.capabilities.galleryMax, 0);
  assert.equal(basic.capabilities.coupon, false);
  assert.equal(getPlan("premium").capabilities.galleryMax, 5);
  assert.equal(getPlan("premium").capabilities.coupon, true);
  assert.equal(getPlan("premium").amountCents, 4999);
  assert.equal(getPlan("professional").amountCents, 11999);
  expectInputError(() => getPlan("premium<script>"), "INVALID_PLAN");
});

test("la projection publique des forfaits expose uniquement le devis et les capacités", () => {
  const plans = projectPaymentPlans();
  assert.equal(plans.length, 3);
  assert.deepEqual(Object.keys(plans[0]), [
    "id",
    "amount",
    "currency",
    "requires_payment",
    "duration_days",
    "label",
    "capabilities",
    "features",
  ]);
  assert.deepEqual(plans.find((plan) => plan.id === "basic")?.capabilities, {
    profile_image: true,
    gallery_max: 0,
    coupon: false,
    featured: false,
  });
  assert.deepEqual(plans.find((plan) => plan.id === "premium")?.capabilities, {
    profile_image: true,
    gallery_max: 5,
    coupon: true,
    featured: false,
  });
  assert.equal(JSON.stringify(plans).includes("amountCents"), false);
  assert.equal(JSON.stringify(plans).includes("secret"), false);
});

test("seuls les avis explicitement approuvés sont publiables", () => {
  assert.equal(isReviewPublic({ isApproved: true }), true);
  assert.equal(isReviewPublic({ moderationStatus: "approved" }), true);
  assert.equal(isReviewPublic({ moderationStatus: "pending" }), false);
  assert.equal(isReviewPublic({ moderationStatus: "rejected" }), false);
  assert.equal(isReviewPublic({}), false);
  assert.equal(isReviewPublic(null), false);
});

test("les alias historiques d'association d'avis sont normalisés", () => {
  assert.equal(reviewProfessionalId({ professionalId: "pro-current" }), "pro-current");
  assert.equal(reviewProfessionalId({ professionnelId: "pro-legacy-fr" }), "pro-legacy-fr");
  assert.equal(reviewProfessionalId({ image: "pro-legacy-image" }), "pro-legacy-image");
  assert.equal(reviewProfessionalId({ professionalId: { _id: "pro-reference" } }), "pro-reference");
  assert.deepEqual(toPublicReview({
    _id: "review-1",
    professionnelId: "pro-legacy-fr",
    title: "Excellent",
    internalNote: "ne pas exposer",
  }), {
    _id: "review-1",
    professionalId: "pro-legacy-fr",
    title: "Excellent",
  });
});

test("une inscription publique ne peut pas viser un profil existant", () => {
  expectInputError(
    () => normalizeRegistrationInput(registration({ professionalId: "existing-profile-id" })),
    "EXISTING_PROFILE_NOT_ALLOWED",
  );
});

test("la normalisation valide les champs et retire le balisage actif", () => {
  const normalized = normalizeRegistrationInput(registration({
    businessName: "  Cabinet <script>alert(1)</script>  ",
    website: "example.ca/path",
  }));
  assert.equal(normalized.businessName, "Cabinet scriptalert(1)/script");
  assert.equal(normalized.website, "https://example.ca/path");
  assert.equal(normalized.email, "owner@example.ca");
});

test("le jeton gratuit signé est lié à l'inscription et expire après 30 minutes", () => {
  const input = registration();
  const issued = createFreeConfirmationToken(input, SIGNING_SECRET, NOW);
  assert.equal(issued.token.startsWith(FREE_TOKEN_PREFIX), true);

  const verified = verifyFreeConfirmationToken(issued.token, input, SIGNING_SECRET, NOW + 60_000);
  assert.equal(verified.planId, "basic");
  assert.equal(verified.fp, registrationFingerprint(input));

  expectInputError(
    () => verifyFreeConfirmationToken(issued.token, registration({ businessName: "Autre entreprise" }), SIGNING_SECRET, NOW),
    "REGISTRATION_MISMATCH",
  );
  expectInputError(
    () => verifyFreeConfirmationToken(issued.token, input, SIGNING_SECRET, NOW + 30 * 60 * 1000),
    "INVALID_CONFIRMATION_TOKEN",
  );
});

test("une altération de signature et les anciens free_plan_* sont refusés", () => {
  const issued = createFreeConfirmationToken(registration(), SIGNING_SECRET, NOW);
  const last = issued.token.at(-1);
  const tampered = `${issued.token.slice(0, -1)}${last === "A" ? "B" : "A"}`;
  expectInputError(
    () => verifyFreeConfirmationToken(tampered, registration(), SIGNING_SECRET, NOW),
    "INVALID_CONFIRMATION_TOKEN",
  );
  expectInputError(() => classifyConfirmationReference("free_plan_123"), "LEGACY_FREE_TOKEN_DISABLED");
  assert.equal(classifyConfirmationReference(issued.token), "free");
  assert.equal(classifyConfirmationReference("pi_3Abcdefghijklmnop"), "stripe");
});

test("le jeton gratuit v2 est lié au checkout persistant et expire", () => {
  const checkout = createCheckoutDraft({ ...registration(), planId: "basic" }, NOW);
  const issued = createFreeCheckoutToken(checkout, SIGNING_SECRET, NOW);
  const verified = verifyFreeCheckoutToken(issued.token, SIGNING_SECRET, NOW + 60_000);
  assert.equal(verified.checkoutId, checkout._id);
  assert.equal(verified.fp, checkout.fingerprint);

  const last = issued.token.at(-1);
  const tampered = `${issued.token.slice(0, -1)}${last === "A" ? "B" : "A"}`;
  expectInputError(
    () => verifyFreeCheckoutToken(tampered, SIGNING_SECRET, NOW),
    "INVALID_CONFIRMATION_TOKEN",
  );
  expectInputError(
    () => verifyFreeCheckoutToken(issued.token, SIGNING_SECRET, NOW + 30 * 60 * 1000),
    "INVALID_CONFIRMATION_TOKEN",
  );
});

test("Basic refuse galerie et coupon avant tout appel de paiement", () => {
  expectInputError(
    () => createCheckoutDraft({
      ...registration(),
      planId: "basic",
      galleryImagesBase64: [pngDataUrl()],
    }, NOW),
    "PLAN_CAPABILITY_VIOLATION",
  );
  expectInputError(
    () => createCheckoutDraft({
      ...registration(),
      planId: "basic",
      couponTitle: "Bienvenue",
      couponCode: "CANADA10",
      couponDescription: "Rabais de dix pour cent",
    }, NOW),
    "PLAN_CAPABILITY_VIOLATION",
  );
});

test("Premium accepte cinq images et persiste un coupon dans le checkout idempotent", () => {
  const input = {
    ...registration(),
    planId: "premium",
    galleryImagesBase64: Array.from({ length: 5 }, () => pngDataUrl()),
    couponTitle: "Bienvenue",
    couponTitleEn: "Welcome",
    couponCode: "CANADA10",
    couponDescription: "Rabais de dix pour cent",
    couponDescriptionEn: "Ten percent discount",
    couponExpirationDate: new Date(NOW + 7 * 24 * 60 * 60 * 1000).toISOString(),
  };
  const first = createCheckoutDraft(input, NOW);
  const retry = createCheckoutDraft(input, NOW + 5_000);
  assert.equal(first._id, retry._id);
  assert.equal(first.images.gallery.length, 5);
  assert.equal(first.coupon.code, "CANADA10");
  assert.equal(first.coupon.title, "Bienvenue");
  assert.equal(first.amountCents, 4999);

  const uploadPlan = buildMediaUploadPlan(first);
  const references = uploadedReferences(uploadPlan);
  const persistedCheckout = buildPersistedCheckoutDraft(first, references);
  assert.equal(JSON.stringify(persistedCheckout).includes("base64"), false);
  assert.equal(persistedCheckout.imageHashes.gallery.length, 5);
  const professional = buildProfessionalRecord(
    persistedCheckout,
    "pi_3Abcdefghijklmnop",
    NOW,
  );
  assert.equal(professional.galerieImage5, references.gallery[4]);
  assert.equal(professional.galerieImage5.startsWith("wix:image://"), true);
  assert.equal(JSON.stringify(professional).includes("base64"), false);
  assert.equal(professional.couponCode, "CANADA10");
  assert.equal(professional.couponDescriptionEn, "Ten percent discount");
  assert.equal(professional.isActive, false);
  assert.equal(professional.registrationStatus, "pending_review");
});

test("tout nouveau profil reste en attente de révision, même sans paiement", () => {
  const checkout = createCheckoutDraft({ ...registration(), planId: "basic" }, NOW);
  const persisted = buildPersistedCheckoutDraft(checkout, { profile: "", gallery: [] });
  const professional = buildProfessionalRecord(
    persisted,
    `free:${checkout._id}`,
    NOW,
  );

  assert.equal(professional.isActive, false);
  assert.equal(professional.registrationStatus, "pending_review");
  assert.equal(professional.paymentStatus, "not_required");
});

test("un checkout expire exactement à expiresAt", () => {
  const checkout = createCheckoutDraft({ ...registration(), planId: "premium" }, NOW);
  assert.equal(assertCheckoutNotExpired(checkout, Date.parse(checkout.expiresAt) - 1), true);
  expectInputError(
    () => assertCheckoutNotExpired(checkout, Date.parse(checkout.expiresAt)),
    "CHECKOUT_EXPIRED",
  );
  expectInputError(
    () => assertCheckoutNotExpired({ ...checkout, expiresAt: "invalide" }, NOW),
    "INVALID_CHECKOUT",
  );
});

test("le plan média est déterministe et le profil ne persiste que des URL Wix", () => {
  const checkout = createCheckoutDraft({
    ...registration(),
    planId: "premium",
    profileImageBase64: pngDataUrl(96),
    galleryImagesBase64: [pngDataUrl(80), pngDataUrl(72)],
  }, NOW);
  const firstPlan = buildMediaUploadPlan(checkout);
  const retryPlan = buildMediaUploadPlan(checkout);

  assert.equal(firstPlan.professionalId, buildProfessionalId(`checkout:${checkout._id}`));
  assert.equal(firstPlan.path, `/index-canada/professionals/${firstPlan.professionalId}`);
  assert.deepEqual(
    firstPlan.uploads.map(({ kind, index, path, fileName, mimeType }) => ({
      kind,
      index,
      path,
      fileName,
      mimeType,
    })),
    retryPlan.uploads.map(({ kind, index, path, fileName, mimeType }) => ({
      kind,
      index,
      path,
      fileName,
      mimeType,
    })),
  );
  assert.match(firstPlan.uploads[0].fileName, /^profile-[a-f0-9]{24}\.png$/u);
  assert.match(firstPlan.uploads[1].fileName, /^gallery-01-[a-f0-9]{24}\.png$/u);
  assert.equal(firstPlan.uploads.every((upload) => Buffer.isBuffer(upload.buffer)), true);
  assert.equal(firstPlan.uploads.every((upload) => upload.mimeType === "image/png"), true);

  const references = uploadedReferences(firstPlan);
  const persistedCheckout = buildPersistedCheckoutDraft(checkout, references);
  assert.equal(validatePersistedCheckout(persistedCheckout).id, "premium");
  assert.equal(persistedCheckout.mediaStorageVersion, MEDIA_STORAGE_VERSION);
  assert.equal(JSON.stringify(persistedCheckout).includes("data:image"), false);
  assert.equal(JSON.stringify(persistedCheckout).length < 10_000, true);
  assert.equal(persistedCheckout.fingerprint, checkout.fingerprint);
  assert.deepEqual(persistedCheckout.imageHashes, checkout.imageHashes);
  const professional = buildProfessionalRecord(
    persistedCheckout,
    "pi_3Abcdefghijklmnop",
    NOW,
  );
  assert.equal(professional.image, references.profile);
  assert.deepEqual([
    professional.image,
    professional.galerieImage1,
    professional.galerieImage2,
  ], [references.profile, ...references.gallery]);
  assert.equal(JSON.stringify(professional).includes("data:image"), false);

  expectInputError(
    () => buildPersistedCheckoutDraft(checkout, {
      profile: references.profile,
      gallery: [references.gallery[0]],
    }),
    "INVALID_MEDIA_REFERENCE",
  );
  expectInputError(
    () => normalizeWixImageUrl("https://static.wixstatic.com/media/image.png"),
    "INVALID_MEDIA_REFERENCE",
  );
  expectInputError(
    () => validatePersistedCheckout({
      ...persistedCheckout,
      images: {
        ...persistedCheckout.images,
        profile: checkout.images.profile,
      },
    }),
    "INVALID_MEDIA_REFERENCE",
  );
  expectInputError(
    () => validatePersistedCheckout({
      ...persistedCheckout,
      imageHashes: {
        ...persistedCheckout.imageHashes,
        profile: "0".repeat(64),
      },
    }),
    "INVALID_CHECKOUT",
  );
});

test("l'idempotence média dépend des octets et non de l'enveloppe Base64", () => {
  const dataUrl = pngDataUrl(96);
  const bareBase64 = dataUrl.split(",")[1];
  const fromDataUrl = createCheckoutDraft({
    ...registration(),
    planId: "basic",
    profileImageBase64: dataUrl,
  }, NOW);
  const fromBareBase64 = createCheckoutDraft({
    ...registration(),
    planId: "basic",
    profileImageBase64: bareBase64,
  }, NOW + 1_000);

  assert.equal(fromDataUrl._id, fromBareBase64._id);
  assert.equal(fromDataUrl.fingerprint, fromBareBase64.fingerprint);
  assert.equal(fromDataUrl.imageHashes.profile, fromBareBase64.imageHashes.profile);
});

test("le nettoyage compensatoire ne cible jamais un média déjà référencé", () => {
  const first = "wix:image://v1/first~mv2.png/first.png#originWidth=8&originHeight=8";
  const second = "wix:image://v1/second~mv2.png/second.png#originWidth=8&originHeight=8";
  assert.deepEqual(
    selectOrphanedMediaUrls([first, second, second], [first]),
    [second],
  );
  expectInputError(
    () => selectOrphanedMediaUrls(["https://example.ca/not-wix.png"], []),
    "INVALID_MEDIA_REFERENCE",
  );
});

test("le budget total des images est rejeté lors de la création du checkout", () => {
  const largeButIndividuallyValidImage = pngDataUrl(65_000);
  expectInputError(
    () => createCheckoutDraft({
      ...registration(),
      planId: "premium",
      galleryImagesBase64: Array.from({ length: 5 }, () => largeButIndividuallyValidImage),
    }, NOW),
    "PAYLOAD_TOO_LARGE",
  );
});

test("la décision de limitation est persistable, bornée et réinitialisée par fenêtre", () => {
  const config = { limit: 3, windowMs: 60_000 };
  let state = null;
  for (let requestNumber = 1; requestNumber <= 3; requestNumber += 1) {
    state = evaluateRateLimit(state, NOW + requestNumber, config);
    assert.equal(state.allowed, true);
    assert.equal(state.count, requestNumber);
  }
  state = evaluateRateLimit(state, NOW + 4, config);
  assert.equal(state.allowed, false);
  assert.equal(state.retryAfterSeconds, 60);

  const reset = evaluateRateLimit(state, NOW + 60_001, config);
  assert.equal(reset.allowed, true);
  assert.equal(reset.count, 1);
});

test("la validation Stripe lie statut, montant, devise et métadonnées au checkout", () => {
  const checkout = createCheckoutDraft({ ...registration(), planId: "premium" }, NOW);
  const paymentIntent = {
    id: "pi_3Abcdefghijklmnop",
    status: "succeeded",
    amount: 4999,
    amount_received: 4999,
    currency: "cad",
    metadata: {
      checkoutVersion: "2",
      checkoutId: checkout._id,
      checkoutFingerprint: checkout.fingerprint,
      planId: "premium",
      expectedAmountCents: "4999",
      currency: "cad",
    },
  };
  assert.equal(
    validatePaymentIntentBinding({ ...paymentIntent, status: "requires_payment_method", amount_received: 0 }, checkout).id,
    "premium",
  );
  assert.equal(validatePaymentIntentForCheckout(paymentIntent, checkout).id, "premium");
  expectInputError(
    () => validatePaymentIntentForCheckout({ ...paymentIntent, amount_received: 1 }, checkout),
    "UNTRUSTED_PAYMENT_INTENT",
  );
  expectInputError(
    () => validatePaymentIntentForCheckout({ ...paymentIntent, status: "processing" }, checkout),
    "UNTRUSTED_PAYMENT_INTENT",
  );
  expectInputError(
    () => validatePaymentIntentBinding({
      ...paymentIntent,
      status: "requires_payment_method",
      amount_received: 0,
      metadata: { ...paymentIntent.metadata, checkoutId: "chk_00000000000000000000000000000000" },
    }, checkout),
    "UNTRUSTED_PAYMENT_INTENT",
  );
});

test("le webhook ignore un PaymentIntent étranger mais refuse tout lien v2 incohérent", () => {
  assert.equal(classifyPaymentIntentWebhook({
    id: "pi_3Foreignwithoutmeta",
  }), "foreign");
  assert.equal(classifyPaymentIntentWebhook({
    id: "pi_3Foreignabcdefghijk",
    metadata: { merchant: "another-application" },
  }), "foreign");
  assert.equal(classifyPaymentIntentWebhook({
    id: "pi_3Abcdefghijklmnop",
    metadata: { checkoutVersion: "2" },
  }), "linked");
  expectInputError(
    () => classifyPaymentIntentWebhook({
      id: "pi_3Abcdefghijklmnop",
      metadata: { checkoutId: "chk_00000000000000000000000000000000" },
    }),
    "UNTRUSTED_PAYMENT_INTENT",
  );
  expectInputError(
    () => classifyPaymentIntentWebhook({
      id: "pi_3Abcdefghijklmnop",
      metadata: { checkoutVersion: "1" },
    }),
    "UNTRUSTED_PAYMENT_INTENT",
  );
});

test("les identifiants professionnels idempotents sont stables et compatibles Wix", () => {
  const first = buildProfessionalId("stripe:pi_3Abcdefghijklmnop");
  const second = buildProfessionalId("stripe:pi_3Abcdefghijklmnop");
  assert.equal(first, second);
  assert.equal(first.length, 36);
  assert.match(first, /^idx_[a-f0-9]{32}$/u);
});

test("la projection publique exclut les données de paiement et identifiants Stripe", () => {
  const projected = toPublicProfessional({
    _id: "pro-1",
    title: "Entreprise",
    email: "public@example.ca",
    isActive: true,
    paymentId: "pi_secret",
    amountPaid: 119.99,
    stripeCustomerId: "cus_secret",
    registrationFingerprint: "hash",
  });
  assert.deepEqual(projected, {
    _id: "pro-1",
    title: "Entreprise",
    email: "public@example.ca",
    isActive: true,
  });
});

test("la recherche borne la longueur et le nombre de résultats", () => {
  assert.equal(normalizeSearchParams({ search: "avocat", limit: "25" }).limit, 25);
  expectInputError(() => normalizeSearchParams({ limit: "101" }), "INVALID_SEARCH");
  expectInputError(() => normalizeSearchParams({ search: "x".repeat(101) }), "INVALID_SEARCH");
  assert.equal(directorySearchText({
    formatted: "100 rue Exemple, Montréal",
    city: "Montréal",
    streetAddress: { formattedAddressLine: "100 rue Exemple" },
  }), "100 rue Exemple, Montréal Montréal 100 rue Exemple");
  assert.equal(directorySearchText({ _id: "category_1" }), "category_1");
});

test("un événement ROI v1 est normalisé sans donnée personnelle et reçoit un identifiant déterministe", () => {
  const normalized = normalizeEngagementEvent({
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174000",
    type: "contact",
    professionalId: "pro_001",
    placement: "detail",
    channel: "phone",
    locale: "fr",
  });

  assert.deepEqual(normalized, {
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174000",
    type: "contact",
    professionalId: "pro_001",
    placement: "detail",
    channel: "phone",
    locale: "fr",
  });

  const receivedAt = new Date("2026-09-23T14:00:00.000Z");
  const first = buildEngagementEventRecord(normalized, receivedAt);
  const replay = buildEngagementEventRecord(normalized, receivedAt);

  assert.match(first._id, /^eng_[a-f0-9]{32}$/u);
  assert.match(first.contentHash, /^[a-f0-9]{64}$/u);
  assert.equal(first.receivedAt.toISOString(), receivedAt.toISOString());
  assert.equal(first.trustLevel, "client_reported_unverified");
  assert.deepEqual(first, replay);
  assert.equal(Object.hasOwn(first, "eventId"), false);
  assert.equal(JSON.stringify(first).includes("owner@example.ca"), false);
});

test("un événement de recherche ROI exige uniquement des dimensions agrégées", () => {
  assert.deepEqual(normalizeEngagementEvent({
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174001",
    type: "search",
    placement: "directory",
    resultsBucket: "21+",
    searchKind: "category",
    locale: "en",
  }), {
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174001",
    type: "search",
    placement: "directory",
    resultsBucket: "21+",
    searchKind: "category",
    locale: "en",
  });

  expectInputError(() => normalizeEngagementEvent({
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174001",
    type: "search",
    placement: "directory",
    searchKind: "text",
  }), "INVALID_ENGAGEMENT_EVENT");
  expectInputError(() => normalizeEngagementEvent({
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174001",
    type: "search",
    placement: "directory",
    searchKind: "text",
    resultsBucket: "1-5",
    professionalId: "pro_001",
  }), "INVALID_ENGAGEMENT_EVENT");
  expectInputError(() => normalizeEngagementEvent({
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174001",
    type: "search",
    placement: "favorites",
    searchKind: "text",
    resultsBucket: "1-5",
  }), "INVALID_ENGAGEMENT_EVENT");
});

test("le contrat ROI refuse les clés inconnues, les PII et les combinaisons incohérentes", () => {
  const base = {
    version: 1,
    eventId: "123e4567-e89b-42d3-a456-426614174002",
    type: "professional_view",
    professionalId: "pro_001",
  };
  const rejected = [
    base,
    { ...base, email: "owner@example.ca" },
    { ...base, query: "avocat immigration" },
    { ...base, sessionId: "session_001" },
    { ...base, trustLevel: "verified" },
    { ...base, type: "category_view" },
    { ...base, placement: "unknown" },
    { ...base, locale: "es" },
    { ...base, channel: "phone" },
    { ...base, eventId: "event-not-a-uuid" },
    { ...base, professionalId: "pro/001" },
    { ...base, professionalId: " pro_001 " },
    { ...base, categoryId: "legal-services" },
    { ...base, type: undefined },
  ];

  for (const candidate of rejected) {
    expectInputError(
      () => normalizeEngagementEvent(candidate),
      "INVALID_ENGAGEMENT_EVENT",
    );
  }

  expectInputError(() => normalizeEngagementEvent({
    ...base,
    padding: "x".repeat(2500),
  }), "INVALID_ENGAGEMENT_EVENT");
  expectInputError(() => normalizeEngagementEvent({
    ...base,
    type: "contact",
  }), "INVALID_ENGAGEMENT_EVENT");
  expectInputError(() => normalizeEngagementEvent({
    ...base,
    type: "coupon_copy",
    channel: "website",
  }), "INVALID_ENGAGEMENT_EVENT");
});

test("le contrat ROI impose la matrice événement, placement et canal de contact", () => {
  const event = (suffix, type, placement, extra = {}) => ({
    version: 1,
    eventId: `123e4567-e89b-42d3-a456-4266141740${suffix}`,
    type,
    professionalId: "pro_001",
    placement,
    ...extra,
  });

  const accepted = [
    event("20", "professional_click", "home_featured"),
    event("21", "professional_impression", "home_featured"),
    event("22", "professional_impression", "directory"),
    event("23", "professional_view", "detail"),
    event("24", "professional_view", "home_featured"),
    event("25", "professional_view", "directory"),
    event("26", "contact", "detail", { channel: "phone" }),
    event("27", "contact", "home_featured", { channel: "website" }),
    event("28", "contact", "directory", { channel: "map" }),
    event("29", "coupon_copy", "detail"),
    event("30", "coupon_copy", "home_featured"),
    event("31", "coupon_copy", "directory"),
    {
      version: 1,
      eventId: "123e4567-e89b-42d3-a456-426614174032",
      type: "search",
      placement: "directory",
      searchKind: "text",
      resultsBucket: "1-5",
    },
  ];
  for (const candidate of accepted) {
    assert.equal(normalizeEngagementEvent(candidate).placement, candidate.placement);
  }

  const rejected = [
    event("40", "professional_click", "directory"),
    event("41", "professional_impression", "detail"),
    event("42", "professional_impression", "favorites"),
    event("43", "professional_view", "favorites"),
    event("44", "contact", "registration", { channel: "phone" }),
    event("45", "contact", "detail", { channel: "email" }),
    event("46", "contact", "detail"),
    event("47", "coupon_copy", "favorites"),
    event("48", "coupon_copy", "detail", { channel: "website" }),
    {
      version: 1,
      eventId: "123e4567-e89b-42d3-a456-426614174049",
      type: "search",
      placement: "detail",
      searchKind: "city",
      resultsBucket: "6-20",
    },
    event("50", "professional_view", "registration"),
  ];
  for (const candidate of rejected) {
    expectInputError(
      () => normalizeEngagementEvent(candidate),
      "INVALID_ENGAGEMENT_EVENT",
    );
  }
});

test("les filtres publics featured, professionnel et catégorie sont stricts", () => {
  assert.equal(normalizeFeaturedFilter(undefined), null);
  assert.equal(normalizeFeaturedFilter("true"), true);
  assert.equal(normalizeFeaturedFilter("0"), false);
  expectInputError(() => normalizeFeaturedFilter("oui"), "INVALID_SEARCH");
  assert.equal(normalizeProfessionalIdFilter("profile_123"), "profile_123");
  expectInputError(() => normalizeProfessionalIdFilter("profile/123"), "INVALID_SEARCH");
  assert.deepEqual(
    normalizeProfessionalIdsFilter(["profile_002", "profile_001", "profile_002"]),
    ["profile_001", "profile_002"],
  );
  assert.deepEqual(
    normalizeProfessionalIdsFilter("profile_002,profile_001"),
    ["profile_001", "profile_002"],
  );
  expectInputError(
    () => normalizeProfessionalIdsFilter(Array.from({ length: 51 }, (_, index) => `profile_${index}`)),
    "INVALID_SEARCH",
  );
  expectInputError(() => normalizeProfessionalIdsFilter("profile_1,bad/id"), "INVALID_SEARCH");

  assert.equal(isCategoryEnabled({ _id: "cat-1" }), true);
  assert.equal(isCategoryEnabled({ _id: "cat-1", isActive: true }), true);
  assert.equal(isCategoryEnabled({ _id: "cat-1", isActive: false }), false);
  assert.equal(isCategoryEnabled({ _id: "cat-1", disabled: true }), false);
});

test("les avis exigent une note entière entre 1 et 5", () => {
  const review = normalizeReviewInput({
    professionnelId: "profile_123",
    auteurNom: "Marie",
    rating: 5,
    title: "Très bon service",
    message: "Une expérience très utile.",
  });
  assert.equal(review.rating, 5);
  expectInputError(() => normalizeReviewInput({ ...review, professionnelId: "profile_123", rating: 6 }), "INVALID_REVIEW");
});

test("les images base64 sont limitées aux signatures PNG, JPEG ou WebP", () => {
  const png = Buffer.alloc(64, 0);
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(png);
  const normalized = normalizeImageDataUrl(png.toString("base64"), 1000);
  assert.equal(normalized.startsWith("data:image/png;base64,"), true);

  const executable = Buffer.from("MZ".padEnd(64, "x"), "ascii").toString("base64");
  expectInputError(() => normalizeImageDataUrl(executable, 1000), "INVALID_IMAGE");
});
