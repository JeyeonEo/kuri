import { createWorkerHandler } from "./handler.js";

export default {
  async fetch(request, env) {
    return createWorkerHandler(env)(request);
  }
};
