import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { register } from "node:module";
import { dirname, relative, resolve, sep } from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

register("./wix-test-loader.mjs", import.meta.url);

const backendDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("jobs.config référence des fonctions backend valides avec un chemin Wix absolu", async () => {
  const configText = await readFile(resolve(backendDirectory, "jobs.config"), "utf8");
  const config = JSON.parse(configText);

  assert.ok(Array.isArray(config.jobs));
  assert.ok(config.jobs.length > 0);

  for (const job of config.jobs) {
    assert.match(
      job.functionLocation,
      /^\/[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*\.(?:js|web\.js|jsw)$/,
    );
    assert.match(job.functionName, /^[A-Za-z_$][A-Za-z0-9_$]*$/);

    const relativeLocation = job.functionLocation.slice(1);
    assert.equal(
      relativeLocation
        .split("/")
        .some((segment) => segment === "." || segment === ".."),
      false,
    );

    const modulePath = resolve(backendDirectory, relativeLocation);
    const resolvedRelativePath = relative(backendDirectory, modulePath);
    assert.equal(
      resolvedRelativePath === ".." || resolvedRelativePath.startsWith(`..${sep}`),
      false,
    );
    await access(modulePath);

    const moduleExports = await import(pathToFileURL(modulePath).href);
    assert.equal(typeof moduleExports[job.functionName], "function");
  }
});
