import crypto from "node:crypto";
import { NotionClient } from "./notion.js";
import { verifyAppleIdentityToken } from "./apple-auth.js";

const OAUTH_STATE_TTL_MS = 10 * 60 * 1000;
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_BODY_BYTES = 1024 * 1024; // 1 MB

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" }
  });
}

function redirectResponse(location) {
  return new Response(null, { status: 302, headers: { Location: location } });
}

async function readJSON(request) {
  const contentLength = request.headers.get("content-length");
  if (contentLength && parseInt(contentLength, 10) > MAX_BODY_BYTES) {
    throw Object.assign(new Error("payload_too_large"), { statusCode: 413 });
  }
  const body = await request.text();
  if (body.length > MAX_BODY_BYTES) {
    throw Object.assign(new Error("payload_too_large"), { statusCode: 413 });
  }
  return body ? JSON.parse(body) : {};
}

function bearerToken(request) {
  const header = request.headers.get("authorization");
  if (!header || !header.startsWith("Bearer ")) {
    return null;
  }
  return header.slice("Bearer ".length);
}

function validSession(state, token) {
  if (!token) return null;
  const session = state.sessions[token];
  if (!session) return null;
  const age = Date.now() - new Date(session.createdAt).getTime();
  if (age > SESSION_TTL_MS) {
    delete state.sessions[token];
    return null;
  }
  return session;
}

export function createMemoryStore() {
  let state = { captures: {}, workspaces: {}, sessions: {}, oauthStarts: {}, users: {} };
  let lock = Promise.resolve();

  return {
    async withLock(fn) {
      const next = lock.then(fn, () => fn());
      lock = next.catch(() => {});
      return next;
    },
    getState() {
      return state;
    },
    saveState(newState) {
      state = newState;
    }
  };
}

export function createWorkerHandler(env, store) {
  if (!store) {
    store = createMemoryStore();
  }

  return async function handler(request) {
    return store.withLock(async () => {
      const url = new URL(request.url);
      const state = store.getState();

      try {
        if (request.method === "POST" && url.pathname === "/v1/auth/apple") {
          const body = await readJSON(request);
          if (!body.identityToken || !body.installationId) {
            return jsonResponse(400, { error: "missing_fields" });
          }
          const bundleId = env.APPLE_BUNDLE_ID || "com.kuri.app";
          let appleUser;
          try {
            appleUser = await verifyAppleIdentityToken(body.identityToken, bundleId);
          } catch (err) {
            return jsonResponse(401, { error: "invalid_identity_token", message: err.message });
          }

          let userId = null;
          for (const [id, user] of Object.entries(state.users)) {
            if (user.appleUserId === appleUser.sub) {
              userId = id;
              break;
            }
          }
          if (!userId) {
            userId = `user_${crypto.randomUUID()}`;
            state.users[userId] = {
              appleUserId: appleUser.sub,
              email: appleUser.email,
              createdAt: new Date().toISOString()
            };
          }

          const installationId = body.installationId;
          const existingWorkspace = state.workspaces[installationId];
          if (existingWorkspace && !existingWorkspace.userId) {
            existingWorkspace.userId = userId;
          }

          const sessionToken = `session_${crypto.randomUUID()}`;
          state.sessions[sessionToken] = {
            installationId,
            userId,
            createdAt: new Date().toISOString()
          };
          store.saveState(state);

          return jsonResponse(200, {
            sessionToken,
            userId,
            email: appleUser.email
          });
        }

        if (request.method === "POST" && url.pathname === "/v1/oauth/notion/start") {
          const body = await readJSON(request);
          const installationId = body.installationId || crypto.randomUUID();
          const oauthState = `oauth_${crypto.randomUUID()}`;
          state.oauthStarts[oauthState] = {
            installationId,
            createdAt: new Date().toISOString()
          };
          store.saveState(state);

          if (env.NOTION_MODE === "live") {
            const clientId = env.NOTION_CLIENT_ID;
            const redirectUri = env.NOTION_REDIRECT_URI || "http://localhost:8787/v1/oauth/notion/callback";
            const authorizeUrl = `https://api.notion.com/v1/oauth/authorize?client_id=${clientId}&response_type=code&owner=user&redirect_uri=${encodeURIComponent(redirectUri)}&state=${encodeURIComponent(oauthState)}`;
            return jsonResponse(200, { authorizeUrl });
          }
          return jsonResponse(200, {
            authorizeUrl: `http://localhost:8787/v1/oauth/notion/callback?state=${encodeURIComponent(oauthState)}`
          });
        }

        if (request.method === "GET" && url.pathname === "/v1/oauth/notion/callback") {
          const oauthState = url.searchParams.get("state");
          if (!oauthState) {
            return redirectResponse("kuri://oauth/notion?status=failed&reason=missing_state");
          }
          const start = state.oauthStarts[oauthState];
          if (!start?.installationId) {
            return redirectResponse("kuri://oauth/notion?status=failed&reason=invalid_state");
          }
          const stateAge = Date.now() - new Date(start.createdAt).getTime();
          if (stateAge > OAUTH_STATE_TTL_MS) {
            delete state.oauthStarts[oauthState];
            store.saveState(state);
            return redirectResponse("kuri://oauth/notion?status=failed&reason=expired_state");
          }
          const installationId = start.installationId;
          delete state.oauthStarts[oauthState];

          const sessionToken = `session_${crypto.randomUUID()}`;
          let workspace;
          if (env.NOTION_MODE === "live") {
            const code = url.searchParams.get("code");
            if (!code) {
              return redirectResponse("kuri://oauth/notion?status=failed&reason=missing_code");
            }
            const notion = new NotionClient(null);
            const redirectUri = env.NOTION_REDIRECT_URI || "http://localhost:8787/v1/oauth/notion/callback";
            const tokenResponse = await notion.exchangeOAuthCode(
              code,
              env.NOTION_CLIENT_ID,
              env.NOTION_CLIENT_SECRET,
              redirectUri
            );
            workspace = state.workspaces[installationId] || {};
            workspace.notionAccessToken = tokenResponse.access_token;
            workspace.workspaceName = tokenResponse.workspace_name || "KURI Workspace";
            workspace.connectionStatus = "connected";
          } else {
            workspace = state.workspaces[installationId] || {
              databaseId: `db_${crypto.randomUUID()}`,
              workspaceName: "KURI Workspace",
              connectionStatus: "connected"
            };
          }
          state.workspaces[installationId] = workspace;
          state.sessions[sessionToken] = {
            installationId,
            createdAt: new Date().toISOString()
          };
          store.saveState(state);

          const redirectURL = new URL("kuri://oauth/notion");
          redirectURL.searchParams.set("status", "success");
          redirectURL.searchParams.set("sessionToken", sessionToken);
          redirectURL.searchParams.set("workspaceName", workspace.workspaceName);
          redirectURL.searchParams.set("databaseId", workspace.databaseId);
          return redirectResponse(redirectURL.toString());
        }

        if (request.method === "POST" && url.pathname === "/v1/workspaces/bootstrap") {
          const body = await readJSON(request);
          const workspaceId = body.installationId || "default-installation";
          const token = bearerToken(request);
          const session = validSession(state, token);
          if (!session || session.installationId !== workspaceId) {
            store.saveState(state);
            return jsonResponse(401, { error: "unauthorized" });
          }
          if (!state.workspaces[workspaceId]) {
            state.workspaces[workspaceId] = {
              databaseId: `db_${crypto.randomUUID()}`,
              workspaceName: "KURI Workspace",
              connectionStatus: "connected"
            };
          }
          const ws = state.workspaces[workspaceId];
          if (env.NOTION_MODE === "live" && ws.notionAccessToken && !ws.realDatabaseCreated) {
            const notion = new NotionClient(ws.notionAccessToken);
            const dbId = await notion.createDatabase(ws.rootPageId);
            ws.databaseId = dbId;
            ws.realDatabaseCreated = true;
          }
          store.saveState(state);
          const { notionAccessToken: _, ...publicWs } = ws;
          return jsonResponse(200, publicWs);
        }

        if (request.method === "POST" && url.pathname === "/v1/captures/sync") {
          const body = await readJSON(request);
          const token = bearerToken(request);
          const session = validSession(state, token);
          const workspace = session ? state.workspaces[session.installationId] : null;
          if (!session || !workspace || workspace.databaseId !== body.databaseId) {
            store.saveState(state);
            return jsonResponse(401, { error: "unauthorized" });
          }
          const key = body.clientItemId;
          if (typeof key !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(key)) {
            return jsonResponse(400, { error: "invalid_client_item_id" });
          }
          if (state.captures[key]) {
            return jsonResponse(200, {
              result: "duplicate",
              notionPageId: state.captures[key].notionPageId
            });
          }

          let notionPageId;
          if (env.NOTION_MODE === "live" && workspace.notionAccessToken) {
            const notion = new NotionClient(workspace.notionAccessToken);
            notionPageId = await notion.createPage(body.databaseId, {
              title: body.title,
              sourceUrl: body.sourceURL,
              platform: body.platform,
              tags: body.tags,
              memo: body.memo,
              text: body.text,
              capturedAt: body.capturedAt
            });
          } else {
            notionPageId = `page_${crypto.randomUUID()}`;
          }
          state.captures[key] = {
            notionPageId,
            databaseId: body.databaseId,
            title: body.title,
            url: body.sourceURL,
            createdAt: body.capturedAt
          };
          store.saveState(state);

          return jsonResponse(200, {
            result: "created",
            notionPageId
          });
        }

        if (request.method === "POST" && url.pathname === "/v1/telemetry/client-performance") {
          const token = bearerToken(request);
          const session = validSession(state, token);
          if (!session) {
            store.saveState(state);
            return jsonResponse(401, { error: "unauthorized" });
          }
          const body = await readJSON(request);
          return jsonResponse(202, {
            accepted: Array.isArray(body.samples) ? body.samples.length : 0
          });
        }

        if (request.method === "GET" && url.pathname === "/v1/health") {
          return jsonResponse(200, { status: "ok" });
        }

        return jsonResponse(404, { error: "not_found" });
      } catch (err) {
        if (err.statusCode === 413) {
          return jsonResponse(413, { error: "payload_too_large" });
        }
        return jsonResponse(500, { error: "internal" });
      }
    });
  };
}
