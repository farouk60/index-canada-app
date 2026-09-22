import assert from "node:assert/strict";
import test from "node:test";

import {
  DIRECTORY_COLLECTION_LIMITS,
  DirectoryDatasetLimitError,
  DirectoryPaginationInputError,
  buildDirectoryPage,
  collectAllPages,
  createDirectoryCursor,
  normalizeDirectoryPageRequest,
  parseDirectoryCursor,
} from "../directory-pagination.js";

function wixPages(pages, { nextErrorAt, nextError } = {}) {
  let nextCalls = 0;

  const pageAt = (index) => ({
    items: pages[index],
    hasNext: () => index < pages.length - 1,
    next: async () => {
      nextCalls += 1;
      if (nextErrorAt === index) throw nextError;
      return pageAt(index + 1);
    },
  });

  return {
    firstPage: pageAt(0),
    get nextCalls() {
      return nextCalls;
    },
  };
}

test("collecte 1001 éléments Wix sans tronquer la seconde page", async () => {
  const firstItems = Array.from({ length: 1000 }, (_, index) => ({ id: index }));
  const source = wixPages([firstItems, [{ id: 1000 }]]);

  const result = await collectAllPages(source.firstPage, {
    collection: "Professionnel",
  });

  assert.equal(result.items.length, 1001);
  assert.equal(result.items[0].id, 0);
  assert.equal(result.items[1000].id, 1000);
  assert.equal(source.nextCalls, 1);
  assert.deepEqual(result.metadata, {
    collection: "Professionnel",
    pageCount: 2,
    itemCount: 1001,
    maxItems: DIRECTORY_COLLECTION_LIMITS.Professionnel,
    complete: true,
  });
});

test("appelle next exactement une fois par page supplémentaire", async () => {
  const source = wixPages([[1], [2], [3], [4]]);

  const result = await collectAllPages(source.firstPage, {
    collection: "SousCategorie",
  });

  assert.deepEqual(result.items, [1, 2, 3, 4]);
  assert.equal(source.nextCalls, 3);
  assert.equal(result.metadata.pageCount, 4);
});

test("conserve l'ordre des éléments entre toutes les pages", async () => {
  const source = wixPages([["a", "b"], ["c"], ["d", "e"]]);

  const result = await collectAllPages(source.firstPage, {
    collection: "Partenaires",
  });

  assert.deepEqual(result.items, ["a", "b", "c", "d", "e"]);
});

test("refuse explicitement une collection qui dépasse son plafond", async () => {
  const source = wixPages([[1, 2], [3]]);

  await assert.rejects(
    collectAllPages(source.firstPage, {
      collection: "OffresPartenaire",
      maxItems: 2,
    }),
    (error) => {
      assert.ok(error instanceof DirectoryDatasetLimitError);
      assert.equal(error.code, "DIRECTORY_DATASET_LIMIT_EXCEEDED");
      assert.equal(error.collection, "OffresPartenaire");
      assert.equal(error.maxItems, 2);
      assert.equal(error.itemCount, 2);
      assert.equal(error.minimumItemCount, 3);
      assert.equal(error.pageCount, 1);
      return true;
    },
  );
  assert.equal(source.nextCalls, 0);
});

test("propage sans l'altérer une erreur de lecture de la page suivante", async () => {
  const expectedError = new Error("Wix indisponible");
  const source = wixPages([[1], [2]], {
    nextErrorAt: 0,
    nextError: expectedError,
  });

  await assert.rejects(
    collectAllPages(source.firstPage, {
      collection: "Reviews",
    }),
    (error) => error === expectedError,
  );
  assert.equal(source.nextCalls, 1);
});

test("le curseur opaque conserve une position stable et reste lié aux filtres", () => {
  const cursor = createDirectoryCursor({
    collection: "Professionnel",
    filterKey: JSON.stringify({ category: "legal", city: "montréal" }),
    lastId: "profile_002",
  });

  assert.doesNotMatch(cursor, /profile_002/u);
  assert.deepEqual(parseDirectoryCursor(cursor, {
    collection: "Professionnel",
    filterKey: JSON.stringify({ category: "legal", city: "montréal" }),
  }), { lastId: "profile_002" });
  assert.throws(
    () => parseDirectoryCursor(cursor, {
      collection: "Professionnel",
      filterKey: JSON.stringify({ category: "health", city: "montréal" }),
    }),
    (error) => error instanceof DirectoryPaginationInputError && error.code === "INVALID_CURSOR",
  );
  assert.throws(
    () => parseDirectoryCursor(cursor, {
      collection: "Reviews",
      filterKey: JSON.stringify({ category: "legal", city: "montréal" }),
    }),
    (error) => error instanceof DirectoryPaginationInputError && error.code === "INVALID_CURSOR",
  );
});

test("rejette un curseur altéré ou non canonique", () => {
  const cursor = createDirectoryCursor({
    collection: "SousCategorie",
    lastId: "category_010",
  });
  const last = cursor.at(-1);
  const altered = `${cursor.slice(0, -1)}${last === "A" ? "B" : "A"}`;

  assert.throws(
    () => parseDirectoryCursor(altered, { collection: "SousCategorie" }),
    (error) => error instanceof DirectoryPaginationInputError && error.code === "INVALID_CURSOR",
  );
  assert.throws(
    () => parseDirectoryCursor(`${cursor}=`, { collection: "SousCategorie" }),
    (error) => error instanceof DirectoryPaginationInputError && error.code === "INVALID_CURSOR",
  );
});

test("borne strictement la taille de page publique", () => {
  assert.deepEqual(normalizeDirectoryPageRequest({}, {
    collection: "Reviews",
  }), { limit: 25, lastId: null });
  assert.deepEqual(normalizeDirectoryPageRequest({ limit: "100" }, {
    collection: "Reviews",
  }), { limit: 100, lastId: null });
  assert.throws(
    () => normalizeDirectoryPageRequest({ limit: "101" }, { collection: "Reviews" }),
    (error) => error instanceof DirectoryPaginationInputError && error.code === "INVALID_PAGE_SIZE",
  );
  assert.throws(
    () => normalizeDirectoryPageRequest({ limit: "1e2" }, { collection: "Reviews" }),
    (error) => error instanceof DirectoryPaginationInputError && error.code === "INVALID_PAGE_SIZE",
  );
});

test("la page défensive avance sur la fenêtre Wix même si un élément est masqué", () => {
  const result = buildDirectoryPage([
    { _id: "pro_001", isActive: true, title: "Visible" },
    { _id: "pro_002", isActive: false, title: "Masqué" },
    { _id: "pro_003", isActive: true, title: "Page suivante" },
  ], {
    collection: "Professionnel",
    filterKey: "{}",
    limit: 2,
    isVisible: (item) => item.isActive === true,
    project: (item) => ({ id: item._id, title: item.title }),
  });

  assert.deepEqual(result.items, [{ id: "pro_001", title: "Visible" }]);
  assert.equal(result.pagination.hasMore, true);
  assert.equal(result.pagination.limit, 2);
  assert.deepEqual(parseDirectoryCursor(result.pagination.nextCursor, {
    collection: "Professionnel",
    filterKey: "{}",
  }), { lastId: "pro_002" });
});
