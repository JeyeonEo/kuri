import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultDataDir = path.join(__dirname, "data");
const defaultStateFile = path.join(defaultDataDir, "state.json");

function ensureState(stateFile) {
  fs.mkdirSync(path.dirname(stateFile), { recursive: true });
  if (!fs.existsSync(stateFile)) {
    fs.writeFileSync(
      stateFile,
      JSON.stringify({ captures: {}, workspaces: {}, sessions: {}, oauthStarts: {} }, null, 2),
      "utf8"
    );
  }
  const parsed = JSON.parse(fs.readFileSync(stateFile, "utf8"));
  return {
    captures: parsed.captures || {},
    workspaces: parsed.workspaces || {},
    sessions: parsed.sessions || {},
    oauthStarts: parsed.oauthStarts || {}
  };
}

function saveState(stateFile, state) {
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 2), "utf8");
}

function json(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

function redirect(res, location) {
  res.writeHead(302, { Location: location });
  res.end();
}

function bearerToken(req) {
  const header = req.headers.authorization || req.headers.Authorization;
  if (!header || !header.startsWith("Bearer ")) {
    return null;
  }
  return header.slice("Bearer ".length);
}

export function createHandler(options = {}) {
  const stateFile = options.stateFile ?? defaultStateFile;
  return async function handler(req, res) {
    const url = new URL(req.url, "http://localhost");
    const state = ensureState(stateFile);

    if (req.method === "POST" && url.pathname === "/v1/oauth/notion/start") {
      const body = await readJSON(req);
      const installationId = body.installationId || crypto.randomUUID();
      const oauthState = `oauth_${crypto.randomUUID()}`;
      state.oauthStarts[oauthState] = {
        installationId,
        createdAt: new Date().toISOString()
      };
      saveState(stateFile, state);
      return json(res, 200, {
        authorizeUrl: `http://localhost:8787/v1/oauth/notion/callback?state=${encodeURIComponent(oauthState)}`
      });
    }

    if (req.method === "GET" && url.pathname === "/v1/oauth/notion/callback") {
      const oauthState = url.searchParams.get("state");
      if (!oauthState) {
        return redirect(res, "kuri://oauth/notion?status=failed&reason=missing_state");
      }
      const start = state.oauthStarts[oauthState];
      if (!start?.installationId) {
        return redirect(res, "kuri://oauth/notion?status=failed&reason=invalid_state");
      }
      const installationId = start.installationId;
      delete state.oauthStarts[oauthState];

      const sessionToken = `session_${crypto.randomUUID()}`;
      const workspace = state.workspaces[installationId] || {
        databaseId: `db_${crypto.randomUUID()}`,
        workspaceName: "KURI Workspace",
        connectionStatus: "connected"
      };
      state.workspaces[installationId] = workspace;
      state.sessions[sessionToken] = {
        installationId,
        createdAt: new Date().toISOString()
      };
      saveState(stateFile, state);

      const redirectURL = new URL("kuri://oauth/notion");
      redirectURL.searchParams.set("status", "success");
      redirectURL.searchParams.set("sessionToken", sessionToken);
      redirectURL.searchParams.set("workspaceName", workspace.workspaceName);
      redirectURL.searchParams.set("databaseId", workspace.databaseId);
      return redirect(res, redirectURL.toString());
    }

    if (req.method === "POST" && url.pathname === "/v1/workspaces/bootstrap") {
      const body = await readJSON(req);
      const workspaceId = body.installationId || "default-installation";
      const token = bearerToken(req);
      const session = token ? state.sessions[token] : null;
      if (!session || session.installationId !== workspaceId) {
        return json(res, 401, { error: "unauthorized" });
      }
      if (!state.workspaces[workspaceId]) {
        state.workspaces[workspaceId] = {
          databaseId: `db_${crypto.randomUUID()}`,
          workspaceName: "KURI Workspace",
          connectionStatus: "connected"
        };
      }
      saveState(stateFile, state);
      return json(res, 200, state.workspaces[workspaceId]);
    }

    if (req.method === "POST" && url.pathname === "/v1/captures/sync") {
      const body = await readJSON(req);
      const token = bearerToken(req);
      const session = token ? state.sessions[token] : null;
      const workspace = session ? state.workspaces[session.installationId] : null;
      if (!session || !workspace || workspace.databaseId !== body.databaseId) {
        return json(res, 401, { error: "unauthorized" });
      }
      const key = body.clientItemId;
      if (state.captures[key]) {
        return json(res, 200, {
          result: "duplicate",
          notionPageId: state.captures[key].notionPageId
        });
      }

      const notionPageId = `page_${crypto.randomUUID()}`;
      state.captures[key] = {
        notionPageId,
        databaseId: body.databaseId,
        title: body.title,
        url: body.sourceURL,
        createdAt: body.capturedAt
      };
      saveState(stateFile, state);

      return json(res, 200, {
        result: "created",
        notionPageId
      });
    }

    if (req.method === "POST" && url.pathname === "/v1/telemetry/client-performance") {
      const body = await readJSON(req);
      return json(res, 202, {
        accepted: Array.isArray(body.samples) ? body.samples.length : 0
      });
    }

    return json(res, 404, { error: "not_found" });
  };
}

async function readJSON(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}

const isDirectRun = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectRun) {
  const port = Number(process.env.PORT || 8787);
  const server = http.createServer(createHandler());
  server.listen(port, () => {
    console.log(`KURI backend listening on http://localhost:${port}`);
  });
}
