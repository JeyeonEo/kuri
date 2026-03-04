import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable, Writable } from "node:stream";
import { createHandler } from "./server.js";
import { NotionClient } from "./notion.js";

async function callHandler(method, url, body) {
  return callHandlerWithHeaders(method, url, body, {}, makeStateFile());
}

test("oauth start returns local callback authorize URL", async () => {
  const installationId = `install_${crypto.randomUUID()}`;
  const response = await callHandler("POST", "/v1/oauth/notion/start", { installationId });

  assert.equal(response.statusCode, 200);
  const authorizeURL = new URL(response.body.authorizeUrl);
  assert.equal(authorizeURL.pathname, "/v1/oauth/notion/callback");
  assert.notEqual(authorizeURL.searchParams.get("state"), installationId);
});

test("oauth callback redirects into the app with a session token", async () => {
  const installationId = `install_${crypto.randomUUID()}`;
  const stateFile = makeStateFile();
  const start = await callHandlerWithHeadersUsingState(
    "POST",
    "/v1/oauth/notion/start",
    { installationId },
    {},
    stateFile
  );
  const authorizeURL = new URL(start.body.authorizeUrl);
  const state = authorizeURL.searchParams.get("state");
  const response = await callHandlerWithHeadersUsingState(
    "GET",
    `/v1/oauth/notion/callback?state=${state}`,
    null,
    {},
    stateFile
  );

  assert.equal(response.statusCode, 302);
  assert.ok(response.headers.Location.startsWith("kuri://oauth/notion?"));
  assert.ok(response.headers.Location.includes("status=success"));
  assert.ok(response.headers.Location.includes("sessionToken="));
});

test("bootstrap requires a valid session and returns a stable database", async () => {
  const stateFile = makeStateFile();
  const installationId = `install_${crypto.randomUUID()}`;
  const start = await callHandlerWithHeadersUsingState(
    "POST",
    "/v1/oauth/notion/start",
    { installationId },
    {},
    stateFile
  );
  const authorizeURL = new URL(start.body.authorizeUrl);
  const state = authorizeURL.searchParams.get("state");
  const callback = await callHandlerWithHeadersUsingState(
    "GET",
    `/v1/oauth/notion/callback?state=${state}`,
    null,
    {},
    stateFile
  );
  const callbackURL = new URL(callback.headers.Location);
  const sessionToken = callbackURL.searchParams.get("sessionToken");

  const first = await callHandlerWithHeaders(
    "POST",
    "/v1/workspaces/bootstrap",
    { installationId },
    { authorization: `Bearer ${sessionToken}` },
    stateFile
  );
  const second = await callHandlerWithHeaders(
    "POST",
    "/v1/workspaces/bootstrap",
    { installationId },
    { authorization: `Bearer ${sessionToken}` },
    stateFile
  );

  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
  assert.equal(first.body.connectionStatus, "connected");
  assert.equal(first.body.databaseId, second.body.databaseId);
});

test("bootstrap rejects requests without a session", async () => {
  const installationId = `install_${crypto.randomUUID()}`;
  const response = await callHandler("POST", "/v1/workspaces/bootstrap", { installationId });

  assert.equal(response.statusCode, 401);
  assert.equal(response.body.error, "unauthorized");
});

test("sync is idempotent for duplicate clientItemId", async () => {
  const stateFile = makeStateFile();
  const installationId = `install_${crypto.randomUUID()}`;
  const start = await callHandlerWithHeadersUsingState(
    "POST",
    "/v1/oauth/notion/start",
    { installationId },
    {},
    stateFile
  );
  const authorizeURL = new URL(start.body.authorizeUrl);
  const state = authorizeURL.searchParams.get("state");
  const callback = await callHandlerWithHeadersUsingState(
    "GET",
    `/v1/oauth/notion/callback?state=${state}`,
    null,
    {},
    stateFile
  );
  const callbackURL = new URL(callback.headers.Location);
  const sessionToken = callbackURL.searchParams.get("sessionToken");
  const bootstrap = await callHandlerWithHeadersUsingState(
    "POST",
    "/v1/workspaces/bootstrap",
    { installationId },
    { authorization: `Bearer ${sessionToken}` },
    stateFile
  );
  const payload = {
    clientItemId: crypto.randomUUID(),
    databaseId: bootstrap.body.databaseId,
    title: "Fast save",
    sourceURL: "https://threads.net/test",
    platform: "Threads",
    tags: ["pm"],
    memo: "memo",
    text: "body",
    status: "Synced",
    capturedAt: new Date().toISOString()
  };

  const headers = { authorization: `Bearer ${sessionToken}` };
  const first = await callHandlerWithHeadersUsingState("POST", "/v1/captures/sync", payload, headers, stateFile);
  const second = await callHandlerWithHeadersUsingState("POST", "/v1/captures/sync", payload, headers, stateFile);

  assert.equal(first.statusCode, 200);
  assert.equal(first.body.result, "created");
  assert.equal(second.body.result, "duplicate");
  assert.equal(first.body.notionPageId, second.body.notionPageId);
});

test("oauth callback rejects unknown state", async () => {
  const response = await callHandler("GET", "/v1/oauth/notion/callback?state=invalid");

  assert.equal(response.statusCode, 302);
  assert.equal(response.headers.Location, "kuri://oauth/notion?status=failed&reason=invalid_state");
});

test("sync rejects requests without a valid session", async () => {
  const payload = {
    clientItemId: crypto.randomUUID(),
    databaseId: "db-1",
    title: "Fast save",
    sourceURL: "https://threads.net/test",
    capturedAt: new Date().toISOString()
  };

  const response = await callHandler("POST", "/v1/captures/sync", payload);

  assert.equal(response.statusCode, 401);
  assert.equal(response.body.error, "unauthorized");
});

test("telemetry accepts samples and returns count", async () => {
  const response = await callHandler("POST", "/v1/telemetry/client-performance", {
    samples: [
      { metric: "sync_request", durationMs: 120, timestamp: new Date().toISOString() },
      { metric: "ocr_processing", durationMs: 340, timestamp: new Date().toISOString() }
    ]
  });

  assert.equal(response.statusCode, 202);
  assert.equal(response.body.accepted, 2);
});

test("unknown route returns 404", async () => {
  const response = await callHandler("GET", "/v1/nonexistent", null);

  assert.equal(response.statusCode, 404);
  assert.equal(response.body.error, "not_found");
});

test("NotionClient.buildPageBody builds correct request body", async () => {
  const client = new NotionClient("fake-token");
  const body = client.buildPageBody("db-123", {
    title: "Test Title",
    sourceUrl: "https://threads.net/test",
    platform: "Threads",
    tags: ["pm", "ai"],
    memo: "Test memo",
    text: "Shared text content",
    capturedAt: "2026-03-02T13:00:00Z"
  });

  assert.equal(body.parent.database_id, "db-123");
  assert.equal(body.properties.Name.title[0].text.content, "Test Title");
  assert.equal(body.properties.URL.url, "https://threads.net/test");
  assert.equal(body.properties.Platform.select.name, "Threads");
  assert.deepEqual(
    body.properties.Tags.multi_select.map(t => t.name),
    ["pm", "ai"]
  );
  assert.equal(body.properties.Memo.rich_text[0].text.content, "Test memo");
  assert.equal(body.properties.Text.rich_text[0].text.content, "Shared text content");
});

test("full flow: oauth -> bootstrap -> sync -> duplicate returns same pageId", async () => {
  const stateFile = makeStateFile();
  const installationId = `install_${crypto.randomUUID()}`;

  // OAuth start
  const start = await callHandlerWithHeadersUsingState(
    "POST", "/v1/oauth/notion/start", { installationId }, {}, stateFile
  );
  assert.equal(start.statusCode, 200);

  // OAuth callback
  const authorizeURL = new URL(start.body.authorizeUrl);
  const oauthState = authorizeURL.searchParams.get("state");
  const callback = await callHandlerWithHeadersUsingState(
    "GET", `/v1/oauth/notion/callback?state=${oauthState}`, null, {}, stateFile
  );
  const callbackURL = new URL(callback.headers.Location);
  const sessionToken = callbackURL.searchParams.get("sessionToken");
  assert.ok(sessionToken);

  // Bootstrap
  const bootstrap = await callHandlerWithHeadersUsingState(
    "POST", "/v1/workspaces/bootstrap", { installationId },
    { authorization: `Bearer ${sessionToken}` }, stateFile
  );
  assert.equal(bootstrap.statusCode, 200);
  const databaseId = bootstrap.body.databaseId;
  assert.ok(databaseId);

  // Sync
  const clientItemId = crypto.randomUUID();
  const headers = { authorization: `Bearer ${sessionToken}` };
  const payload = {
    clientItemId,
    databaseId,
    title: "E2E test",
    sourceURL: "https://threads.net/e2e",
    platform: "Threads",
    tags: ["e2e"],
    memo: "end to end",
    text: "full flow",
    status: "Synced",
    capturedAt: new Date().toISOString()
  };

  const sync1 = await callHandlerWithHeadersUsingState(
    "POST", "/v1/captures/sync", payload, headers, stateFile
  );
  assert.equal(sync1.statusCode, 200);
  assert.equal(sync1.body.result, "created");

  // Duplicate sync
  const sync2 = await callHandlerWithHeadersUsingState(
    "POST", "/v1/captures/sync", payload, headers, stateFile
  );
  assert.equal(sync2.body.result, "duplicate");
  assert.equal(sync2.body.notionPageId, sync1.body.notionPageId);
});

async function callHandlerWithHeaders(method, url, body, headers, stateFile = makeStateFile()) {
  return callHandlerWithHeadersUsingState(method, url, body, headers, stateFile);
}

async function callHandlerWithHeadersUsingState(method, url, body, headers, stateFile) {
  const payload = body ? Buffer.from(JSON.stringify(body)) : Buffer.alloc(0);
  const req = Readable.from(payload);
  req.method = method;
  req.url = url;
  req.headers = { "content-type": "application/json", ...headers };

  let raw = "";
  const res = new Writable({
    write(chunk, _encoding, callback) {
      raw += chunk.toString();
      callback();
    }
  });
  res.statusCode = 200;
  res.headers = {};
  res.writeHead = function writeHead(statusCode, responseHeaders) {
    this.statusCode = statusCode;
    this.headers = responseHeaders;
    return this;
  };
  res.end = function end(chunk) {
    if (chunk) raw += chunk.toString();
    this.emit("finish");
    return this;
  };

  const handler = createHandler({ stateFile });
  await handler(req, res);
  return {
    statusCode: res.statusCode,
    headers: res.headers,
    body: raw ? JSON.parse(raw) : null
  };
}

function makeStateFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "kuri-backend-test-"));
  return path.join(dir, "state.json");
}
