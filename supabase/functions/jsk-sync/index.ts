import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

type Row = Record<string, unknown>;
type AppProfile = { auth_user_id: string; app_user_id: string; role: string; active: boolean };

const URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const db: SupabaseClient = createClient(URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};
const ROLES = new Set(["admin", "staff", "teacher", "student", "guardian"]);
const APP_USER_SAFE_FIELDS = new Set([
  "phoneNotifs", "notifPrompted", "notifyMessages", "notifyNotices", "notifySound", "photo",
]);
const STUDENT_SELF_FIELDS = new Set(["phone", "email", "address", "city", "dob", "bloodGroup"]);
const STAFF_RECORD_FIELDS = [
  "date", "inTs", "outTs", "inDist", "outDist", "inAcc", "outAcc", "inEdge", "outEdge",
  "late", "lateMin", "shift", "staffId", "userId",
];
const ATTENDANCE_FIELDS = ["date", "studentId", "batchId", "subjectId", "status", "corrCount"];

function reply(status: number, body: Row): Response {
  return new Response(JSON.stringify(body), { status, headers: CORS });
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

function arr(value: unknown): Row[] {
  return Array.isArray(value) ? value.filter((x): x is Row => !!x && typeof x === "object" && !Array.isArray(x)) : [];
}

function text(value: unknown): string {
  return value == null ? "" : String(value);
}

function isLiveLegacyAccount(user: Row): boolean {
  return !user.ghost && !user.demoAccount && ROLES.has(text(user.role)) &&
    !!text(user.id) && !!text(user.email);
}

function cleanUser(user: Row): Row {
  const copy = { ...user };
  delete copy.password;
  delete copy.ghost;
  delete copy.demoAccount;
  return copy;
}

function cleanState(source: Row): Row {
  const state = clone(source);
  state.users = arr(state.users).filter(isLiveLegacyAccount).map(cleanUser);
  state.session = null;
  if (state.ui && typeof state.ui === "object") {
    const ui = state.ui as Row;
    delete ui.lastAdminInvite;
    delete ui.loc;
  }
  return state;
}

async function readMainState(): Promise<Row> {
  const { data, error } = await db.from("app_data").select("content").eq("id", "main_state").maybeSingle();
  if (error) throw error;
  if (!data?.content || typeof data.content !== "object") throw new Error("JSK data is not available.");
  return clone(data.content as Row);
}

async function writeMainState(content: Row): Promise<void> {
  const { error } = await db.from("app_data").upsert({ id: "main_state", content });
  if (error) throw error;
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function provisionLegacyAccount(email: string, password: string, skipBootstrapLimit = false): Promise<Row> {
  const normalizedEmail = email.toLowerCase().trim();
  const emailHash = await sha256(normalizedEmail);
  if (!skipBootstrapLimit) {
    const { data: allowed, error: limitError } = await db.rpc("jsk_consume_auth_bootstrap_attempt", {
      p_email_hash: emailHash,
    });
    if (limitError) throw limitError;
    if (!allowed) return { ok: false, code: "rate_limited" };
  }

  const state = await readMainState();
  const security = state.security && typeof state.security === "object"
    ? state.security as Row
    : {};
  // Legacy sign-in is a one-time migration bridge only. Once Admin completes
  // the Auth cutover and removes the shared password copies, never accept a
  // later client request to recreate an Auth account from legacy data.
  if (security.authOnlyPasswords === true) {
    return { ok: false, code: "invalid_credentials" };
  }

  const matchingUser = arr(state.users).find((u) => isLiveLegacyAccount(u) &&
    text(u.email).toLowerCase().trim() === normalizedEmail && text(u.password) === password);
  if (!matchingUser) return { ok: false, code: "invalid_credentials" };
  const appUserId = text(matchingUser.id);
  const role = text(matchingUser.role);
  if (!ROLES.has(role) || password.length < 6) return { ok: false, code: "invalid_credentials" };

  const mapped = await accountFor(appUserId);
  if (mapped) {
    // The client already tried Supabase Auth. Never let a saved legacy password
    // overwrite a mapped account's current Auth password.
    return { ok: false, code: "invalid_credentials" };
  }

  const authFields = {
    email: normalizedEmail,
    password,
    email_confirm: true,
    app_metadata: { jsk_app_user_id: appUserId, jsk_role: role },
    user_metadata: { full_name: text(matchingUser.name) },
  };
  let authUser;
  const { data: created, error: createError } = await db.auth.admin.createUser(authFields);
  if (createError && /already|registered|exists/i.test(createError.message)) {
    // Recover an interrupted migration only if the existing Auth user is already
    // bound to this exact JSK record and role.
    let match;
    for (let page = 1; !match; page++) {
      const { data: listed, error: listError } = await db.auth.admin.listUsers({ page, perPage: 1000 });
      if (listError) throw listError;
      const users = listed.users ?? [];
      match = users.find((u) => text(u.email).toLowerCase() === normalizedEmail);
      if (match || users.length < 1000) break;
    }
    if (!match || text(match.app_metadata?.jsk_app_user_id) !== appUserId ||
        text(match.app_metadata?.jsk_role) !== role) {
      return { ok: false, code: "account_conflict" };
    }
    authUser = match;
  } else if (createError) {
    throw new Error("Could not activate this JSK account.");
  } else {
    authUser = created.user;
  }
  const profileValues = {
    auth_user_id: authUser.id,
    app_user_id: appUserId,
    role,
    active: true,
    updated_at: new Date().toISOString(),
  };
  const { error: profileError } = await db.from("jsk_auth_profiles").upsert(profileValues);
  if (profileError) throw profileError;

  if (!skipBootstrapLimit) {
    const { error: clearLimitError } = await db.from("jsk_auth_bootstrap_limits").delete().eq("email_hash", emailHash);
    if (clearLimitError) console.warn("legacy-login rate-limit cleanup failed");
  }
  return { ok: true, provisioned: true };
}

function stripStoredPasswords(source: Row): Row {
  const state = clone(source);
  state.users = arr(state.users).map((user) => {
    const safe = clone(user);
    delete safe.password;
    return safe;
  });
  state.session = null;
  if (state.ui && typeof state.ui === "object") {
    const ui = state.ui as Row;
    delete ui.lastAdminInvite;
    delete ui.loc;
  }
  return state;
}

async function secureLegacyAccounts(profile: AppProfile): Promise<Row> {
  if (profile.role !== "admin") throw new Error("Only an Admin can secure existing accounts.");
  const state = await readMainState();
  const live = arr(state.users).filter(isLiveLegacyAccount);
  const failures: Row[] = [];
  let migrated = 0;
  let alreadyMapped = 0;

  for (const user of live) {
    const appUserId = text(user.id);
    const mapped = await accountFor(appUserId);
    if (mapped?.active && mapped.app_user_id === appUserId && mapped.role === text(user.role)) {
      const { data, error } = await db.auth.admin.getUserById(mapped.auth_user_id);
      const authUser = data?.user;
      if (error || !authUser || text(authUser.email).toLowerCase().trim() !== text(user.email).toLowerCase().trim()) {
        failures.push({ id: appUserId, role: text(user.role), code: "auth_email_mismatch" });
        continue;
      }

      const appMetadata = authUser.app_metadata ?? {};
      const existingAppUserId = text(appMetadata.jsk_app_user_id);
      const existingRole = text(appMetadata.jsk_role);
      if ((existingAppUserId && existingAppUserId !== appUserId) ||
          (existingRole && existingRole !== text(user.role))) {
        failures.push({ id: appUserId, role: text(user.role), code: "auth_metadata_conflict" });
        continue;
      }

      if (existingAppUserId !== appUserId || existingRole !== text(user.role)) {
        const { data: updated, error: updateError } = await db.auth.admin.updateUserById(authUser.id, {
          app_metadata: {
            ...appMetadata,
            jsk_app_user_id: appUserId,
            jsk_role: text(user.role),
          },
        });
        const updatedUser = updated?.user;
        if (updateError || !updatedUser ||
            text(updatedUser.app_metadata?.jsk_app_user_id) !== appUserId ||
            text(updatedUser.app_metadata?.jsk_role) !== text(user.role)) {
          failures.push({ id: appUserId, role: text(user.role), code: "auth_metadata_update_failed" });
        } else {
          alreadyMapped++;
        }
      } else {
        alreadyMapped++;
      }
      continue;
    }
    const password = text(user.password);
    if (password.length < 6) {
      failures.push({ id: appUserId, role: text(user.role), code: "missing_legacy_password" });
      continue;
    }
    const result = await provisionLegacyAccount(text(user.email), password, true);
    if (result.ok === true) migrated++;
    else failures.push({ id: appUserId, role: text(user.role), code: text(result.code) || "provision_failed" });
  }

  if (failures.length) {
    return { ok: false, code: "accounts_need_attention", migrated, alreadyMapped, failures };
  }

  const latest = await readMainState();
  const latestLive = arr(latest.users).filter(isLiveLegacyAccount);
  const unmapped: Row[] = [];
  for (const user of latestLive) {
    const mapped = await accountFor(text(user.id));
    if (!mapped?.active || mapped.app_user_id !== text(user.id) || mapped.role !== text(user.role)) {
      unmapped.push({ id: text(user.id), role: text(user.role) });
      continue;
    }
    const { data, error } = await db.auth.admin.getUserById(mapped.auth_user_id);
    if (error || !data.user || text(data.user.email).toLowerCase().trim() !== text(user.email).toLowerCase().trim() || text(data.user.app_metadata?.jsk_app_user_id) !== text(user.id) || text(data.user.app_metadata?.jsk_role) !== text(user.role)) {
      unmapped.push({ id: text(user.id), role: text(user.role) });
    }
  }
  if (unmapped.length) {
    return { ok: false, code: "verification_failed", migrated, alreadyMapped, failures: unmapped };
  }

  const secured = stripStoredPasswords(latest);
  secured.security = {
    ...((secured.security && typeof secured.security === "object") ? secured.security as Row : {}),
    authOnlyPasswords: true,
    passwordsSecuredAt: new Date().toISOString(),
  };
  await writeMainState(secured);
  return {
    ok: true,
    migrated,
    alreadyMapped,
    total: latestLive.length,
    content: roleView(secured, profile),
    profile: { id: profile.app_user_id, role: profile.role },
  };
}

function newTemporaryPassword(): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#$%_-";
  const all = upper + lower + digits + symbols;
  const bytes = crypto.getRandomValues(new Uint8Array(28));
  const chars = [
    upper[bytes[0] % upper.length],
    lower[bytes[1] % lower.length],
    digits[bytes[2] % digits.length],
    symbols[bytes[3] % symbols.length],
    ...Array.from(bytes.slice(4), (byte) => all[byte % all.length]),
  ];
  for (let i = chars.length - 1; i > 0; i--) {
    const swap = crypto.getRandomValues(new Uint32Array(1))[0] % (i + 1);
    [chars[i], chars[swap]] = [chars[swap], chars[i]];
  }
  return chars.join("");
}

async function resetAccountPassword(profile: AppProfile, appUserId: string): Promise<Row> {
  if (profile.role !== "admin") throw new Error("Only an Admin can reset account passwords.");
  if (!appUserId) return { ok: false, code: "account_not_found" };

  const state = await readMainState();
  const target = arr(state.users).find((user) => isLiveLegacyAccount(user) && text(user.id) === appUserId);
  if (!target) return { ok: false, code: "account_not_found" };
  const email = text(target.email).toLowerCase().trim();
  const role = text(target.role);

  let mapped = await accountFor(appUserId);
  if (!mapped?.active || mapped.role !== role) {
    const legacyPassword = text(target.password);
    if (legacyPassword.length < 6) return { ok: false, code: "account_needs_secure_login" };
    const provisioned = await provisionLegacyAccount(email, legacyPassword, true);
    if (provisioned.ok !== true) return { ok: false, code: text(provisioned.code) || "account_conflict" };
    mapped = await accountFor(appUserId);
  }
  if (!mapped?.active || mapped.role !== role) return { ok: false, code: "account_conflict" };

  const { data: authData, error: authReadError } = await db.auth.admin.getUserById(mapped.auth_user_id);
  const authUser = authData?.user;
  if (authReadError || !authUser || text(authUser.email).toLowerCase().trim() !== email ||
      text(authUser.app_metadata?.jsk_app_user_id) !== appUserId) {
    return { ok: false, code: "account_conflict" };
  }

  // Delete this person's legacy password before changing Auth. That closes the
  // legacy-login fallback path; restore it only if the Auth update fails.
  const latest = await readMainState();
  const latestTarget = arr(latest.users).find((user) => isLiveLegacyAccount(user) && text(user.id) === appUserId);
  if (!latestTarget || text(latestTarget.email).toLowerCase().trim() !== email || text(latestTarget.role) !== role) {
    return { ok: false, code: "account_conflict" };
  }
  const previousPassword = text(latestTarget.password);
  const temporaryPassword = newTemporaryPassword();
  delete latestTarget.password;
  await writeMainState(latest);

  const { error: passwordError } = await db.auth.admin.updateUserById(authUser.id, { password: temporaryPassword });
  if (passwordError) {
    if (previousPassword) {
      try {
        const rollback = await readMainState();
        const rollbackTarget = arr(rollback.users).find((user) => text(user.id) === appUserId &&
          text(user.email).toLowerCase().trim() === email);
        if (rollbackTarget && !Object.hasOwn(rollbackTarget, "password")) {
          rollbackTarget.password = previousPassword;
          await writeMainState(rollback);
        }
      } catch {
        console.error("Account password reset rollback needs Admin review.");
      }
    }
    throw new Error("Could not reset this account password. The previous sign-in should still work.");
  }

  return { ok: true, userId: appUserId, email, temporaryPassword };
}

function sameId(list: Row[], id: string): Row | undefined {
  return list.find((x) => text(x.id) === id);
}

function mergeById(current: Row[], submitted: Row[], canWrite: (row: Row) => boolean, fields: string[]): Row[] {
  const output = new Map<string, Row>(current.filter((x) => !!text(x.id)).map((x) => [text(x.id), clone(x)]));
  for (const row of submitted) {
    const id = text(row.id);
    if (!id || !canWrite(row)) continue;
    const existing = output.get(id);
    if (!existing) {
      const next: Row = {};
      for (const key of fields) if (Object.hasOwn(row, key)) next[key] = row[key];
      next.id = id;
      output.set(id, next);
      continue;
    }
    for (const key of fields) if (Object.hasOwn(row, key)) existing[key] = row[key];
  }
  return [...output.values()];
}

function nonNegativeInteger(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 0;
}

function attendanceDateLabel(value: unknown): string {
  const raw = text(value);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!match) return raw;
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  if (Number.isNaN(date.getTime())) return raw;
  return new Intl.DateTimeFormat("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  }).format(date);
}

function addAttendanceInboxNotifications(
  state: Row,
  student: Row,
  attendance: Row,
  isCorrection: boolean,
  correctionCount: number,
): void {
  const attendanceId = text(attendance.id);
  const status = text(attendance.status).toLowerCase().trim();
  if (!attendanceId || !["present", "absent"].includes(status)) return;

  const studentId = text(student.id);
  const studentName = text(student.name) || "Student";
  const subject = arr(state.subjects).find((row) => text(row.id) === text(attendance.subjectId));
  const batch = arr(state.batches).find((row) => text(row.id) === text(student.batchId));
  const subjectName = text(subject?.name) || "—";
  const batchName = text(batch?.name) || "—";
  const recipients: Array<{ key: string; userId: string | null; type: string; name: string }> = [];

  const studentUserId = text(student.userId);
  if (studentUserId) {
    recipients.push({ key: "stu", userId: studentUserId, type: "student", name: studentName });
  }
  recipients.push({
    key: "g",
    userId: text(student.guardianUserId) || null,
    type: "guardian",
    name: text(student.guardianName) || `Guardian of ${studentName}`,
  });
  arr(student.additionalGuardians).forEach((guardian, index) => {
    recipients.push({
      key: `gx${index}`,
      userId: text(guardian.userId) || null,
      type: "guardian",
      name: text(guardian.name) || "Guardian",
    });
  });

  if (!Array.isArray(state.inbox)) state.inbox = [];
  const inbox = state.inbox as Row[];
  const correctionSuffix = isCorrection ? `:corr:${correctionCount}:${status}` : "";
  const dateLine = `Date: ${attendanceDateLabel(attendance.date)}`;
  const batchLine = `Batch: ${batchName}`;
  const verb = isCorrection
    ? `was marked ${status.toUpperCase()} (corrected)`
    : `was marked ${status.toUpperCase()}`;
  const type = isCorrection
    ? "ATTENDANCE_CORRECTED"
    : status === "present" ? "ATTENDANCE_PRESENT" : "ATTENDANCE_ABSENT";
  const timestamp = Date.now();

  for (const recipient of recipients) {
    const dedupKey = `att:${attendanceId}${correctionSuffix}:${recipient.key}`;
    const duplicate = inbox.some((item) =>
      text(item.dedupKey) === dedupKey &&
      text(item.recipientUserId) === (recipient.userId || "") &&
      (!!recipient.userId || text(item.recipientName) === recipient.name)
    );
    if (duplicate) continue;

    const message = recipient.type === "student" && recipient.key === "stu"
      ? `You were marked ${status.toUpperCase()}${isCorrection ? " (corrected)" : ""} for ${subjectName}.\n${dateLine}\n${batchLine}`
      : `${studentName} ${verb} for ${subjectName}.\n${dateLine}\n${batchLine}`;
    inbox.unshift({
      id: `ntf_${crypto.randomUUID()}`,
      dedupKey,
      recipientUserId: recipient.userId,
      recipientType: recipient.type,
      recipientName: recipient.name,
      studentId,
      type,
      title: "JSK Institute Attendance Update",
      message,
      refType: "attendance",
      refId: attendanceId,
      attachment: null,
      ts: timestamp,
      read: {},
    });
  }
}

type InboxRecipient = { userId: string | null; type: string; name: string; studentId?: string; key?: string };

function readMap(value: unknown): Row {
  if (value && typeof value === "object" && !Array.isArray(value)) return { ...(value as Row) };
  return {};
}

function pushInbox(state: Row, spec: Row): Row | null {
  const type = text(spec.type);
  const refType = text(spec.refType);
  const refId = text(spec.refId);
  const userId = text(spec.recipientUserId);
  const recipientName = text(spec.recipientName);
  if (!type || (!userId && !recipientName)) return null;
  if (!Array.isArray(state.inbox)) state.inbox = [];
  const inbox = state.inbox as Row[];
  const dedupKey = text(spec.dedupKey);
  const sameRecipient = (item: Row) => text(item.recipientUserId) === userId &&
    (!!userId || text(item.recipientName) === recipientName);
  const existing = inbox.find((item) =>
    (dedupKey && text(item.dedupKey) === dedupKey && sameRecipient(item)) ||
    (!text(item.dedupKey) && text(item.type) === type && text(item.refType) === refType &&
      text(item.refId) === refId && sameRecipient(item))
  );
  const ts = Number(spec.ts) > 0 ? Number(spec.ts) : Date.now();
  if (existing) {
    if (dedupKey && !text(existing.dedupKey)) existing.dedupKey = dedupKey;
    existing.recipientType = text(spec.recipientType) || text(existing.recipientType) || "user";
    existing.recipientName = recipientName || text(existing.recipientName);
    existing.studentId = spec.studentId ?? existing.studentId ?? null;
    existing.type = type;
    existing.title = text(spec.title) || text(existing.title);
    existing.message = text(spec.message) || text(existing.message);
    existing.refType = refType || existing.refType || null;
    existing.refId = refId || existing.refId || null;
    if (Object.hasOwn(spec, "attachment")) existing.attachment = spec.attachment ?? null;
    const reads = readMap(existing.read);
    if (existing.read === true && userId && reads[userId] == null) reads[userId] = ts;
    if (spec.resetRead === true && userId) {
      reads[userId] = null;
      existing.ts = ts;
    }
    existing.read = reads;
    return existing;
  }
  const record: Row = {
    id: `ntf_${crypto.randomUUID()}`,
    dedupKey: dedupKey || null,
    recipientUserId: userId || null,
    recipientType: text(spec.recipientType) || "user",
    recipientName,
    studentId: spec.studentId ?? null,
    type,
    title: text(spec.title) || "JSK Institute Update",
    message: text(spec.message),
    refType: refType || null,
    refId: refId || null,
    attachment: spec.attachment ?? null,
    ts,
    read: {},
  };
  inbox.unshift(record);
  return record;
}

function liveUsers(state: Row): Row[] {
  return arr(state.users).filter((user) => isLiveLegacyAccount(user));
}

function userRecipient(user: Row): InboxRecipient | null {
  const userId = text(user.id);
  if (!userId) return null;
  return { userId, type: text(user.role) || "user", name: text(user.name) || "User" };
}

function studentRecipients(student: Row): InboxRecipient[] {
  const name = text(student.name) || "Student";
  const output: InboxRecipient[] = [];
  const seen = new Set<string>();
  const add = (recipient: InboxRecipient) => {
    const key = recipient.userId ? `user:${recipient.userId}` : `name:${recipient.type}:${recipient.name}`;
    if (!seen.has(key)) { seen.add(key); output.push(recipient); }
  };
  const studentUserId = text(student.userId);
  if (studentUserId) add({ userId: studentUserId, type: "student", name, studentId: text(student.id), key: "stu" });
  add({
    userId: text(student.guardianUserId) || null,
    type: "guardian",
    name: text(student.guardianName) || `Guardian of ${name}`,
    studentId: text(student.id),
    key: "g",
  });
  arr(student.additionalGuardians).forEach((guardian, index) => add({
    userId: text(guardian.userId) || null,
    type: "guardian",
    name: text(guardian.name) || `Guardian of ${name}`,
    studentId: text(student.id),
    key: `gx${index}`,
  }));
  return output;
}

function fmtClock(value: unknown): string {
  const raw = text(value).trim();
  const match = /^(\d{1,2}):(\d{2})/.exec(raw);
  if (match) {
    const hour = Number(match[1]);
    return `${hour % 12 || 12}:${match[2]} ${hour < 12 ? "AM" : "PM"}`;
  }
  const numeric = Number(value);
  const date = new Date(Number.isFinite(numeric) && numeric > 0 ? numeric : raw);
  if (Number.isNaN(date.getTime())) return raw;
  return new Intl.DateTimeFormat("en-IN", {
    hour: "numeric", minute: "2-digit", hour12: true, timeZone: "Asia/Kolkata",
  }).format(date);
}

function dateRangeLabel(records: Row[]): string {
  const dates = [...new Set(records.map((row) => text(row.date)).filter(Boolean))].sort();
  if (!dates.length) return "the requested date";
  if (dates.length === 1) return attendanceDateLabel(dates[0]);
  return `${attendanceDateLabel(dates[0])} to ${attendanceDateLabel(dates[dates.length - 1])} (${dates.length} days)`;
}

function isCancelledSchedule(schedule: Row): boolean {
  return ["cancelled", "canceled"].includes(text(schedule.status).toLowerCase());
}

function scheduleMessage(state: Row, schedule: Row, action: "scheduled" | "rescheduled" | "cancelled"): string {
  const subject = arr(state.subjects).find((row) => text(row.id) === text(schedule.subjectId));
  const batch = arr(state.batches).find((row) => text(row.id) === text(schedule.batchId));
  const teacher = arr(state.users).find((row) => text(row.id) === text(schedule.teacherId));
  const subjectName = text(subject?.name) || "Class";
  const head = action === "cancelled"
    ? `${subjectName} class has been CANCELLED.`
    : `${subjectName} class has been ${action}.`;
  const details = [
    `Date: ${attendanceDateLabel(schedule.date)}`,
    `Time: ${fmtClock(schedule.time)}${schedule.endTime ? ` - ${fmtClock(schedule.endTime)}` : ""}`,
    `Batch: ${text(batch?.name) || "—"}`,
    `Teacher: ${text(teacher?.name) || text(schedule.teacherName) || "—"}`,
  ];
  if (action !== "cancelled") {
    if (schedule.room) details.push(`Room: ${text(schedule.room)}`);
    if (action === "rescheduled" && schedule.topic) details.push(`Topic: ${text(schedule.topic)}`);
    if (schedule.note) details.push(`Note: ${text(schedule.note)}`);
  }
  return `${head}\n${details.join("\n")}`;
}

function addStudentFanout(state: Row, spec: Row, student: Row): void {
  for (const recipient of studentRecipients(student)) {
    pushInbox(state, {
      ...spec,
      recipientUserId: recipient.userId,
      recipientType: recipient.type,
      recipientName: recipient.name,
      studentId: text(student.id),
      dedupKey: text(spec.dedupKey) ? `${text(spec.dedupKey)}:${recipient.key || recipient.userId || recipient.name}` : "",
    });
  }
}

function staffCheckMessage(user: Row, record: Row, kind: "in" | "out"): { type: string; message: string } {
  const eventTs = Number(record[kind === "in" ? "inTs" : "outTs"] ?? Date.now());
  const firstName = text(user.name).trim().split(/\s+/)[0] || "Staff";
  const date = text(record.date) || new Date(eventTs).toISOString().slice(0, 10);
  let message = `${firstName} checked ${kind === "in" ? "IN" : "OUT"} successfully.\nDate: ${attendanceDateLabel(date)}\nTime: ${fmtClock(eventTs)}`;
  let type = kind === "in" ? "STAFF_CHECK_IN" : "STAFF_CHECK_OUT";
  if (kind === "in") {
    const dateParts = date.split("-").map(Number);
    const weekday = dateParts.length === 3 && dateParts.every(Number.isFinite)
      ? new Intl.DateTimeFormat("en-US", { weekday: "long", timeZone: "UTC" })
        .format(new Date(Date.UTC(dateParts[0], dateParts[1] - 1, dateParts[2])))
      : "";
    const specialShift = arr(user.lateDays).find((item) => text(item.day) === weekday);
    const shift = text(specialShift?.start) || text(user.shiftTime) || text(record.shift) || "09:00";
    const [hourText, minuteText] = shift.split(":");
    const expected = Number(hourText) * 60 + Number((minuteText || "0").slice(0, 2));
    const actualDate = new Date(eventTs);
    const actual = Number(new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Kolkata",
    }).format(actualDate).split(":")[0]) * 60 + Number(new Intl.DateTimeFormat("en-GB", {
      hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Kolkata",
    }).format(actualDate).split(":")[1]);
    const grace = 10;
    const lateMinutes = Number(record.lateMin) || Math.max(0, actual - expected);
    const isLate = record.late === true || (record.late !== false && lateMinutes > grace);
    if (isLate) {
      type = "STAFF_LATE";
      message += `\nLate by ${lateMinutes} min (shift ${fmtClock(shift)}, ${grace} min grace)`;
    }
  }
  return { type, message };
}

function addUserAndAdminNotification(state: Row, spec: Row, user: Row, baseKey: string): void {
  const recipient = userRecipient(user);
  if (recipient) pushInbox(state, {
    ...spec,
    recipientUserId: recipient.userId,
    recipientType: recipient.type,
    recipientName: recipient.name,
    dedupKey: `${baseKey}:self`,
  });
  for (const admin of liveUsers(state).filter((item) => text(item.role) === "admin")) {
    const adminRecipient = userRecipient(admin);
    if (adminRecipient) pushInbox(state, {
      ...spec,
      recipientUserId: adminRecipient.userId,
      recipientType: adminRecipient.type,
      recipientName: adminRecipient.name,
      dedupKey: `${baseKey}:adm:${adminRecipient.userId}`,
    });
  }
}

function addLeaveNotifications(state: Row, requests: Row[], decision?: string): void {
  if (!requests.length) return;
  const first = requests[0];
  const groupId = text(first.groupId) || text(first.id);
  const userId = text(first.userId);
  const user = liveUsers(state).find((item) => text(item.id) === userId);
  if (!user || !groupId) return;
  const person = text(first.name) || text(user.name) || "Staff member";
  const role = text(first.role) || text(user.role) || "staff";
  const dates = dateRangeLabel(requests);
  const reason = text(first.reason) || "not given";
  if (decision) {
    state.inbox = arr(state.inbox).filter((item) =>
      !(text(item.refType) === "leave_request" && text(item.recipientType) === "admin" &&
        (text(item.refId) === groupId || requests.some((row) => text(row.id) === text(item.refId))))
    );
    pushInbox(state, {
      recipientUserId: userId,
      recipientType: role,
      recipientName: person,
      type: "STAFF_UPDATE",
      title: "JSK Institute Staff Update",
      message: `Your leave request for ${dates} was ${decision.toUpperCase()} by the office.`,
      refType: "leave_request",
      refId: groupId,
      dedupKey: `lreq:${groupId}:decision:${decision}:${userId}`,
      resetRead: true,
    });
    return;
  }
  pushInbox(state, {
    recipientUserId: userId,
    recipientType: role,
    recipientName: person,
    type: "STAFF_UPDATE",
    title: "JSK Institute Staff Update",
    message: `Your request was sent to the office and is pending.\nDate: ${dates}`,
    refType: "leave_request",
    refId: groupId,
    dedupKey: `lreq:${groupId}:u:${userId}`,
  });
  for (const admin of liveUsers(state).filter((item) => text(item.role) === "admin")) {
    const adminId = text(admin.id);
    pushInbox(state, {
      recipientUserId: adminId,
      recipientType: "admin",
      recipientName: text(admin.name),
      type: "LEAVE_REQUEST",
      title: "Leave request — needs your decision",
      message: `${person} (${role}) has requested leave.\nDate: ${dates}\nReason: ${reason}\nAccept or decline it on the ${role === "teacher" ? "Teachers" : "Staff"} page.`,
      refType: "leave_request",
      refId: groupId,
      dedupKey: `lreq:${groupId}:adm:${adminId}`,
    });
  }
}

function fanOutSystemNotifications(previous: Row, next: Row): void {
  if (!liveUsers(previous).length) return;
  const oldRecords = arr(previous.staffRecords);
  const newRecords = arr(next.staffRecords);
  const oldById = new Map(oldRecords.map((row) => [text(row.id), row]));
  for (const record of newRecords) {
    const id = text(record.id);
    const old = oldById.get(id);
    const appUserId = text(record.userId) || text(record.staffId);
    const user = liveUsers(next).find((item) => text(item.id) === appUserId);
    if (!id || !user) continue;
    const inTs = Number(record.inTs) || 0;
    const oldInTs = Number(old?.inTs) || 0;
    const outTs = Number(record.outTs) || 0;
    const oldOutTs = Number(old?.outTs) || 0;
    for (const kind of ["in", "out"] as const) {
      const justChecked = kind === "in" ? (inTs > 0 && (!old || oldInTs === 0)) : (outTs > 0 && oldOutTs === 0);
      if (!justChecked) continue;
      const details = staffCheckMessage(user, record, kind);
      addUserAndAdminNotification(next, {
        type: details.type,
        title: "JSK Institute Staff Attendance",
        message: details.message,
        refType: "staff_record",
        refId: id,
        ts: kind === "in" ? inTs : outTs,
      }, user, `srec:${id}:${kind}`);
    }
  }

  const oldLeaves = arr(previous.leaveRequests);
  const leaves = arr(next.leaveRequests);
  const oldLeaveById = new Map(oldLeaves.map((row) => [text(row.id), row]));
  const newGroups = new Map<string, Row[]>();
  const decidedGroups = new Map<string, Row[]>();
  for (const request of leaves) {
    const groupId = text(request.groupId) || text(request.id);
    const old = oldLeaveById.get(text(request.id));
    if (!old) {
      const list = newGroups.get(groupId) || [];
      list.push(request);
      newGroups.set(groupId, list);
    } else if (text(old.status) === "pending" && ["accepted", "approved", "declined", "rejected"].includes(text(request.status))) {
      const list = decidedGroups.get(groupId) || [];
      list.push(request);
      decidedGroups.set(groupId, list);
    }
  }
  for (const [groupId, requests] of newGroups) {
    const wholeGroup = leaves.filter((row) => (text(row.groupId) || text(row.id)) === groupId);
    addLeaveNotifications(next, wholeGroup.length ? wholeGroup : requests);
  }
  for (const [groupId, requests] of decidedGroups) {
    const wholeGroup = leaves.filter((row) => (text(row.groupId) || text(row.id)) === groupId);
    const statuses = new Set(wholeGroup.map((row) => text(row.status)));
    const decision = statuses.has("declined") || statuses.has("rejected") ? "declined" : "accepted";
    addLeaveNotifications(next, wholeGroup.length ? wholeGroup : requests, decision);
  }

  const oldAdjustments = new Set(arr(previous.hourAdjustments).map((row) => text(row.id)));
  for (const adjustment of arr(next.hourAdjustments)) {
    const id = text(adjustment.id);
    const recipientId = text(adjustment.userId);
    const minutes = Number(adjustment.minutes) || 0;
    if (!id || !recipientId || oldAdjustments.has(id)) continue;
    const user = liveUsers(next).find((item) => text(item.id) === recipientId);
    const recipient = user && userRecipient(user);
    if (!user || !recipient) continue;
    const duration = `${minutes > 0 ? "+" : "−"}${Math.floor(Math.abs(minutes) / 60) ? `${Math.floor(Math.abs(minutes) / 60)}h` : ""}${Math.abs(minutes) % 60 ? `${Math.abs(minutes) % 60}m` : ""}`;
    pushInbox(next, {
      recipientUserId: recipient.userId,
      recipientType: recipient.type,
      recipientName: recipient.name,
      type: "STAFF_UPDATE",
      title: "JSK Institute Staff Update",
      message: `${duration} was ${minutes >= 0 ? "added to" : "taken from"} your hours bank.\nReason: ${text(adjustment.reason) || "Office adjustment"}\nDate: ${attendanceDateLabel(adjustment.date)}`,
      refType: "staff_update",
      refId: id,
      dedupKey: `hadj:${id}:u:${recipientId}`,
    });
  }

  const oldAnnouncements = new Map(arr(previous.announcements).map((row) => [text(row.id), row]));
  for (const announcement of arr(next.announcements)) {
    const id = text(announcement.id);
    const old = oldAnnouncements.get(id);
    if (!id || announcement.published === false || (Number(announcement.publishAt) > Date.now())) continue;
    if (old && text(old.title) === text(announcement.title) &&
      text(old.message ?? old.body) === text(announcement.message ?? announcement.body) &&
      JSON.stringify(old.recipients ?? []) === JSON.stringify(announcement.recipients ?? []) &&
      JSON.stringify(old.staffRecipients ?? []) === JSON.stringify(announcement.staffRecipients ?? []) &&
      JSON.stringify(old.file ?? null) === JSON.stringify(announcement.file ?? null)) continue;
    const rawAttachment = announcement.file ?? announcement.attachment;
    const attachment = rawAttachment && typeof rawAttachment === "object" && !Array.isArray(rawAttachment)
      ? rawAttachment as Row
      : null;
    const title = text(announcement.title) || "Institute notice";
    const body = text(announcement.message ?? announcement.body);
    const dateLine = `Date: ${attendanceDateLabel(announcement.date || new Date().toISOString().slice(0, 10))}`;
    const attachmentLine = attachment && text(attachment.name) ? `\nAttachment: ${text(attachment.name)}` : "";
    const message = `${body}${body ? "\n" : ""}${dateLine}${attachmentLine}`;
    const type = text(announcement.category).toLowerCase() === "notice" ? "ADMIN_MESSAGE" : "ADMIN_ANNOUNCEMENT";
    const spec: Row = {
      type, title, message, attachment,
      refType: "announcement", refId: id,
      dedupKey: `ann:${id}`,
      resetRead: true,
    };
    const selectedStudents = arr(next.students).filter((student) => arr(announcement.recipients).some((recipient) => text(recipient) === text(student.id)));
    const recipients = new Map<string, InboxRecipient>();
    for (const student of selectedStudents) for (const recipient of studentRecipients(student)) {
      const key = recipient.userId ? `user:${recipient.userId}` : `name:${recipient.name}`;
      recipients.set(key, recipient);
    }
    for (const userId of Array.isArray(announcement.staffRecipients) ? announcement.staffRecipients.map(text) : []) {
      const recipient = userRecipient(liveUsers(next).find((user) => text(user.id) === userId) || {});
      if (recipient) recipients.set(`user:${recipient.userId}`, recipient);
    }
    const hasExplicitTargets = Array.isArray(announcement.recipients) || Array.isArray(announcement.staffRecipients);
    if (!hasExplicitTargets || (!selectedStudents.length && !arr(announcement.staffRecipients).length)) {
      const audienceValue = announcement.audience ?? announcement.roles ?? "all";
      const audience = Array.isArray(audienceValue) ? audienceValue.map((value) => text(value).toLowerCase()) : [text(audienceValue).toLowerCase()];
      for (const user of liveUsers(next)) {
        const role = text(user.role).toLowerCase();
        if (audience.includes("all") || audience.includes("everyone") || audience.includes(role) ||
            (role === "guardian" && audience.includes("student"))) {
          const recipient = userRecipient(user);
          if (recipient) recipients.set(`user:${recipient.userId}`, recipient);
        }
      }
    }
    for (const recipient of recipients.values()) {
      pushInbox(next, {
        ...spec,
        recipientUserId: recipient.userId,
        recipientType: recipient.type,
        recipientName: recipient.name,
        studentId: recipient.studentId || null,
        dedupKey: `${text(spec.dedupKey)}:${recipient.key
          ? `${recipient.key}:${recipient.userId || `s:${recipient.studentId || ""}`}`
          : `u:${recipient.userId || ""}`}`,
      });
    }
  }

  const oldHolidays = new Set(arr(previous.holidays).map((holiday) => text(holiday.date)));
  for (const holiday of arr(next.holidays)) {
    const date = text(holiday.date);
    if (!date || oldHolidays.has(date)) continue;
    const name = text(holiday.name) || "Holiday";
    const message = `The institute is CLOSED on ${attendanceDateLabel(date)} for ${name}.\nNo check-in is needed that day, hours are not counted, no one is marked late and no leave request is needed.`;
    for (const user of liveUsers(next)) {
      const recipient = userRecipient(user);
      if (!recipient) continue;
      pushInbox(next, {
        recipientUserId: recipient.userId,
        recipientType: recipient.type,
        recipientName: recipient.name,
        type: "INSTITUTE_HOLIDAY",
        title: `Institute closed — ${name}`,
        message,
        refType: "holiday",
        refId: date,
        dedupKey: `holiday:${date}:u:${recipient.userId}`,
      });
    }
  }

  const oldStudents = new Map(arr(previous.students).map((student) => [text(student.id), student]));
  for (const student of arr(next.students)) {
    const id = text(student.id);
    const old = oldStudents.get(id);
    if (!id || (old && text(old.batchId) === text(student.batchId))) continue;
    const batch = arr(next.batches).find((row) => text(row.id) === text(student.batchId));
    const assigned = !!text(student.batchId) && !!batch;
    const batchName = assigned ? text(batch?.name) : "Not yet decided";
    const timestamp = Date.now();
    for (const recipient of studentRecipients(student)) {
      const isStudent = recipient.type === "student";
      const message = assigned
        ? (isStudent
          ? `You are now in ${batchName}.\nClass schedules, subjects and attendance for this batch apply to you.`
          : `${text(student.name) || "Student"} is now in ${batchName}.\nClass schedules and attendance for this batch apply to this student.`)
        : (isStudent
          ? "Your batch is not decided yet.\nThe office will place you in a batch — you will be told here as soon as it is done."
          : `${text(student.name) || "Student"}'s batch is not decided yet.\nThe office will place the student — you will be told here as soon as it is done.`);
      pushInbox(next, {
        recipientUserId: recipient.userId,
        recipientType: recipient.type,
        recipientName: recipient.name,
        studentId: id,
        type: "BATCH_UPDATE",
        title: assigned ? "Batch assigned" : "Batch not decided yet",
        message,
        refType: "batch",
        refId: id,
        ts: timestamp,
      });
    }
  }

  const oldSchedules = new Map(arr(previous.schedules).map((schedule) => [text(schedule.id), schedule]));
  for (const schedule of arr(next.schedules)) {
    const id = text(schedule.id);
    const old = oldSchedules.get(id);
    if (!id) continue;
    const cancelled = isCancelledSchedule(schedule);
    let action: "scheduled" | "rescheduled" | "cancelled" | null = null;
    if (!old && !cancelled) action = "scheduled";
    else if (old && !isCancelledSchedule(old) && cancelled) action = "cancelled";
    else if (old && !cancelled && ["date", "time", "endTime", "room", "note", "topic", "subjectId", "batchId", "teacherId"]
      .some((key) => text(old[key]) !== text(schedule[key]))) action = "rescheduled";
    if (!action) continue;
    const batchId = text(schedule.batchId);
    const keyVersion = action === "rescheduled" ? String(Number(schedule.rev) || 0) : "";
    const baseKey = `sch:${action}:${id}${keyVersion ? `:${keyVersion}` : ""}`;
    for (const student of arr(next.students).filter((row) => text(row.batchId) === batchId)) {
      addStudentFanout(next, {
        type: `CLASS_${action.toUpperCase()}`,
        title: "JSK Institute Class Schedule",
        message: scheduleMessage(next, schedule, action),
        refType: "schedule",
        refId: id,
        dedupKey: baseKey,
      }, student);
    }
  }
}

function ownedBy(row: Row, appUserId: string): boolean {
  return text(row.userId) === appUserId || text(row.recipientUserId) === appUserId;
}

function roleView(source: Row, profile: AppProfile): Row {
  if (profile.role === "admin") {
    return cleanState(source);
  }
  const state = cleanState(source);
  const appId = profile.app_user_id;
  const allUsers = arr(state.users);
  const me = allUsers.find((u) => text(u.id) === appId);
  const allStudents = arr(state.students);
  const studentIds = new Set<string>();
  if (profile.role === "student") {
    for (const student of allStudents) if (text(student.userId) === appId) studentIds.add(text(student.id));
  } else if (profile.role === "guardian") {
    for (const student of allStudents) {
      const extra = Array.isArray(student.additionalGuardians) ? student.additionalGuardians : [];
      if (text(student.guardianUserId) === appId || extra.some((g: unknown) =>
        !!g && typeof g === "object" && text((g as Row).userId) === appId)) studentIds.add(text(student.id));
    }
  }
  const allAssignments = arr(state.assignments);
  const myAssignments = allAssignments.filter((x) => text(x.teacherId) === appId);
  const batchIds = new Set<string>(myAssignments.map((x) => text(x.batchId)).filter(Boolean));
  if (profile.role === "student" || profile.role === "guardian") {
    for (const student of allStudents) if (studentIds.has(text(student.id)) && text(student.batchId)) batchIds.add(text(student.batchId));
  }
  const subjectIds = new Set<string>(myAssignments.map((x) => text(x.subjectId)).filter(Boolean));
  const relatedStudents = allStudents.filter((s) =>
    studentIds.has(text(s.id)) || (profile.role === "teacher" && batchIds.has(text(s.batchId))));
  const relatedStudentIds = new Set<string>(relatedStudents.map((s) => text(s.id)));
  const keepStudentData = (row: Row) => relatedStudentIds.has(text(row.studentId));

  state.users = me ? [me] : [];
  state.students = relatedStudents;
  state.attendance = arr(state.attendance).filter((row) =>
    keepStudentData(row) || (profile.role === "teacher" && batchIds.has(text(row.batchId)) &&
      subjectIds.has(text(row.subjectId))));
  state.staffRecords = profile.role === "staff" ? arr(state.staffRecords).filter((r) => ownedBy(r, appId)) : [];
  state.staffNotifications = arr(state.staffNotifications).filter((r) => ownedBy(r, appId));
  state.leaveRequests = arr(state.leaveRequests).filter((r) => text(r.userId) === appId);
  state.inbox = arr(state.inbox).filter((r) => ownedBy(r, appId));
  state.notifications = arr(state.notifications).filter((r) => ownedBy(r, appId));
  state.lateRemarks = arr(state.lateRemarks).filter((r) => ownedBy(r, appId));
  state.hourAdjustments = arr(state.hourAdjustments).filter((r) => ownedBy(r, appId));
  state.feePayments = arr(state.feePayments).filter(keepStudentData);
  state.feePlans = arr(state.feePlans).filter(keepStudentData);
  state.feeReminders = arr(state.feeReminders).filter(keepStudentData);
  state.feeClearances = arr(state.feeClearances).filter(keepStudentData);
  state.assignments = profile.role === "teacher"
    ? myAssignments
    : (profile.role === "student" || profile.role === "guardian"
      ? allAssignments.filter((a) => batchIds.has(text(a.batchId))) : []);
  state.batches = arr(state.batches).filter((b) => batchIds.has(text(b.id)));
  state.subjects = arr(state.subjects).filter((s) => subjectIds.has(text(s.id)) ||
    state.assignments.some((a) => text(a.subjectId) === text(s.id)));
  state.announcements = arr(state.announcements).filter((a) => {
    const audience = a.audience ?? a.roles ?? "all";
    const allowed = Array.isArray(audience) ? audience.map(text) : [text(audience)];
    const batchOk = !text(a.batchId) || batchIds.has(text(a.batchId));
    return batchOk && (allowed.length === 0 || allowed.includes("all") || allowed.includes(profile.role));
  });
  state.notes = arr(state.notes).filter((n) => !text(n.batchId) || batchIds.has(text(n.batchId)) || text(n.byId) === appId);
  state.previousYears = {};
  state.deletedIds = [];
  state.settings = {};
  return state;
}

async function getProfile(accessToken: string): Promise<AppProfile | null> {
  const { data: authResult, error: authError } = await db.auth.getUser(accessToken);
  if (authError || !authResult.user) return null;
  const { data, error } = await db.from("jsk_auth_profiles").select("auth_user_id,app_user_id,role,active")
    .eq("auth_user_id", authResult.user.id).maybeSingle();
  if (error || !data || !data.active || !ROLES.has(data.role) || text(authResult.user.app_metadata?.jsk_app_user_id) !== data.app_user_id || text(authResult.user.app_metadata?.jsk_role) !== data.role) return null;
  return data as AppProfile;
}

async function accountFor(appUserId: string): Promise<AppProfile | null> {
  const { data, error } = await db.from("jsk_auth_profiles").select("auth_user_id,app_user_id,role,active")
    .eq("app_user_id", appUserId).maybeSingle();
  if (error) throw error;
  return data as AppProfile | null;
}

async function registerPushToken(profile: AppProfile, tokenValue: string, platformValue: string): Promise<Row> {
  const token = tokenValue.trim();
  const platform = platformValue.toLowerCase();
  if (token.length < 40 || token.length > 4096 || !["android", "web", "ios"].includes(platform)) {
    return { ok: false, code: "invalid_push_registration" };
  }
  const tokenHash = await sha256(token);
  const { error } = await db.from("jsk_push_tokens").upsert({
    token_hash: tokenHash,
    token,
    auth_user_id: profile.auth_user_id,
    app_user_id: profile.app_user_id,
    platform,
    updated_at: new Date().toISOString(),
  }, { onConflict: "token_hash" });
  if (error) throw error;
  return { ok: true };
}

async function unregisterPushToken(profile: AppProfile, tokenValue: string): Promise<Row> {
  const token = tokenValue.trim();
  if (token.length < 40 || token.length > 4096) return { ok: false };
  const tokenHash = await sha256(token);
  const { error } = await db.from("jsk_push_tokens").delete()
    .eq("token_hash", tokenHash)
    .eq("auth_user_id", profile.auth_user_id);
  if (error) throw error;
  return { ok: true };
}

async function ensureAdminAccounts(current: Row, submitted: Row, callerProfile: AppProfile): Promise<void> {
  const currentUsers = arr(current.users).filter(isLiveLegacyAccount);
  const submittedUsers = arr(submitted.users).filter((u) =>
    !!text(u.id) && !!text(u.email) && ROLES.has(text(u.role)) && !u.ghost && !u.demoAccount);
  const submittedIds = new Set(submittedUsers.map((u) => text(u.id)));
  const remainingAdmins = submittedUsers.filter((u) => text(u.role) === "admin");
  if (remainingAdmins.length < 1) throw new Error("At least one admin account must remain active.");

  const seenEmails = new Set<string>();
  for (const incoming of submittedUsers) {
    const id = text(incoming.id);
    const email = text(incoming.email).toLowerCase().trim();
    if (seenEmails.has(email)) throw new Error("A login email is used more than once.");
    seenEmails.add(email);
    const existingLegacy = sameId(currentUsers, id);
    if (existingLegacy &&
      text(existingLegacy.email).toLowerCase().trim() === email &&
      text(existingLegacy.role) === text(incoming.role) &&
      text(existingLegacy.name) === text(incoming.name) &&
      text(existingLegacy.password) === (text(incoming.password) || text(existingLegacy.password))) {
      continue;
    }
    const existingProfile = await accountFor(id);
    if (existingProfile) {
      const { data: mappedAuth, error: mappedAuthError } = await db.auth.admin.getUserById(existingProfile.auth_user_id);
      if (mappedAuthError || !mappedAuth.user || existingProfile.app_user_id !== id ||
          text(mappedAuth.user.app_metadata?.jsk_app_user_id) !== id ||
          text(mappedAuth.user.app_metadata?.jsk_role) !== existingProfile.role) {
        throw new Error("This account has an invalid JSK identity mapping.");
      }
    }
    const password = text(incoming.password);
    if (!existingProfile) {
      // Existing accounts are migrated only when that person signs in. Admin saves
      // should provision only newly added accounts, regardless of school size.
      if (existingLegacy) continue;
      if (password.length < 6) throw new Error(`A temporary password is required for ${email}.`);
      const { data, error } = await db.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        app_metadata: { jsk_app_user_id: id, jsk_role: text(incoming.role) },
        user_metadata: { full_name: text(incoming.name) },
      });
      if (error) throw new Error(`Could not create the account for ${email}: ${error.message}`);
      const { error: profileError } = await db.from("jsk_auth_profiles").insert({
        auth_user_id: data.user.id, app_user_id: id, role: text(incoming.role), active: true,
      });
      if (profileError) throw profileError;
      continue;
    }
    const patch: Row = {
      email,
      app_metadata: { jsk_app_user_id: id, jsk_role: text(incoming.role) },
      user_metadata: { full_name: text(incoming.name) },
    };
    // Password changes for mapped users must go through the Admin reset action
    // or that user's authenticated Auth flow. A stale browser may still submit
    // an old legacy password, so never accept it here as an Auth update.
    const { error: authError } = await db.auth.admin.updateUserById(existingProfile.auth_user_id, patch);
    if (authError) throw authError;
    const { error: profileError } = await db.from("jsk_auth_profiles").update({
      role: text(incoming.role), active: true, updated_at: new Date().toISOString(),
    }).eq("auth_user_id", existingProfile.auth_user_id);
    if (profileError) throw profileError;
  }

  // Accounts removed in the Admin UI are removed from Auth and the private map.
  for (const old of currentUsers) {
    const oldId = text(old.id);
    if (submittedIds.has(oldId)) continue;
    const mapped = await accountFor(oldId);
    if (mapped && oldId !== callerProfile.app_user_id) {
      const { error } = await db.auth.admin.deleteUser(mapped.auth_user_id);
      if (error) throw error;
    }
  }
}

function copyFields(source: Row, target: Row, fields: string[]): void {
  for (const field of fields) if (Object.hasOwn(source, field)) target[field] = source[field];
}

function applyMemberWrites(current: Row, submitted: Row, profile: AppProfile): Row {
  const next = clone(current);
  const appId = profile.app_user_id;
  const userNow = sameId(arr(next.users), appId);
  const userSent = sameId(arr(submitted.users), appId);
  if (userNow && userSent) copyFields(userSent, userNow, [...APP_USER_SAFE_FIELDS]);

  if (profile.role === "staff" || profile.role === "teacher") {
    next.staffRecords = mergeById(arr(next.staffRecords), arr(submitted.staffRecords),
      (r) => text(r.userId) === appId, STAFF_RECORD_FIELDS);
    const requests = arr(next.leaveRequests);
    const submittedRequests = arr(submitted.leaveRequests);
    const requestById = new Map(requests.map((r) => [text(r.id), r]));
    for (const request of submittedRequests) {
      if (!text(request.id) || text(request.userId) !== appId) continue;
      const existing = requestById.get(text(request.id));
      if (existing) {
        if (text(existing.status) === "pending") {
          copyFields(request, existing, ["date", "minutes", "name", "reason", "ts", "type"]);
        }
      } else {
        const created: Row = {
          id: text(request.id),
          userId: appId,
          role: profile.role,
          status: "pending",
        };
        copyFields(request, created, ["groupId", "date", "minutes", "name", "reason", "ts", "type"]);
        requests.push(created);
        requestById.set(text(request.id), created);
      }
    }
    next.leaveRequests = requests;
  }

  if (profile.role === "teacher") {
    const allowedAssignments = arr(current.assignments).filter((a) => text(a.teacherId) === appId);
    const allowed = (r: Row) => allowedAssignments.some((a) =>
      text(a.batchId) === text(r.batchId) && text(a.subjectId) === text(r.subjectId));
    const permittedStudents = new Set(arr(current.students)
      .filter((s) => allowedAssignments.some((a) => text(a.batchId) === text(s.batchId)))
      .map((s) => text(s.id)));
    const currentAttendance = arr(current.attendance);
    const currentAttendanceById = new Map(currentAttendance
      .filter((row) => !!text(row.id)).map((row) => [text(row.id), row]));
    const acceptedById = new Map<string, Row>();
    for (const row of arr(submitted.attendance)) {
      const id = text(row.id);
      if (!id || !permittedStudents.has(text(row.studentId)) || !allowed(row)) continue;
      acceptedById.set(id, row);
    }
    const acceptedAttendance: Row[] = [];
    for (const [id, submittedRow] of acceptedById) {
      const previous = currentAttendanceById.get(id);
      const previousStatus = text(previous?.status).toLowerCase().trim();
      const status = text(submittedRow.status).toLowerCase().trim();
      const isCorrection = !!previous && previousStatus !== status;
      const correctionCount = isCorrection
        ? nonNegativeInteger(previous?.corrCount) + 1
        : previous ? nonNegativeInteger(previous.corrCount) : 0;
      const acceptedRow = { ...submittedRow, status, corrCount: correctionCount };
      acceptedAttendance.push(acceptedRow);

      if (!previous || isCorrection) {
        const student = arr(current.students).find((item) => text(item.id) === text(acceptedRow.studentId));
        if (student) {
          addAttendanceInboxNotifications(next, student, acceptedRow, isCorrection, correctionCount);
        }
      }
    }
    next.attendance = mergeById(arr(next.attendance), acceptedAttendance,
      (r) => permittedStudents.has(text(r.studentId)) && allowed(r), ATTENDANCE_FIELDS);
    next.notes = mergeById(arr(next.notes), arr(submitted.notes),
      (r) => text(r.byId) === appId && allowed(r),
      ["batchId", "subjectId", "title", "body", "content", "ts", "byId"]);
    const submittedSchedules = arr(submitted.schedules).map((row) => ({ ...row, teacherId: appId }));
    next.schedules = mergeById(arr(next.schedules), submittedSchedules,
      (row) => allowed(row),
      ["batchId", "subjectId", "teacherId", "teacherName", "kind", "topic", "date", "time", "endTime", "room", "note", "status", "ts", "rev"]);
  }

  if (profile.role === "student") {
    const student = arr(next.students).find((s) => text(s.userId) === appId);
    const sent = arr(submitted.students).find((s) => text(s.userId) === appId);
    if (student && sent) copyFields(sent, student, [...STUDENT_SELF_FIELDS]);
  }

  const readList = arr(next.inbox);
  const submittedInbox = arr(submitted.inbox);
  const inboxById = new Map(submittedInbox.filter((r) => !!text(r.id)).map((r) => [text(r.id), r]));
  for (const item of readList) {
    const id = text(item.id);
    const sent = inboxById.get(id);
    if (!sent || !ownedBy(item, appId) || !sent.read || typeof sent.read !== "object" || Array.isArray(sent.read)) continue;
    const sentRead = sent.read as Row;
    if (!Object.hasOwn(sentRead, appId)) continue;
    const readMap = item.read && typeof item.read === "object" && !Array.isArray(item.read)
      ? { ...(item.read as Row) }
      : {};
    const readValue = sentRead[appId];
    if (readValue === null) {
      readMap[appId] = null;
    } else {
      const requestedReadAt = Number(readValue);
      readMap[appId] = Number.isFinite(requestedReadAt) && requestedReadAt > 0
        ? Math.min(requestedReadAt, Date.now())
        : Date.now();
    }
    item.read = readMap;
  }
  const notifs = arr(next.notifications);
  const submittedNotifs = new Map(arr(submitted.notifications).map((r) => [text(r.id), r]));
  for (const item of notifs) {
    const sent = submittedNotifs.get(text(item.id));
    if (sent && ownedBy(item, appId)) {
      if (Object.hasOwn(sent, "read")) item.read = sent.read === true;
      if (Object.hasOwn(sent, "seen")) item.seen = sent.seen === true;
    }
  }
  fanOutSystemNotifications(current, next);
  return next;
}

async function compatUsers(current: Row, submitted: Row): Promise<Row[]> {
  const oldUsers = arr(current.users);
  const hidden = oldUsers.filter((u) => !!u.ghost || !!u.demoAccount).map((user) => {
    const safe = clone(user);
    delete safe.password;
    return safe;
  });
  const oldById = new Map(oldUsers.map((u) => [text(u.id), u]));
  const active: Row[] = [];
  for (const u of arr(submitted.users).filter((u) => !u.ghost && !u.demoAccount)) {
    const copy = clone(u);
    const old = oldById.get(text(u.id));
    const mapped = await accountFor(text(u.id));
    if (mapped?.active) {
      delete copy.password;
    } else {
      const password = text(u.password) || text(old?.password);
      if (password) copy.password = password; else delete copy.password;
    }
    active.push(copy);
  }
  return [...hidden, ...active];
}

async function syncRequest(profile: AppProfile, body: Row): Promise<Row> {
  const current = await readMainState();
  const mode = body.mode === "push" ? "push" : "pull";
  let stored = current;
  if (mode === "push") {
    const incoming = body.content && typeof body.content === "object" ? body.content as Row : null;
    if (!incoming) throw new Error("No JSK changes were supplied.");
    if (profile.role === "admin") {
      await ensureAdminAccounts(current, incoming, profile);
      stored = clone(incoming);
      stored.users = await compatUsers(current, incoming);
      stored.session = null;
      if (stored.ui && typeof stored.ui === "object") {
        delete (stored.ui as Row).lastAdminInvite;
        delete (stored.ui as Row).loc;
      }
    } else {
      stored = applyMemberWrites(current, incoming, profile);
    }
    if (profile.role === "admin") fanOutSystemNotifications(current, stored);
    await writeMainState(stored);
  }
  return {
    ok: true,
    content: roleView(stored, profile),
    profile: { id: profile.app_user_id, role: profile.role },
  };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return reply(405, { error: "Use POST." });
  if (!URL || !SERVICE_KEY) return reply(500, { error: "The JSK sync service is not configured." });

  try {
    const body = await request.json() as Row;
    if (body.action === "migrate_legacy_user" || body.action === "migrate_legacy_admin") {
      const email = text(body.email).toLowerCase().trim();
      const password = text(body.password);
      if (!email || !password) return reply(400, { ok: false, code: "invalid_credentials" });
      const result = await provisionLegacyAccount(email, password);
      return reply(200, result);
    }

    const authHeader = request.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return reply(401, { error: "Sign in to continue." });
    const profile = await getProfile(token);
    if (!profile) return reply(403, { error: "This account is not active. Ask an Admin for access." });
    if (body.action === "reset_account_password") {
      const result = await resetAccountPassword(profile, text(body.userId));
      return reply(200, result);
    }
    if (body.action === "register_push_token") {
      const result = await registerPushToken(profile, text(body.token), text(body.platform));
      return reply(200, result);
    }
    if (body.action === "unregister_push_token") {
      const result = await unregisterPushToken(profile, text(body.token));
      return reply(200, result);
    }
    if (body.action === "secure_legacy_accounts") {
      const result = await secureLegacyAccounts(profile);
      return reply(200, result);
    }
    const result = await syncRequest(profile, body);
    return reply(200, result);
  } catch (error) {
    console.error("jsk-sync request failed", error instanceof Error ? error.message : "unknown error");
    const message = error instanceof Error ? error.message : "Could not sync JSK data.";
    return reply(400, { error: message });
  }
});
