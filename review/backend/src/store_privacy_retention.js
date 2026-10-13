"use strict";

// Timed execution of the existing store privacy request. No database-root read
// or root transaction: each related record is selected by an indexed query and
// compared again in its own transaction. The store lifecycle lock excludes
// registration/login/catalog writers throughout a resumable purge.
const crypto = require("node:crypto");
const {storeLoginLimitKey, normalizePhoneDigits} = require("./code_login");
const {ROOT, publicRequest} = require("./store_privacy_requests");
const {VERSION} = require("./store_privacy_schedule");
const {StoreAccountManagementError} = require("./store_account_management");
const {storeLifecycleKey, storeLifecycleLockId, storeDeletionAuditId} = require("./store_lifecycle_guard");
const {withBranchGeometryLocks, renewBranchGeometryLocks} = require("./store_operations_control");
const {activeIdentityLifecycleWriters, sharedIdentityUpdates} = require("./customer_account_deletion");
const {deleteStoreMedia} = require("./store_permanent_deletion");
const {syncOperationalOrderReferences} = require("./operational_order_refs");
const PAGE = 200;
const obj = v => v && typeof v === "object" && !Array.isArray(v) ? v : {};
const canonical = v => Array.isArray(v) ? v.map(canonical) : v && typeof v === "object" ?
  Object.fromEntries(Object.keys(v).sort().map(k => [k, canonical(v[k])])) : v;
const same = (a,b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const digest = v => crypto.createHash("sha256").update(JSON.stringify(canonical(v))).digest("hex");
const fail = reason => {throw new StoreAccountManagementError("failed-precondition",
  "لم يكتمل حذف البيانات بعد؛ ستُستكمل العملية نفسها بأمان.", {reason});};

async function records(database, path, field, value, visit) {
  let cursor = "";
  for (let page = 0; page < 100; page++) {
    let q = database.ref(path).orderByChild(field).equalTo(value);
    // RTDB cannot combine equalTo and startAfter. Rebuild the exact value range
    // with a key cursor on subsequent pages.
    if (cursor) q = database.ref(path).orderByChild(field).startAfter(value, cursor).endAt(value);
    const rows = obj((await q.limitToFirst(PAGE).get()).val());
    const keys = Object.keys(rows).sort();
    for (const key of keys) await visit(key, rows[key]);
    if (keys.length < PAGE) return;
    cursor = keys.at(-1);
  }
  fail("privacy_page_limit"); // Resume later; never silently skip excess rows.
}

async function compareRecord(database, path, transform, renew) {
  const ref = database.ref(path), warm = (await ref.get()).val();
  let first = true, rejected;
  await renew();
  const result = await ref.transaction(raw => {
    rejected = null;
    if (first && raw === null && warm !== null) {first = false; return null;}
    first = false;
    try {return transform(raw);} catch (e) {rejected = e; return;}
  }, undefined, false);
  if (rejected) throw rejected;
  if (!result.committed) fail("privacy_record_changed");
  return result.snapshot.val();
}

async function identityFence(database, uid, operation, renew) {
  return compareRecord(database, `customerAccountDeletionLocks/${uid}`, raw => {
    const v = obj(raw);
    if (v.authDeletionFenced === true && v.authDeletionOperationId === operation) return v;
    if (v.authDeleted || v.authDeletionFenced || v.committing ||
        (v.active && Number(v.leaseUntilMs) > Date.now()) || Object.keys(activeIdentityLifecycleWriters(v, Date.now())).length) {
      fail("privacy_identity_busy");
    }
    return {...v, authDeletionFenced: true, authDeletionOperationId: operation,
      authDeletionFencedAt: new Date().toISOString()};
  }, renew);
}

async function purgeOtpIdentity(database, uid, operation, renew) {
  const lockPath = `customerAccountDeletionLocks/${uid}`;
  let fence = obj((await database.ref(lockPath).get()).val());
  if (!fence.storePrivacyOtpPlan) {
    const roots = {}, loaded = new Set();
    const names = ["authOtpRequests","authOtpVerifications","authOtpSessions","authOtpPhoneSessions","authOtpVerifiedPhones"];
    const add = (root,key,v) => {if (v) {roots[root] ||= {}; roots[root][key] = v;}};
    for (const root of names) for (const field of ["uid","customerUid","authUid","identity/uid"]) {
      await records(database,root,field,uid,async (key,v) => add(root,key,v));
    }
    // Follow references using indexed queries/direct keys, including legacy OTP
    // records without uid. Never enumerate the entire authentication database.
    for (let pass=0; pass<20; pass++) {
      const pending=[];
      for (const [root,rows] of Object.entries(roots)) for (const [key,v] of Object.entries(rows)) {
        const token=`${root}/${key}`;
        if (loaded.has(token)) continue;
        loaded.add(token);
        const owner=v.uid || v.customerUid || v.authUid || obj(v.identity).uid;
        if (owner && owner !== uid) continue;
        const requestId = v.requestId || (["authOtpRequests","authOtpSessions"].includes(root) ? key : "");
        if (requestId) {
          for (const name of ["authOtpRequests","authOtpSessions"]) pending.push((async()=>add(name,requestId,(await database.ref(`${name}/${storeLifecycleKey(requestId)}`).get()).val()))());
          for (const name of names.slice(1)) pending.push(records(database,name,"requestId",requestId,async(k,r)=>add(name,k,r)));
        }
        if (v.verificationId) pending.push((async()=>add("authOtpVerifications",v.verificationId,(await database.ref(`authOtpVerifications/${storeLifecycleKey(v.verificationId)}`).get()).val()))());
        const phoneHash=v.phoneHash || (["authOtpPhoneSessions","authOtpVerifiedPhones"].includes(root) ? key : "");
        if (phoneHash) for(const name of ["authOtpPhoneSessions","authOtpVerifiedPhones"]) pending.push((async()=>add(name,phoneHash,(await database.ref(`${name}/${storeLifecycleKey(phoneHash)}`).get()).val()))());
      }
      if (!pending.length) break;
      await Promise.all(pending); await renew();
      if (loaded.size > 2000 || pass===19) fail("privacy_otp_graph_limit");
    }
    const updates=require("./whatsapp_otp_security").whatsappOtpDeletionCleanupUpdates({uid,roots});
    const plan=Object.keys(updates).map(path=>({path,hash:digest(roots[path.split('/')[0]][path.split('/')[1]])}));
    fence=await compareRecord(database,lockPath,raw=>{
      const v=obj(raw); if(v.authDeletionOperationId!==operation || !v.authDeletionFenced) fail("privacy_identity_fence_lost");
      return {...v,storePrivacyOtpPlan:plan.length ? plan : {empty:true}};
    },renew);
  }
  for (const entry of Array.isArray(fence.storePrivacyOtpPlan) ? fence.storePrivacyOtpPlan : []) {
    await compareRecord(database,entry.path,raw=>{
      if(raw===null) return null;
      if(digest(raw)===entry.hash) return null;
      const v=obj(raw), owner=v.uid || v.customerUid || v.authUid || obj(v.identity).uid;
      if(owner && owner!==uid) return raw;
      fail("privacy_otp_record_changed");
    },renew);
  }
}

async function purgeIdentity(database, authAdmin, uid, id, operation, renew) {
  await identityFence(database, uid, operation, renew);
  await compareRecord(database, `userRoleProfiles/${uid}/store`, raw =>
    obj(raw).entityId === id ? null : raw, renew);
  const roles = obj((await database.ref(`userRoleProfiles/${uid}`).get()).val());
  const remaining = Object.entries(roles).map(([roleName, profile]) => ({roleName, profile: obj(profile)}));
  if (remaining.some(v => !["customer", "driver", "admin", "store"].includes(v.roleName) ||
      v.profile.uid !== uid || !v.profile.entityId)) fail("privacy_identity_inconsistent");
  // An orphan operational role is evidence against deleting Auth. Do not guess.
  for (const [collection, roleName] of [["stores","store"],["drivers","driver"],["employees","admin"],
    ["employeeArchive","admin"],["customers","customer"]]) {
    await records(database, collection, "authUid", uid, async (key) => {
      if (collection === "stores" && key === id) return;
      if (!remaining.some(v => v.roleName === roleName && v.profile.entityId === key)) fail("privacy_identity_inconsistent");
    });
  }
  const ownCustomer = (await database.ref(`customers/${uid}`).get()).val();
  if (ownCustomer && !remaining.some(v => v.roleName === "customer" && v.profile.entityId === uid)) fail("privacy_identity_inconsistent");
  remaining.sort((a,b) => Number(b.profile.active === true) - Number(a.profile.active === true) || a.roleName.localeCompare(b.roleName));
  const projections = sharedIdentityUpdates({uid, remainingRoles: remaining}, new Date().toISOString());
  for (const path of [`userProfiles/${uid}`, `accountProfiles/${uid}`]) {
    await compareRecord(database, path, raw => {
      if (!raw) return null;
      const v = obj(raw);
      // Preserve a concurrently refreshed projection of another role.
      const pointsToStore = (v.role === "store" && v.entityId === id) ||
        (v.lastLinkedRole === "store" && v.lastLinkedEntityId === id);
      if (remaining.length && !pointsToStore) return raw;
      return projections[path];
    }, renew);
  }
  for (const [path, field] of [["appErrorLogs","userUid"],["accessRequests","uid"]]) {
    await records(database, path, field, uid, async key => compareRecord(database, `${path}/${key}`, raw => {
      const v = obj(raw);
      return v[field] === uid && (v.role === "store" || v.appName === "تطبيق المتجر" || v.requestedRole === "store") ? null : raw;
    }, renew));
  }
  // Login history is not a financial ledger. Remove the deleted store's UID
  // links, including old device rebindings, without touching another role.
  for (const field of ["uid", "replacedUid"]) {
    await records(database, "securityAudit/codeLogins", field, uid,
      async key => compareRecord(database, `securityAudit/codeLogins/${key}`, raw => {
        const v = obj(raw);
        return v[field] === uid && v.role === "store" && v.entityId === id ? null : raw;
      }, renew));
  }
    await compareRecord(database, `securityAudit/codeLoginLimits/${storeLoginLimitKey("uid", uid)}`, () => null, renew);
    if (!remaining.length) {
    await purgeOtpIdentity(database, uid, operation, renew);
    await renew();
    const freshRoles = obj((await database.ref(`userRoleProfiles/${uid}`).get()).val());
    const fence = obj((await database.ref(`customerAccountDeletionLocks/${uid}`).get()).val());
    if (Object.keys(freshRoles).length || !fence.authDeletionFenced || fence.authDeletionOperationId !== operation) fail("privacy_identity_changed");
    try {await authAdmin.deleteUser(uid);} catch (e) {if (e.code !== "auth/user-not-found") throw e;}
  }
  await compareRecord(database, `customerAccountDeletionLocks/${uid}`, raw => {
    const v = obj(raw);
    if (v.authDeletionOperationId !== operation) fail("privacy_identity_fence_lost");
    return {...v, storePrivacyOtpPlan: null, authDeletionFenced: !remaining.length, authDeleted: !remaining.length,
      ...(remaining.length ? {authDeletionOperationId: null} : {authDeletedAt: new Date().toISOString()})};
  }, renew);
}

async function purgeDueStorePrivacy({database, authAdmin, storageBucket, storeId, expectedRequestId, nowMs = Date.now()}) {
  const id = storeLifecycleKey(storeId), path = `${ROOT}/${id}`;
  const initial = obj((await database.ref(path).get()).val());
  if (initial.version !== VERSION || initial.id !== expectedRequestId) return {skipped: true};
  if (initial.status === "completed") return {ok: true, request: publicRequest(initial), completed: true};
  if (!["scheduled", "purging"].includes(initial.status) || !(Number(initial.deleteAfterMs) > 0) || nowMs < Number(initial.deleteAfterMs)) return {skipped: true};
  if (!authAdmin?.deleteUser || !storageBucket?.getFiles) fail("privacy_cleanup_services_unavailable");
  const source = obj((await database.ref(`stores/${id}`).get()).val());
  const operation = `store_privacy_${initial.id}`;
  return withBranchGeometryLocks({database, branchIds: [storeLifecycleLockId(id), ...(source.branchId ? [source.branchId] : [])],
    fingerprint: crypto.createHash("sha256").update(operation).digest("hex"), kind: "store_privacy_retention"}, async lock => {
    const renew = () => renewBranchGeometryLocks({database, lock});
    let row = obj((await database.ref(path).get()).val());
    if (row.id !== expectedRequestId || row.version !== VERSION || !["scheduled", "purging"].includes(row.status) ||
        !Number.isFinite(Number(row.deleteAfterMs)) || !(Number(row.deleteAfterMs) > 0) || nowMs < Number(row.deleteAfterMs)) return {skipped: true};
    let store = obj((await database.ref(`stores/${id}`).get()).val());
    if (row.status === "scheduled") {
      await records(database, "orders", "storeId", id, async (_, order) => {
        if (!["delivered", "cancelled"].includes(order.status)) fail("privacy_active_order_after_closure");
      });
      const application = row.subjectType === "application";
      if ((!application && (!store.accountDeletionPending || store.authUid !== row.requestedByUid)) ||
          (application && store.authUid && store.authUid !== row.requestedByUid) || store.branchId !== source.branchId) fail("privacy_subject_changed");
      const subjects = new Set([row.requestedByUid]);
      for (const [root, field] of [["userRoleProfiles","store/entityId"],["userProfiles","entityId"],
        ["userProfiles","lastLinkedEntityId"],["accountProfiles","entityId"],["accountProfiles","lastLinkedEntityId"]]) {
        await records(database, root, field, id, async (uid,v) => {
          if (root === "userRoleProfiles" || v.role === "store" || v.lastLinkedRole === "store") subjects.add(storeLifecycleKey(uid));
        });
      }
      if (subjects.size > 100) fail("privacy_identity_limit");
      row = await compareRecord(database, path, raw => {
        if (!same(raw, row)) fail("privacy_request_changed");
        return {...row, status: "purging", purgeSubjects: [...subjects], purgeDone: {},
          message: row.deletionMode === "immediate" ? "جارٍ حذف بيانات الحساب نهائياً." :
            "انتهت مهلة الاسترجاع؛ جارٍ استكمال الحذف النهائي.", updatedAt: new Date(nowMs).toISOString()};
      }, renew);
    }
    // Once claimed, restoration is impossible. Resuming never reselects new identities.
    for (const uid of row.purgeSubjects || []) {
      storeLifecycleKey(uid);
      if (obj(row.purgeDone)[uid]) continue;
      await purgeIdentity(database, authAdmin, uid, id, operation, renew);
      await renew();
      await database.ref(`${path}/purgeDone/${uid}`).set(true);
    }
    for (const [root, field] of [["linkInvitations/store","entityId"],["storeIdentityIndex/phone","storeId"],
      ["system/storeApplications/requests","storeId"]]) {
      await records(database, root, field, id, async key => compareRecord(database, `${root}/${key}`,
        raw => obj(raw)[field] === id ? null : raw, renew));
    }
    if (row.phone) await compareRecord(database,
      `securityAudit/codeLoginLimits/${storeLoginLimitKey("account", normalizePhoneDigits(row.phone))}`,
      () => null, renew);
    if (row.phone) await records(database, "system/storeApplications/requests", "phone", row.phone,
      async key => compareRecord(database, `system/storeApplications/requests/${key}`, raw => {
        const v = obj(raw); return v.phone === row.phone && (!v.storeId || v.storeId === id) ? null : raw;
      }, renew));
    if (row.applicationId) await compareRecord(database, `system/storeApplications/requests/${storeLifecycleKey(row.applicationId)}`, raw => {
      if (raw && obj(raw).applicantUid !== row.requestedByUid) fail("privacy_application_changed");
      return null;
    }, renew);
    // Order numbers, amounts and settlements remain intact; contact is not
    // needed for that financial evidence after the retention period.
    const clearReferralContact = async (key, requireBinding = false) => {
      await compareRecord(database, `storeReferrals/${storeLifecycleKey(key)}`, raw => {
        if (!raw) return null;
        if (obj(raw).linkedStoreId !== id) {
          if (requireBinding) fail("privacy_referral_binding_changed");
          return raw;
        }
        const next = {...raw};
        for (const field of ["phone", "phoneNormalized", "linkedStorePhone", "storeAddress"]) delete next[field];
        return next; // Driver reward amounts and qualifying orders remain intact.
      }, renew);
    };
    if (store.storeReferralId) await clearReferralContact(store.storeReferralId, true);
    // A legacy/missing reverse pointer must not leave the referred merchant's
    // contact behind. Use the indexed forward binding and preserve reward data.
    await records(database, "storeReferrals", "linkedStoreId", id, async key => {
      if (key !== store.storeReferralId) await clearReferralContact(key);
    });
    await records(database, "orders", "storeId", id, async key => {
      const order = await compareRecord(database, `orders/${key}`, raw => {
        if (obj(raw).storeId !== id) return raw;
        if (!["delivered", "cancelled"].includes(obj(raw).status)) fail("privacy_active_order_after_closure");
        const next = {...raw};
        // Pickup contact/location is not part of the financial evidence. Keeping
        // these snapshots contradicted the in-app promise to erase the address.
        // checkout_pricing and store_external_delivery also store pickup location
        // as lat/lng. Delivery coordinates and the other parties' data are separate.
        for (const field of ["storePhone", "storeAddress", "storeLat", "storeLng", "lat", "lng"]) delete next[field];
        return next;
      }, renew);
      if (obj(order).storeId !== id) return;
      // Do not report erasure while a terminal order's old public projection
      // still contains pickup contact. Reuse the canonical convergence writer.
      await renew();
      await syncOperationalOrderReferences({database, orderId: key, before: order, after: order});
      await renew();
    });
    for (const root of ["storeCatalog", "storeCatalogPublic", "notificationDevices/store", "notifications/store", "operationalOrderRefs/stores",
      "system/storeExternalDelivery/tables", "system/storeExternalDelivery/reportAccess"]) {
      await compareRecord(database, `${root}/${id}`, () => null, renew);
    }
    store = await compareRecord(database, `stores/${id}`, raw => {
      const v = obj(raw);
      if (v.privacyRequestId === row.id && v.accountDeleted) return v;
      if (row.subjectType === "application" ? (v.authUid && v.authUid !== row.requestedByUid) :
          (!v.accountDeletionPending || v.authUid !== row.requestedByUid)) fail("privacy_subject_changed");
      const retired = {id, name: "متجر محذوف", active: false, accountDeleted: true, accountDeletionPending: true,
        storeStatus: "banned", storeStatusLocked: true, isOnline: false, acceptingOrders: false,
        privacyRequestId: row.id, privacyDeletedAt: new Date(nowMs).toISOString()};
      for (const k of ["branchId","provinceId","agencyId","settlementMode","commissionPercent","storeReferralId",
        "lastSettlementAt","lastSettlementAmount","lastSettlementOrderCount"]) if (v[k] !== undefined) retired[k] = v[k];
      return retired;
    }, renew);
    await compareRecord(database, path, raw => {
      const v = obj(raw); if (v.id !== row.id || v.status !== "purging") fail("privacy_request_changed");
      return {...v, phone: null, storeName: v.deletionMode === "immediate" ? v.storeName : "متجر محذوف", priorState: null};
    }, renew);
    await renew(); await deleteStoreMedia(storageBucket, id); await renew();
    await compareRecord(database, `auditLogs/${storeDeletionAuditId(id)}`, raw => {
      if (raw && obj(raw).requestId !== row.id) fail("privacy_audit_conflict");
      return {id: storeDeletionAuditId(id), action: "delete_store_privacy", requestId: row.id,
        targetType: "deleted_store", targetId: id, targetName: row.deletionMode === "immediate" ? row.storeName : "متجر محذوف", status: "completed",
        createdAt: new Date(nowMs).toISOString(), visibility: "مدير فقط"};
    }, renew);
    const completed = await compareRecord(database, path, raw => {
      const v = obj(raw); if (v.id !== row.id || v.status !== "purging") fail("privacy_request_changed");
      return {id: v.id, storeId: id, version: VERSION, status: "completed",
        storeName: v.deletionMode === "immediate" ? v.storeName : "متجر محذوف",
        ...(v.deletionMode === "immediate" ? {deletionMode: "immediate", requestId: v.requestId,
          ownerHash: require("./store_privacy_schedule").ownerHash(v.requestedByUid),
          ...(v.applicationId ? {applicationId: v.applicationId} : {})} : {}),
        createdAt: v.createdAt, deleteAfter: v.deleteAfter, completedAt: new Date(nowMs).toISOString(),
        updatedAt: new Date(nowMs).toISOString(), message: "اكتمل الحذف النهائي لبيانات حساب المتجر. بقيت السجلات المالية والأدوار الأخرى إن وجدت."};
    }, renew);
    return {ok: true, request: publicRequest(completed), completed: true};
  });
}

// New confirmations run the bounded purge in this same callable. The existing
// durable receipt/scheduler resumes a partial purge; never claim success early.
async function deleteStorePrivacyNow(options) {
  const {database, uid, data} = options;
  const accepted = await require("./store_privacy_schedule").scheduleStorePrivacyDeletion(options);
  if (data.graceDays !== 0 || accepted.completed || accepted.request?.deletionMode !== "immediate") return accepted;
  try {
    const result = await purgeDueStorePrivacy({...options, storeId: accepted.request.storeId,
      expectedRequestId: accepted.request.id});
    if (result.completed) return {...result, signOut: true};
  } catch (error) {
    console.warn("store_privacy_immediate_retry", {reason: String(error.details?.reason || error.code || "unavailable").slice(0,100)});
  }
  return {ok: true, request: publicRequest(obj((await database.ref(`${ROOT}/${accepted.request.storeId}`).get()).val())),
    signOut: true, completed: false};
}

async function reconcileStorePrivacyRetention({database, authAdmin, storageBucket, nowMs = Date.now()}) {
  const rows = obj((await database.ref(ROOT).orderByChild("nextAttemptAtMs").startAt(1).endAt(nowMs).limitToFirst(5).get()).val());
  const result = {checked: 0, completed: 0, failed: 0};
  for (const [storeId, row] of Object.entries(rows)) {
    if (row.version !== VERSION || !["scheduled","purging"].includes(row.status)) continue;
    result.checked++;
    try {const value = await purgeDueStorePrivacy({database, authAdmin, storageBucket, storeId, expectedRequestId: row.id, nowMs});
      if (value.completed) result.completed++;
    } catch (error) {
      result.failed++;
      // Preserve the promised deletion deadline; only the retry cursor moves,
      // so one unavailable record cannot starve all later requests.
      await compareRecord(database, `${ROOT}/${storeLifecycleKey(storeId)}`, raw => {
        const v = obj(raw);
        if (v.id !== row.id || !["scheduled","purging"].includes(v.status)) return raw;
        return {...v, nextAttemptAtMs: nowMs + 15*60*1000, lastPurgeError: String(error.details?.reason || error.code || "unavailable").slice(0,100)};
      }, async () => {});
    }
  }
  return result;
}
module.exports = {records, compareRecord, purgeDueStorePrivacy, reconcileStorePrivacyRetention, deleteStorePrivacyNow};
