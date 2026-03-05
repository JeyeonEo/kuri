export class NotionClient {
  constructor(accessToken) {
    this.accessToken = accessToken;
    this.baseURL = "https://api.notion.com/v1";
    this.notionVersion = "2022-06-28";
  }

  buildPageBody(databaseId, capture) {
    const properties = {
      Name: { title: [{ text: { content: capture.title || "Untitled" } }] },
      Platform: { select: { name: capture.platform || "Unknown" } },
      Status: { select: { name: "Synced" } }
    };

    if (capture.sourceUrl) {
      properties.URL = { url: capture.sourceUrl };
    }

    if (capture.tags && capture.tags.length > 0) {
      properties.Tags = { multi_select: capture.tags.map(name => ({ name })) };
    }

    if (capture.memo) {
      properties.Memo = { rich_text: [{ text: { content: capture.memo } }] };
    }

    if (capture.text) {
      properties.Text = { rich_text: [{ text: { content: capture.text } }] };
    }

    if (capture.capturedAt) {
      properties["Captured At"] = { date: { start: capture.capturedAt } };
    }

    return { parent: { database_id: databaseId }, properties };
  }

  async searchPages() {
    const response = await fetch(`${this.baseURL}/search`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        "Notion-Version": this.notionVersion
      },
      body: JSON.stringify({
        filter: { property: "object", value: "page" },
        page_size: 1
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Notion API error ${response.status}: ${error}`);
    }

    const result = await response.json();
    return result.results;
  }

  async createRootPage(title = "KURI") {
    const response = await fetch(`${this.baseURL}/pages`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        "Notion-Version": this.notionVersion
      },
      body: JSON.stringify({
        parent: { type: "workspace", workspace: true },
        properties: {
          title: [{ text: { content: title } }]
        }
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Notion API error ${response.status}: ${error}`);
    }

    const result = await response.json();
    return result.id;
  }

  async createPage(databaseId, capture) {
    const body = this.buildPageBody(databaseId, capture);
    const response = await fetch(`${this.baseURL}/pages`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        "Notion-Version": this.notionVersion
      },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Notion API error ${response.status}: ${error}`);
    }

    const result = await response.json();
    return result.id;
  }

  async createDatabase(parentPageId, title = "KURI Captures") {
    const body = {
      parent: { type: "page_id", page_id: parentPageId },
      title: [{ text: { content: title } }],
      properties: {
        Name: { title: {} },
        URL: { url: {} },
        Platform: { select: { options: [
          { name: "Threads", color: "blue" },
          { name: "Instagram", color: "pink" },
          { name: "X", color: "gray" },
          { name: "Web", color: "green" },
          { name: "Unknown", color: "default" }
        ]}},
        Tags: { multi_select: {} },
        Memo: { rich_text: {} },
        Text: { rich_text: {} },
        Status: { select: { options: [
          { name: "Synced", color: "green" },
          { name: "Pending", color: "yellow" },
          { name: "Failed", color: "red" }
        ]}},
        "Captured At": { date: {} }
      }
    };

    const response = await fetch(`${this.baseURL}/databases`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        "Notion-Version": this.notionVersion
      },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Notion API error ${response.status}: ${error}`);
    }

    const result = await response.json();
    return result.id;
  }

  async exchangeOAuthCode(code, clientId, clientSecret, redirectUri) {
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    const response = await fetch("https://api.notion.com/v1/oauth/token", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${credentials}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        grant_type: "authorization_code",
        code,
        redirect_uri: redirectUri
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Notion OAuth error ${response.status}: ${error}`);
    }

    return response.json();
  }
}
