import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createWorkerHandler, createMemoryStore } from "./handler.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultDataDir = path.join(__dirname, "data");
const defaultStateFile = path.join(defaultDataDir, "state.json");

function createFileStore(stateFile) {
  let lock = Promise.resolve();

  function ensureState() {
    fs.mkdirSync(path.dirname(stateFile), { recursive: true });
    if (!fs.existsSync(stateFile)) {
      fs.writeFileSync(
        stateFile,
        JSON.stringify({ captures: {}, workspaces: {}, sessions: {}, oauthStarts: {}, users: {} }, null, 2),
        "utf8"
      );
    }
    const parsed = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    return {
      captures: parsed.captures || {},
      workspaces: parsed.workspaces || {},
      sessions: parsed.sessions || {},
      oauthStarts: parsed.oauthStarts || {},
      users: parsed.users || {}
    };
  }

  return {
    async withLock(fn) {
      const next = lock.then(fn, () => fn());
      lock = next.catch(() => {});
      return next;
    },
    getState() {
      return ensureState();
    },
    saveState(state) {
      fs.writeFileSync(stateFile, JSON.stringify(state, null, 2), "utf8");
    }
  };
}

async function collectBody(req) {
  const chunks = [];
  let totalBytes = 0;
  for await (const chunk of req) {
    totalBytes += chunk.length;
    if (totalBytes > 1024 * 1024) {
      throw Object.assign(new Error("payload_too_large"), { statusCode: 413 });
    }
    chunks.push(chunk);
  }
  return chunks.length ? Buffer.concat(chunks) : null;
}

export function createHandler(options = {}) {
  const stateFile = options.stateFile ?? defaultStateFile;
  const env = {
    NOTION_CLIENT_ID: process.env.NOTION_CLIENT_ID,
    NOTION_CLIENT_SECRET: process.env.NOTION_CLIENT_SECRET,
    NOTION_REDIRECT_URI: process.env.NOTION_REDIRECT_URI,
    NOTION_MODE: process.env.NOTION_MODE,
    APPLE_BUNDLE_ID: process.env.APPLE_BUNDLE_ID,
    ...options.env
  };

  const store = createFileStore(stateFile);
  const workerHandler = createWorkerHandler(env, store);

  return async function handler(req, res) {
    try {
      const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);
      const bodyBuffer = req.method !== "GET" && req.method !== "HEAD"
        ? await collectBody(req) : null;

      const webRequest = new Request(url.toString(), {
        method: req.method,
        headers: req.headers,
        body: bodyBuffer
      });

      const webResponse = await workerHandler(webRequest);

      const headers = {};
      webResponse.headers.forEach((value, key) => {
        // Preserve header casing expected by consumers (e.g. Location, Content-Type)
        if (key === "location") headers["Location"] = value;
        else if (key === "content-type") headers["Content-Type"] = value;
        else headers[key] = value;
      });
      res.writeHead(webResponse.status, headers);
      const responseBody = await webResponse.text();
      res.end(responseBody);
    } catch (err) {
      if (err.statusCode === 413) {
        res.writeHead(413, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "payload_too_large" }));
      } else {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "internal" }));
      }
    }
  };
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectRun) {
  const port = Number(process.env.PORT || 8787);
  const server = http.createServer(createHandler());
  server.listen(port, () => {
    console.log(`KURI backend listening on http://localhost:${port}`);
  });
}
