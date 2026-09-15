interface Env {
  GH_APP_ID: string;
  GH_INSTALLATION_ID: string;
  GH_PRIVATE_KEY: string;
  GITHUB_OWNER: string;
  GITHUB_REPO: string;
  REPORT_LIMITS: KVNamespace;
}

interface ReportPayload {
  category: string;
  summary: string;
  description: string;
  metadata: {
    tuimVersion?: string;
    os?: string;
    osVersion?: string;
    kernel?: string;
    architecture?: string;
    displayServer?: string;
    desktop?: string;
    terminal?: string;
    terminalVersion?: string;
    term?: string;
    shell?: string;
  };
  logs: string | null;
}

interface GitHubToken {
  token: string;
  expires_at: string;
}

let cachedToken: { value: string; expiresAt: number } | undefined;
const categories = new Set(["Editor", "Terminal", "Source control", "Extensions", "Performance", "Other"]);

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) { result.set(part, offset); offset += part.length; }
  return result;
}

function derLength(length: number): Uint8Array {
  if (length < 128) return Uint8Array.of(length);
  const bytes: number[] = [];
  for (let value = length; value > 0; value >>>= 8) bytes.unshift(value & 0xff);
  return Uint8Array.of(0x80 | bytes.length, ...bytes);
}

function der(tag: number, value: Uint8Array): Uint8Array {
  return concat(Uint8Array.of(tag), derLength(value.length), value);
}

function pemBytes(pem: string): Uint8Array {
  const normalized = pem.replace(/\\n/g, "\n");
  const isPkcs1 = normalized.includes("BEGIN RSA PRIVATE KEY");
  const body = normalized.replace(/-----BEGIN (?:RSA )?PRIVATE KEY-----|-----END (?:RSA )?PRIVATE KEY-----|\s/g, "");
  const binary = atob(body);
  const key = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  if (!isPkcs1) return key;

  // GitHub downloads PKCS#1 keys; WebCrypto imports PKCS#8. Wrap the RSA key
  // in a PrivateKeyInfo structure without ever exporting it from the Worker.
  const version = Uint8Array.of(0x02, 0x01, 0x00);
  const rsaAlgorithm = Uint8Array.of(0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00);
  return der(0x30, concat(version, rsaAlgorithm, der(0x04, key)));
}

async function appJwt(env: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: env.GH_APP_ID }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(env.GH_PRIVATE_KEY),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

async function installationToken(env: Env): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;
  const response = await fetch(`https://api.github.com/app/installations/${env.GH_INSTALLATION_ID}/access_tokens`, {
    method: "POST",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${await appJwt(env)}`,
      "User-Agent": "tuim-bug-report-gateway",
      "X-GitHub-Api-Version": "2026-03-10",
    },
    body: JSON.stringify({ repositories: [env.GITHUB_REPO], permissions: { issues: "write" } }),
  });
  if (!response.ok) throw new Error(`GitHub App authentication failed (${response.status})`);
  const result = (await response.json()) as GitHubToken;
  cachedToken = { value: result.token, expiresAt: Date.parse(result.expires_at) };
  return result.token;
}

function validReport(value: unknown): value is ReportPayload {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const report = value as Partial<ReportPayload>;
  const metadata = report.metadata as ReportPayload["metadata"] | undefined;
  const metadataValues = metadata ? [
    metadata.tuimVersion, metadata.os, metadata.osVersion, metadata.kernel,
    metadata.architecture, metadata.displayServer, metadata.desktop,
    metadata.terminal, metadata.terminalVersion, metadata.term, metadata.shell,
  ] : [];
  return (
    typeof report.category === "string" && categories.has(report.category) &&
    typeof report.summary === "string" && report.summary.trim().length >= 3 && report.summary.length <= 120 &&
    typeof report.description === "string" && report.description.trim().length >= 3 && report.description.length <= 6000 &&
    typeof metadata === "object" && metadata !== null && !Array.isArray(metadata) &&
    metadataValues.every((item) => item === undefined || (typeof item === "string" && item.length <= 160)) &&
    (report.logs === null || (typeof report.logs === "string" && report.logs.length <= 40_000))
  );
}

async function rateLimited(request: Request, env: Env): Promise<boolean> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(ip));
  const key = `hour:${new Date().toISOString().slice(0, 13)}:${base64url(new Uint8Array(digest))}`;
  const count = Number((await env.REPORT_LIMITS.get(key)) ?? "0");
  if (count >= 5) return true;
  await env.REPORT_LIMITS.put(key, String(count + 1), { expirationTtl: 7200 });
  return false;
}

function issueBody(report: ReportPayload): string {
  const safe = (value?: string) => (value || "unknown").replace(/[\r\n\t]+/g, " ").slice(0, 160);
  const terminal = `${safe(report.metadata.terminal)} ${safe(report.metadata.terminalVersion)}`.trim();
  const metadata = [
    `- TUIM: ${safe(report.metadata.tuimVersion)}`,
    `- OS: ${safe(report.metadata.osVersion)} (${safe(report.metadata.os)})`,
    `- Kernel: ${safe(report.metadata.kernel)}`,
    `- Architecture: ${safe(report.metadata.architecture)}`,
    `- Display server: ${safe(report.metadata.displayServer)}`,
    `- Desktop/session: ${safe(report.metadata.desktop)}`,
    `- Terminal: ${terminal} (TERM=${safe(report.metadata.term)})`,
    `- Shell: ${safe(report.metadata.shell)}`,
    `- Category: ${report.category}`,
    `- Debug logs authorized: ${report.logs !== null ? "yes" : "no"}`,
  ].join("\n");
  const logs = report.logs === null ? "" : `\n\n### Debug logs\n\n\`\`\`text\n${report.logs}\n\`\`\``;
  return `### Description\n\n${report.description}\n\n### Environment\n\n${metadata}${logs}\n\n---\nSubmitted from TUIM's in-app bug reporter.`;
}

async function createIssue(report: ReportPayload, env: Env): Promise<{ html_url: string; number: number }> {
  const response = await fetch(`https://api.github.com/repos/${env.GITHUB_OWNER}/${env.GITHUB_REPO}/issues`, {
    method: "POST",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${await installationToken(env)}`,
      "Content-Type": "application/json",
      "User-Agent": "tuim-bug-report-gateway",
      "X-GitHub-Api-Version": "2026-03-10",
    },
    body: JSON.stringify({ title: `[${report.category}] ${report.summary.trim()}`, body: issueBody(report) }),
  });
  if (!response.ok) throw new Error(`GitHub issue creation failed (${response.status})`);
  return (await response.json()) as { html_url: string; number: number };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "GET") return json({ service: "TUIM bug reporting", ready: true });
    if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
    if ((request.headers.get("Content-Type") ?? "").split(";", 1)[0] !== "application/json") return json({ error: "Expected JSON" }, 415);
    if (Number(request.headers.get("Content-Length") ?? "0") > 55_000) return json({ error: "Report too large" }, 413);
    if (await rateLimited(request, env)) return json({ error: "Too many reports; try again later" }, 429);

    const raw = await request.text();
    if (new TextEncoder().encode(raw).length > 55_000) return json({ error: "Report too large" }, 413);
    let payload: unknown;
    try { payload = JSON.parse(raw); } catch { return json({ error: "Invalid JSON" }, 400); }
    if (!validReport(payload)) return json({ error: "Invalid report" }, 422);

    try {
      const issue = await createIssue(payload, env);
      return json({ issueUrl: issue.html_url, issueNumber: issue.number }, 201);
    } catch (error) {
      console.error(error instanceof Error ? error.message : error);
      return json({ error: "Issue creation failed" }, 502);
    }
  },
} satisfies ExportedHandler<Env>;
