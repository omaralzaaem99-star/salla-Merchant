"use strict";

// A public enquiry, not an Auth account, store record, or operational grant.
const crypto = require("node:crypto");
const {StoreAccountManagementError, generatedStoreId} = require("./store_account_management");
const ROOT = "system/storeApplications/requests";
const ADMIN_ACTIONS = new Set(["list_store_applications", "approve_store_application"]);
const hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
const object = (v) => v && typeof v === "object" && !Array.isArray(v) ? v : {};
const fail = (code, message) => { throw new StoreAccountManagementError(code, message); };
function text(value, min, max) {
  if (typeof value !== "string") fail("invalid-argument", "راجع بيانات طلب الحساب.");
  const v = value.trim();
  if (v.length < min || v.length > max || /[\u0000-\u001f]/.test(v)) fail("invalid-argument", "راجع طول البيانات المكتوبة.");
  return v;
}
function phone(value) {
  let v = text(value, 8, 35).replace(/[٠-٩]/g, d => "٠١٢٣٤٥٦٧٨٩".indexOf(d))
      .replace(/[۰-۹]/g, d => "۰۱۲۳۴۵۶۷۸۹".indexOf(d)).replace(/[\s()+-]/g, "");
  if (v.startsWith("00964")) v = `0${v.slice(5)}`;
  else if (v.startsWith("964")) v = `0${v.slice(3)}`;
  if (!/^07[0-9]{9}$/.test(v)) fail("invalid-argument", "اكتب رقم هاتف عراقي صحيحاً مثل 07701234567.");
  return v;
}
function assertAdmin(actor) {
  if (!actor?.uid || (!actor.isGeneralManager && !actor.isBootstrapAdmin)) fail("permission-denied", "طلبات الانضمام متاحة للمدير العام فقط.");
}
function key(value) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) fail("invalid-argument", "معرف الطلب غير صالح.");
  return value;
}
async function quota(database, name, limit, nowMs) {
  const day = new Date(nowMs).toISOString().slice(0, 10);
  const ref = database.ref(`system/storeApplications/limits/${hash(name)}`);
  const initial = object((await ref.get()).val());
  const result = await ref.transaction(raw => {
    if (raw === null && Object.keys(initial).length) return null;
    const v = object(raw), count = v.day === day ? Number(v.count || 0) : 0;
    if (count >= limit) return;
    return {day, count: count + 1};
  });
  if (!result.committed || !result.snapshot.val()) fail("resource-exhausted", "وصلت إلى حد المحاولات اليوم. تواصل مع الدعم عبر واتساب.");
}
async function submit({database, data, ip, applicantUid = '', nowMs = Date.now()}) {
  if (applicantUid) {
    const {withIdentityLifecycleMutation, CustomerAccountDeletionError} = require('./customer_account_deletion');
    try {
      return await withIdentityLifecycleMutation({
        database, uid: applicantUid, role: 'store', mutationKind: 'store_application',
        operationId: `store_application_${hash(String(data.requestId || '')).slice(0,40)}`,
        nowMs, action: () => submitCore({database, data, ip, applicantUid, nowMs}),
      });
    } catch (error) {
      // Preserve a deliberate identity rejection at the merchant callable boundary.
      if (error instanceof CustomerAccountDeletionError) {
        throw new StoreAccountManagementError(error.code, error.message, error.details);
      }
      throw error;
    }
  }
  return submitCore({database, data, ip, applicantUid, nowMs});
}
async function submitCore({database, data, ip, applicantUid = '', nowMs = Date.now()}) {
  if (applicantUid && (typeof applicantUid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(applicantUid))) fail('unauthenticated', 'سجّل الدخول مجدداً.');
  const requestId = text(data.requestId, 20, 100);
  if (!/^[A-Za-z0-9_-]+$/.test(requestId) || data.consent !== true) fail("invalid-argument", "وافق على التواصل بخصوص طلب الحساب.");
  const payload = {storeName: text(data.storeName, 2, 100), phone: phone(data.phone), address: text(data.address, 5, 300)};
  const id = hash(`store-application-v1|${payload.phone}`), digest = hash(JSON.stringify(payload));
  if (!ip) fail("unavailable", "تعذر تأكيد الاتصال. حاول مجدداً.");
  // Rate limit every attempt, including existing phone enquiries; no public lookup.
  await quota(database, `ip:${ip}`, 30, nowMs);
  const ref = database.ref(`${ROOT}/${id}`), initial = object((await ref.get()).val());
  if (applicantUid && !initial.id && (await database.ref(`stores/${generatedStoreId(payload.phone)}`).get()).exists()) {
    fail('already-exists', 'تعذر تقديم حساب بهذا الرقم. سجّل الدخول أو تواصل مع الدعم.');
  }
  if (!initial.id) await quota(database, "global", 1000, nowMs);
  const now = new Date(nowMs).toISOString();
  const result = await ref.transaction(raw => {
    if (raw === null && initial.id) return null;
    const current = object(raw);
    if (current.id) return current; // Never overwrite a prior enquiry or its review.
    return {id, ...payload, requestId, digest, status: "pending", phoneVerified: false,
      ...(applicantUid ? {applicantUid, accountApplication: true} : {}),
      createdAt: now, updatedAt: now, revision: 1, source: "store_guest"};
  });
  if (!result.committed || !result.snapshot.val()?.id) fail("unavailable", "تعذر تأكيد الطلب. أعد المحاولة نفسها.");
  if (applicantUid) {
    const saved = result.snapshot.val();
    if (saved.applicantUid !== applicantUid) fail('already-exists', 'تعذر تقديم حساب بهذا الرقم. سجّل الدخول أو تواصل مع الدعم.');
    if (saved.requestId !== requestId || saved.digest !== digest) fail('failed-precondition', 'يوجد تقديم سابق محفوظ. تابع مراجعته أو تواصل مع الدعم.');
    return {ok: true, received: true, applicationId: id};
  }
  // The identical generic receipt prevents exposing another applicant's details/status.
  return {ok: true, received: true, message: "تم استلام بياناتك أو يوجد طلب سابق لهذا الرقم. تواصل مع الإدارة لمتابعة التفعيل."};
}

// Only the submitting Firebase session can follow this application. An entered
// phone number is never proof of ownership and cannot recover another request.
async function ownStatus({database, uid, data}) {
  if (!uid) fail('unauthenticated', 'جلسة الحساب مطلوبة.');
  const row = object((await database.ref(`${ROOT}/${key(data.applicationId)}`).get()).val());
  if (!row.id || !row.accountApplication || row.applicantUid !== uid) fail('permission-denied', 'لا يمكن الوصول إلى هذا الطلب من هذه الجلسة.');
  if (row.status === 'deletion_scheduled') return {ok: true, status: 'deletion_scheduled'};
  if (row.status !== 'completed' || !row.storeId) return {ok: true, status: 'pending'};
  const store = object((await database.ref(`stores/${row.storeId}`).get()).val());
  const profile = object((await database.ref(`userRoleProfiles/${uid}/store`).get()).val());
  const blocked = new Set(['blocked', 'disabled', 'suspended', 'terminated']);
  if (!Object.keys(store).length || store.active === false ||
      blocked.has(String(store.status || '').toLowerCase()) ||
      blocked.has(String(store.adminStatus || '').toLowerCase()) ||
      profile.active === false || (profile.active === true && profile.entityId !== row.storeId) ||
      (store.authUid && store.authUid !== uid)) {
    return {ok: true, status: 'sign_in_required'};
  }
  if (store.authUid === uid && profile.active === true && profile.entityId === row.storeId) {
    return {ok: true, status: 'active'};
  }
  if (phone(store.phone) !== row.phone) return {ok: true, status: 'sign_in_required'};
  const code = String(store.linkCode || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  if (code.length < 4) return {ok: true, status: 'pending'};
  const invitation = object((await database.ref(`linkInvitations/store/${code}`).get()).val());
  if (invitation.active !== true || invitation.entityId !== row.storeId) return {ok: true, status: 'sign_in_required'};
  // Approved applicants use the existing code-login callable. No new role grant
  // or parallel identity writer; these credentials must never enter public data.
  return {ok: true, status: 'approved', phone: row.phone, linkCode: code, storeName: store.name || row.storeName};
}
async function list({database, actor, data}) {
  assertAdmin(actor);
  let query = database.ref(ROOT).orderByChild("createdAt");
  if (data.cursor) {
    const cursor = object(data.cursor);
    const at = text(cursor.createdAt, 24, 24);
    if (Number.isNaN(Date.parse(at))) fail("invalid-argument", "مؤشر الصفحة غير صالح.");
    query = query.endAt(at, key(cursor.id));
  }
  const rows = [];
  const snapshot = await query.limitToLast(data.cursor ? 32 : 31).get();
  snapshot.forEach(child => { const row = object(child.val()); if (row.id !== data.cursor?.id) rows.push(row); });
  rows.sort((a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id));
  const more = rows.length > 30, page = rows.slice(0, 30);
  const safe = page.map(({requestId, digest, ...row}) => row);
  const last = page.at(-1);
  return {ok: true, applications: safe, nextCursor: more && last ? {createdAt: last.createdAt, id: last.id} : null};
}
async function approve({database, actor, data, nowMs = Date.now()}) {
  assertAdmin(actor);
  const ref = database.ref(`${ROOT}/${key(data.applicationId)}`);
  const before = object((await ref.get()).val());
  if (!before.accountApplication || !before.applicantUid || !before.storeId) fail('failed-precondition', 'أكمل تفاصيل المتجر أولاً.');
  const requestId = text(data.requestId, 20, 120);
  if (data.contactConfirmed !== true) fail('failed-precondition', 'تحقق من صاحب المتجر ورقم التواصل قبل التفعيل.');
  const store = object((await database.ref(`stores/${before.storeId}`).get()).val());
  if (store.active !== true || phone(store.phone) !== before.phone ||
      store.networkAssignmentPending === true || !store.branchId || !store.serviceZoneId ||
      (store.authUid && store.authUid !== before.applicantUid)) fail('failed-precondition', 'راجع تفعيل سجل المتجر وفرعه ومنطقته ورقم الهاتف قبل الموافقة.');
  const result = await ref.transaction(raw => {
    if (raw === null) return null;
    const row = object(raw);
    if (row.storeId !== before.storeId || row.applicantUid !== before.applicantUid) return;
    if (row.status === 'completed') return row;
    if (row.status !== 'prepared' || row.revision !== data.expectedRevision) return;
    return {...row, status: 'completed', revision: row.revision + 1,
      approvedAt: new Date(nowMs).toISOString(), updatedAt: new Date(nowMs).toISOString(),
      approvedBy: actor.uid, approvalRequestId: requestId, contactConfirmed: true};
  });
  if (!result.committed || result.snapshot.val()?.status !== 'completed') fail('aborted', 'تغير الطلب. حدّث القائمة ثم راجعه مجدداً.');
  return {ok: true, status: 'completed'};
}
async function link({database, actor, applicationId, storeId, nowMs = Date.now()}) {
  assertAdmin(actor);
  const id = key(applicationId);
  if (typeof storeId !== "string" || /[.#$\[\]/]/.test(storeId) || !storeId) fail("invalid-argument", "معرف المتجر غير صالح.");
  const store = object((await database.ref(`stores/${storeId}`).get()).val());
  const ref = database.ref(`${ROOT}/${id}`), initial = object((await ref.get()).val());
  if (!initial.id || phone(store.phone) !== initial.phone) fail("failed-precondition", "هاتف المتجر لا يطابق طلب الانضمام.");
  const result = await ref.transaction(raw => {
    if (raw === null && initial.id) return null;
    const row = object(raw);
    if (!row.id || row.phone !== initial.phone || (row.storeId && row.storeId !== storeId) || row.status === 'deletion_scheduled') return;
    if (row.storeId === storeId && ['prepared', 'completed'].includes(row.status)) return row;
    return {...row, storeId, status: row.accountApplication ? 'prepared' : "completed", revision: row.revision + 1,
      updatedAt: new Date(nowMs).toISOString(), reviewedBy: actor.uid};
  });
  if (!result.committed || !result.snapshot.val()?.id) fail("aborted", "تعذر ربط الطلب بالمتجر. أعد المحاولة نفسها.");
  return {ok: true};
}
async function validateRegistration({database, actor, data}) {
  assertAdmin(actor);
  const row = object((await database.ref(`${ROOT}/${key(data.merchantApplicationId)}`).get()).val());
  if (!row.id || row.phone !== phone(data.phone) || row.status === 'deletion_scheduled') fail("failed-precondition", "راجع هاتف وحالة طلب الانضمام قبل إنشاء الحساب.");
}
function cleanupUpdates(root, storeId, storePhone) {
  let normalized = '';
  try { normalized = phone(storePhone); } catch (_) {}
  const rows = object(object(object(root.system).storeApplications).requests);
  return Object.fromEntries(Object.entries(rows).filter(([, raw]) => {
    const row = object(raw);
    return row.storeId === storeId || (!row.storeId && normalized && row.phone === normalized);
  }).map(([id]) => [`${ROOT}/${id}`, null]));
}
module.exports = {ROOT, ADMIN_ACTIONS, phone, submit, ownStatus, list, approve, link, assertAdmin, validateRegistration, cleanupUpdates};
