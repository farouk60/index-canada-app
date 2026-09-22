const runtimeUrl = new URL("./support/wix-test-runtime.js", import.meta.url).href;

function virtualModule(source) {
  return `data:text/javascript;base64,${Buffer.from(source, "utf8").toString("base64")}`;
}

const virtualModules = new Map([
  [
    "wix-http-functions",
    virtualModule(`export {
      badRequest, created, forbidden, notFound, ok, response, serverError
    } from ${JSON.stringify(runtimeUrl)};`),
  ],
  [
    "wix-data",
    virtualModule(`export {
      wixData as default, wixDataTest as __wixDataTest
    } from ${JSON.stringify(runtimeUrl)};`),
  ],
  [
    "wix-auth",
    virtualModule(`export { elevate } from ${JSON.stringify(runtimeUrl)};`),
  ],
  [
    "wix-media-backend",
    virtualModule(`export { mediaManager } from ${JSON.stringify(runtimeUrl)};`),
  ],
  [
    "wix-secrets-backend.v2",
    virtualModule(`export { secrets } from ${JSON.stringify(runtimeUrl)};`),
  ],
  [
    "stripe",
    virtualModule(`export { StripeStub as default } from ${JSON.stringify(runtimeUrl)};`),
  ],
]);

const backendModules = new Map([
  ["backend/directory-pagination", new URL("../directory-pagination.js", import.meta.url).href],
  ["backend/security-core", new URL("../security-core.js", import.meta.url).href],
]);

export async function resolve(specifier, context, nextResolve) {
  const virtualUrl = virtualModules.get(specifier);
  if (virtualUrl) return { url: virtualUrl, shortCircuit: true };

  const backendUrl = backendModules.get(specifier);
  if (backendUrl) return { url: backendUrl, shortCircuit: true };

  return nextResolve(specifier, context);
}
