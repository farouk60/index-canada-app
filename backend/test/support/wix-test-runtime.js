const operationLog = [];
let collections = new Map();

function clone(value) {
  return structuredClone(value);
}

function comparable(value) {
  if (value && typeof value === "object" && typeof value._id === "string") {
    return value._id;
  }
  return value;
}

function equals(actual, expected) {
  return comparable(actual) === comparable(expected);
}

function collectionItems(name) {
  return collections.get(name) ?? [];
}

class MemoryQuery {
  constructor(
    collection,
    predicate = () => true,
    operations = [],
    sortField = null,
    pageLimit = 50,
  ) {
    this.collection = collection;
    this.predicate = predicate;
    this.operations = operations;
    this.sortField = sortField;
    this.pageLimit = pageLimit;
  }

  derive({ predicate, operation, sortField, pageLimit } = {}) {
    return new MemoryQuery(
      this.collection,
      predicate ?? this.predicate,
      operation ? [...this.operations, operation] : [...this.operations],
      sortField === undefined ? this.sortField : sortField,
      pageLimit ?? this.pageLimit,
    );
  }

  eq(field, expected) {
    const previous = this.predicate;
    return this.derive({
      predicate: (item) => previous(item) && equals(item?.[field], expected),
      operation: { method: "eq", field, value: clone(expected) },
    });
  }

  gt(field, expected) {
    const previous = this.predicate;
    return this.derive({
      predicate: (item) => previous(item) && comparable(item?.[field]) > comparable(expected),
      operation: { method: "gt", field, value: clone(expected) },
    });
  }

  hasSome(field, expectedValues) {
    const expected = Array.isArray(expectedValues) ? expectedValues.map(comparable) : [];
    const previous = this.predicate;
    return this.derive({
      predicate: (item) => {
        if (!previous(item)) return false;
        const actual = item?.[field];
        if (Array.isArray(actual)) {
          return actual.map(comparable).some((value) => expected.includes(value));
        }
        return expected.includes(comparable(actual));
      },
      operation: { method: "hasSome", field, value: clone(expectedValues) },
    });
  }

  contains(field, expected) {
    const previous = this.predicate;
    const fragment = String(expected);
    return this.derive({
      predicate: (item) => previous(item) && String(item?.[field] ?? "").includes(fragment),
      operation: { method: "contains", field, value: fragment },
    });
  }

  and(other) {
    if (!(other instanceof MemoryQuery) || other.collection !== this.collection) {
      throw new TypeError("Les requêtes Wix combinées doivent viser la même collection");
    }
    return this.derive({
      predicate: (item) => this.predicate(item) && other.predicate(item),
      operation: { method: "and", operations: clone(other.operations) },
    });
  }

  or(other) {
    if (!(other instanceof MemoryQuery) || other.collection !== this.collection) {
      throw new TypeError("Les requêtes Wix combinées doivent viser la même collection");
    }
    return this.derive({
      predicate: (item) => this.predicate(item) || other.predicate(item),
      operation: { method: "or", operations: clone(other.operations) },
    });
  }

  ascending(field) {
    return this.derive({
      operation: { method: "ascending", field },
      sortField: field,
    });
  }

  limit(value) {
    return this.derive({
      operation: { method: "limit", value },
      pageLimit: value,
    });
  }

  async find(options = {}) {
    let matched = collectionItems(this.collection).filter(this.predicate);
    if (this.sortField) {
      const field = this.sortField;
      matched = [...matched].sort((left, right) => String(left?.[field] ?? "")
        .localeCompare(String(right?.[field] ?? "")));
    }
    const limit = this.pageLimit;
    operationLog.push({
      type: "find",
      collection: this.collection,
      operations: clone(this.operations),
      options: clone(options),
    });

    const pageAt = (offset) => ({
      items: clone(matched.slice(offset, offset + limit)),
      hasNext: () => offset + limit < matched.length,
      next: async () => pageAt(offset + limit),
    });
    return pageAt(0);
  }
}

export const wixData = Object.freeze({
  query(collection) {
    operationLog.push({ type: "query", collection });
    return new MemoryQuery(collection);
  },

  async insert(collection, item, options = {}) {
    const items = collectionItems(collection);
    if (items.some((existing) => existing?._id === item?._id)) {
      const error = new Error("Item already exists");
      error.code = "WDE0074";
      throw error;
    }
    const stored = clone(item);
    collections.set(collection, [...items, stored]);
    operationLog.push({ type: "insert", collection, item: clone(stored), options: clone(options) });
    return clone(stored);
  },

  async update(collection, item, options = {}) {
    const items = collectionItems(collection);
    const index = items.findIndex((existing) => existing?._id === item?._id);
    if (index < 0) throw new Error(`Item ${item?._id ?? ""} not found`);
    const updated = [...items];
    updated[index] = clone(item);
    collections.set(collection, updated);
    operationLog.push({ type: "update", collection, item: clone(item), options: clone(options) });
    return clone(item);
  },
});

export const wixDataTest = Object.freeze({
  reset(seed = {}) {
    collections = new Map(
      Object.entries(seed).map(([collection, items]) => [collection, clone(items)]),
    );
    operationLog.length = 0;
  },

  items(collection) {
    return clone(collectionItems(collection));
  },

  get calls() {
    return clone(operationLog);
  },
});

function httpResponse(status, options = {}) {
  return {
    status,
    statusCode: status,
    headers: options.headers ?? {},
    body: options.body,
  };
}

export const ok = (options) => httpResponse(200, options);
export const created = (options) => httpResponse(201, options);
export const badRequest = (options) => httpResponse(400, options);
export const forbidden = (options) => httpResponse(403, options);
export const notFound = (options) => httpResponse(404, options);
export const serverError = (options) => httpResponse(500, options);
export const response = (options) => httpResponse(options.status, options);

export function elevate(callback) {
  return callback;
}

export const secrets = Object.freeze({
  async getSecretValue(name) {
    return { value: `test-only-${name}-secret-with-more-than-thirty-two-characters` };
  },
});

export const mediaManager = Object.freeze({
  async upload() {
    throw new Error("Le téléversement média n'est pas disponible dans ce double de test");
  },
  async moveFilesToTrash() {},
});

export class StripeStub {
  constructor() {
    this.paymentIntents = Object.freeze({
      async create() {
        throw new Error("Stripe n'est pas disponible dans ce double de test");
      },
      async retrieve() {
        throw new Error("Stripe n'est pas disponible dans ce double de test");
      },
    });
    this.webhooks = Object.freeze({
      constructEvent() {
        throw new Error("Stripe n'est pas disponible dans ce double de test");
      },
    });
  }
}
