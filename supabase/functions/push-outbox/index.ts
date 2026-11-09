import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type InboxNotification = {
  id?: string;
  ts?: number | string;
  recipientUserId?: string | null;
  type?: string;
  title?: string;
  message?: string;
  refType?: string | null;
  refId?: string | null;
  read?: Record<string, number | null>;
};
type UserRow = Record<string, unknown>;
type Delivery = {
  delivery_key: string;
  notification_id: string;
  user_id: string;
  title: string;
  body: string;
  type: string;
  refType: string;
  refId: string;
};
type Device = { token_hash: string; token: string; app_user_id: string; platform: string };
type Target = { item: Delivery; device: Device; receipt_key: string };
type ServiceAccount = { project_id: string; client_email: string; private_key: string; token_uri?: string };
type SendResult = { receiptKey: string; tokenHash: string; ok: boolean; unregistered: boolean; errorCode: string };

const receiptTable = "push_delivery_receipts";
const encoder = new TextEncoder();
let accessToken = "";
let accessTokenUntil = 0;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function textWithinUtf8Limit(value: unknown, maxBytes: number): string {
  let result = "";
  let used = 0;
  for (const character of String(value ?? "")) {
    const size = encoder.encode(character).length;
    if (used + size > maxBytes - 3) return result + "…";
    result += character;
    used += size;
  }
  return result;
}

function stateFromRecord(record: Record<string, unknown> | null): Record<string, unknown> {
  if (!record) return {};
  const content = record.content;
  if (typeof content === "string") {
    try { return JSON.parse(content); } catch { return {}; }
  }
  return content && typeof content === "object" ? content as Record<string, unknown> : {};
}

function b64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function getFcmAccessToken(account: ServiceAccount): Promise<string> {
  if (accessToken && Date.now() < accessTokenUntil - 60_000) return accessToken;
  const tokenUri = account.token_uri || "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }))}`;
  const pem = account.private_key.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    decodeBase64(pem),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(unsigned));
  const assertion = `${unsigned}.${b64url(new Uint8Array(signature))}`;
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || typeof result.access_token !== "string") {
    console.error("Google OAuth rejected the FCM service account.", response.status);
    throw new Error("FCM service authorization failed.");
  }
  accessToken = result.access_token;
  accessTokenUntil = Date.now() + Number(result.expires_in || 3600) * 1000;
  return accessToken;
}

async function claimTargets(db: ReturnType<typeof createClient>, targets: Target[]): Promise<Set<string>> {
  if (!targets.length) return new Set();
  const now = new Date().toISOString();
  const claimed = new Set<string>();
  for (let start = 0; start < targets.length; start += 500) {
    const batch = targets.slice(start, start + 500);
    const { data, error } = await db.from(receiptTable).upsert(batch.map((target) => ({
      delivery_key: target.receipt_key,
      notification_id: target.item.notification_id,
      status: "processing",
      updated_at: now,
    })), { onConflict: "delivery_key", ignoreDuplicates: true }).select("delivery_key");
    if (error) throw error;
    for (const row of data ?? []) claimed.add(String(row.delivery_key));

    const retryKeys = batch.map((target) => target.receipt_key).filter((key) => !claimed.has(key));
    for (let retryStart = 0; retryStart < retryKeys.length; retryStart += 500) {
      const retryBatch = retryKeys.slice(retryStart, retryStart + 500);
      const { data: retried, error: retryError } = await db.from(receiptTable)
        .update({ status: "processing", last_error: null, updated_at: now })
        .in("delivery_key", retryBatch).eq("status", "failed").select("delivery_key");
      if (retryError) throw retryError;
      for (const row of retried ?? []) claimed.add(String(row.delivery_key));
      const staleBefore = new Date(Date.now() - 15 * 60 * 1000).toISOString();
      const { data: recovered, error: recoveryError } = await db.from(receiptTable)
        .update({ status: "processing", last_error: null, updated_at: now })
        .in("delivery_key", retryBatch).eq("status", "processing")
        .lt("updated_at", staleBefore).select("delivery_key");
      if (recoveryError) throw recoveryError;
      for (const row of recovered ?? []) claimed.add(String(row.delivery_key));
    }
  }
  return claimed;
}

async function updateReceipts(
  db: ReturnType<typeof createClient>,
  targets: Target[],
  status: "sent" | "failed",
  lastError: string | null,
): Promise<void> {
  for (let start = 0; start < targets.length; start += 500) {
    const keys = targets.slice(start, start + 500).map((target) => target.receipt_key);
    const { error } = await db.from(receiptTable).update({
      status,
      provider_message_id: null,
      last_error: lastError,
      updated_at: new Date().toISOString(),
    }).in("delivery_key", keys);
    if (error) throw error;
  }
}

async function mapLimit<T, R>(items: T[], limit: number, work: (item: T) => Promise<R>): Promise<R[]> {
  const output = new Array<R>(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (true) {
      const index = next++;
      if (index >= items.length) return;
      output[index] = await work(items[index]);
    }
  });
  await Promise.all(workers);
  return output;
}

function fcmErrorCode(body: Record<string, unknown>): string {
  const error = body.error && typeof body.error === "object" ? body.error as Record<string, unknown> : {};
  const details = Array.isArray(error.details) ? error.details as Array<Record<string, unknown>> : [];
  const item = details.find((detail) => typeof detail.errorCode === "string");
  return String(item?.errorCode ?? error.status ?? "FCM_ERROR");
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
  const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
  const suppliedSecret = request.headers.get("x-push-webhook-secret") ?? "";
  if (expectedSecret.length < 32 || !constantTimeEqual(suppliedSecret, expectedSecret)) {
    return json({ error: "unauthorized webhook" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const serviceAccountJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";
  if (!supabaseUrl || !serviceRoleKey || !serviceAccountJson) {
    console.error("Push outbox needs the Firebase service account secret.");
    return json({ error: "FCM push service is not configured" }, 503);
  }

  let account: ServiceAccount;
  try {
    account = JSON.parse(serviceAccountJson) as ServiceAccount;
    if (account.project_id !== "jsk-attendance" || !account.client_email || !account.private_key) throw new Error("incomplete or wrong Firebase project");
  } catch {
    console.error("FCM service account JSON is invalid.");
    return json({ error: "FCM push service is not configured" }, 503);
  }

  let webhook: Record<string, unknown>;
  try { webhook = await request.json(); } catch { return json({ error: "invalid JSON" }, 400); }
  const eventType = String(webhook.type ?? "").toUpperCase();
  if (webhook.schema !== "public" || webhook.table !== "app_data" || !["INSERT", "UPDATE"].includes(eventType)) {
    return json({ ignored: true });
  }
  const record = webhook.record && typeof webhook.record === "object"
    ? webhook.record as Record<string, unknown>
    : null;
  if (!record || record.id !== "main_state") return json({ ignored: true });

  const state = stateFromRecord(record);
  const inbox = Array.isArray(state.inbox) ? state.inbox as InboxNotification[] : [];
  const users = Array.isArray(state.users) ? state.users as UserRow[] : [];
  const userById = new Map(users.filter((user) => user && user.id != null).map((user) => [String(user.id), user]));
  const now = Date.now();
  const candidates: Delivery[] = [];
  for (const notification of inbox) {
    const userId = notification?.recipientUserId ? String(notification.recipientUserId) : "";
    const user = userById.get(userId);
    if (!notification?.id || !userId || !user || user.phoneNotifs !== true || user.ghost === true || user.demoAccount === true) continue;
    if (notification.read && notification.read[userId]) continue;
    const createdAt = Number(notification.ts ?? 0);
    if (createdAt && now - createdAt > 7 * 24 * 60 * 60 * 1000) continue;
    candidates.push({
      delivery_key: `${notification.id}:${String(notification.ts ?? 0)}`,
      notification_id: String(notification.id),
      user_id: userId,
      title: textWithinUtf8Limit(notification.title || "JSK Attendance", 180),
      body: textWithinUtf8Limit(notification.message || "You have a new JSK Attendance update.", 2800),
      type: String(notification.type ?? ""),
      refType: String(notification.refType ?? ""),
      refId: String(notification.refId ?? ""),
    });
  }
  if (!candidates.length) return json({ accepted: true, queued: 0, sent: 0, devices: 0 });

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    // The rollout migration marks old inbox entries as `existing`; keep them
    // suppressed even though new receipts are tracked separately per device.
    const historicalIds = new Set<string>();
    const notificationIds = [...new Set(candidates.map((item) => item.notification_id))];
    for (let start = 0; start < notificationIds.length; start += 500) {
      const { data, error } = await db.from(receiptTable).select("notification_id")
        .eq("status", "existing").in("notification_id", notificationIds.slice(start, start + 500));
      if (error) throw error;
      for (const row of data ?? []) historicalIds.add(String(row.notification_id));
    }
    const freshCandidates = candidates.filter((item) => !historicalIds.has(item.notification_id));
    if (!freshCandidates.length) return json({ accepted: true, queued: 0, sent: 0, devices: 0 });

    const userIds = [...new Set(freshCandidates.map((item) => item.user_id))];
    const devices: Device[] = [];
    for (let start = 0; start < userIds.length; start += 500) {
      const { data, error } = await db.from("jsk_push_tokens")
        .select("token_hash,token,app_user_id,platform")
        .in("app_user_id", userIds.slice(start, start + 500));
      if (error) throw error;
      devices.push(...(data ?? []) as Device[]);
    }
    const devicesByUser = new Map<string, Device[]>();
    for (const device of devices) {
      const list = devicesByUser.get(device.app_user_id) ?? [];
      list.push(device);
      devicesByUser.set(device.app_user_id, list);
    }
    const targets: Target[] = freshCandidates.flatMap((item) =>
      (devicesByUser.get(item.user_id) ?? []).map((device) => ({
        item,
        device,
        receipt_key: `${item.delivery_key}:${device.token_hash}`,
      })),
    );
    if (!targets.length) return json({ accepted: true, queued: 0, sent: 0, devices: 0 });

    const claimedKeys = await claimTargets(db, targets);
    const claimed = targets.filter((target) => claimedKeys.has(target.receipt_key));
    if (!claimed.length) return json({ accepted: true, queued: 0, sent: 0, devices: targets.length });

    const googleToken = await getFcmAccessToken(account);
    const linkFor = (item: Delivery) => {
      const url = new URL("https://jsk-attendance.web.app/");
      url.searchParams.set("jskPush", "1");
      url.searchParams.set("notificationId", item.notification_id);
      url.searchParams.set("type", item.type);
      url.searchParams.set("refType", item.refType);
      url.searchParams.set("refId", item.refId);
      return url.toString();
    };
    const results = await mapLimit(claimed, 80, async ({ item, device, receipt_key }): Promise<SendResult> => {
      const data: Record<string, string> = {
        notificationId: item.notification_id,
        screen: "notifications",
        type: item.type,
        refType: item.refType,
        refId: item.refId,
      };
      try {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
          method: "POST",
          headers: { authorization: `Bearer ${googleToken}`, "content-type": "application/json" },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: { title: item.title, body: item.body },
              data,
              android: {
                priority: "HIGH",
                notification: { channel_id: "jsk_updates", sound: "default" },
              },
              webpush: {
                headers: { Urgency: "high" },
                notification: {
                  icon: "/assets/jsk-attendance-logo.png",
                  badge: "/assets/jsk-attendance-logo.png",
                  tag: item.delivery_key,
                  data,
                },
                fcm_options: { link: linkFor(item) },
              },
            },
          }),
        });
        if (response.ok) return { receiptKey: receipt_key, tokenHash: device.token_hash, ok: true, unregistered: false, errorCode: "" };
        const body = await response.json().catch(() => ({})) as Record<string, unknown>;
        const code = fcmErrorCode(body);
        return {
          receiptKey: receipt_key,
          tokenHash: device.token_hash,
          ok: false,
          unregistered: code === "UNREGISTERED",
          errorCode: code,
        };
      } catch {
        return { receiptKey: receipt_key, tokenHash: device.token_hash, ok: false, unregistered: false, errorCode: "NETWORK_ERROR" };
      }
    });

    const unregistered = [...new Set(results.filter((result) => result.unregistered).map((result) => result.tokenHash))];
    for (let start = 0; start < unregistered.length; start += 500) {
      const { error } = await db.from("jsk_push_tokens").delete().in("token_hash", unregistered.slice(start, start + 500));
      if (error) throw error;
    }
    const successfulKeys = new Set(results.filter((result) => result.ok).map((result) => result.receiptKey));
    const sentTargets = claimed.filter((target) => successfulKeys.has(target.receipt_key));
    const failedTargets = claimed.filter((target) => !successfulKeys.has(target.receipt_key));
    await updateReceipts(db, sentTargets, "sent", null);
    const failuresByCode = new Map<string, Target[]>();
    const targetByReceiptKey = new Map(claimed.map((target) => [target.receipt_key, target]));
    for (const result of results.filter((item) => !item.ok)) {
      const target = targetByReceiptKey.get(result.receiptKey);
      if (!target) continue;
      const group = failuresByCode.get(result.errorCode) ?? [];
      group.push(target);
      failuresByCode.set(result.errorCode, group);
    }
    for (const [code, failed] of failuresByCode) {
      await updateReceipts(db, failed, "failed", `FCM ${code}; retry on a later notification sync.`);
    }
    const sentMessages = new Set(sentTargets.map((target) => target.item.notification_id));
    return json({ accepted: true, queued: claimed.length, sent: sentMessages.size, failed: failedTargets.length, devices: targets.length });
  } catch (error) {
    console.error("FCM push outbox processing failed.", error instanceof Error ? error.name : "unknown error");
    return json({ error: "FCM push outbox processing failed" }, 500);
  }
});
