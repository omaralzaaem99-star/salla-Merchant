"use strict";

const crypto = require("node:crypto");
const {
  CustomerAccountDeletionError,
  withIdentityLifecycleMutation,
} = require("./customer_account_deletion");

const supportedRoles = new Set(["customer", "driver", "store", "admin"]);
const roleCollections = Object.freeze({
  customer: "customers",
  driver: "drivers",
  store: "stores",
  admin: "employees",
});
const blockedStatuses = new Set([
  "blocked",
  "disabled",
  "suspended",
  "terminated",
]);

class CodeLoginError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = "CodeLoginError";
    this.code = code;
    this.details = details;
  }
}

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value : {};
}

function normalizeCode(value) {
  return String(value || "").replace(/[^A-Za-z0-9]/g, "").toUpperCase();
}

function normalizeName(value) {
  return String(value || "").trim().replace(/\s+/g, " ");
}

function normalizeNameKey(value) {
  return normalizeName(value)
      .toLocaleLowerCase("ar")
      // Employee names are often entered with or without Arabic marks, hamza
      // forms, tatweel, or a space inside compound names such as عبد الأمير.
      // Keep the full-name factor, but compare its canonical Arabic letters so
      // a harmless keyboard spelling difference does not block first login.
      .replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, "")
      .replace(/\u0640/g, "")
      .replace(/[\u0622\u0623\u0625\u0671]/g, "\u0627")
      .replace(/\u0649/g, "\u064A")
      .replace(/\s+/g, "");
}

function normalizePhoneDigits(value) {
  let digits = String(value || "")
      .replace(/[٠-٩]/g, (digit) =>
        String("٠١٢٣٤٥٦٧٨٩".indexOf(digit)))
      .replace(/[۰-۹]/g, (digit) =>
        String("۰۱۲۳۴۵۶۷۸۹".indexOf(digit)))
      .replace(/[^0-9]/g, "");
  if (digits.startsWith("9640")) {
    digits = `964${digits.slice(4)}`;
  } else if (digits.startsWith("0") && digits.length === 11) {
    digits = `964${digits.slice(1)}`;
  } else if (digits.startsWith("7") && digits.length === 10) {
    digits = `964${digits}`;
  }
  return digits;
}

function safeDatabaseKey(value, label) {
  const key = String(value || "").trim();
  if (!key || key.length > 160 || /[.#$/[\]]/.test(key)) {
    throw new CodeLoginError("failed-precondition", `${label} غير صالح.`);
  }
  return key;
}

function operationalRecordBlocked(record) {
  const value = asObject(record);
  if (value.accountDeletionPending === true || value.accountDeleted === true) return true;
  if (value.active === false) return true;
  const status = String(value.status || "").trim().toLowerCase();
  const adminStatus = String(value.adminStatus || "").trim().toLowerCase();
  return blockedStatuses.has(status) || blockedStatuses.has(adminStatus);
}

function identityFor({
  uid,
  role,
  entityId,
  requestedName,
  phone,
  invitation,
  entity,
}) {
  const storedName = normalizeName(
      entity.name ||
      entity.driverName ||
      invitation.entityName ||
      requestedName,
  );
  const storedPhone = normalizeName(
      entity.phone ||
      entity.driverPhone ||
      invitation.phone ||
      phone,
  );
  const identity = {
    uid,
    role,
    entityId,
    name: storedName || {
      customer: "عميل سلة",
      driver: "سائق سلة",
      store: "متجر سلة",
      admin: "موظف الإدارة",
    }[role],
    phone: storedPhone,
    email: normalizeName(entity.email),
    active: true,
  };
  for (const field of [
    "provinceId",
    "provinceName",
    "branchId",
    "branchName",
    "ownershipType",
    "agencyId",
    "agencyName",
  ]) {
    const value = normalizeName(entity[field]);
    if (value) identity[field] = value;
  }
  return identity;
}

function employeeIdForUid(uid) {
  const normalized = String(uid || "")
      .replace(/[^A-Za-z0-9]/g, "")
      .toUpperCase();
  const suffix = normalized.length <= 10 ?
    normalized : normalized.slice(0, 10);
  return `EMP-${suffix}`;
}

async function claimBootstrapAdmin({database, uid}) {
  const bootstrapRef = database.ref("system/bootstrap/adminUid");
  const transaction = await bootstrapRef.transaction((current) => {
    const existing = String(current || "").trim();
    if (existing && existing !== uid) return;
    return uid;
  });
  if (!transaction.committed ||
      String(transaction.snapshot.val() || "").trim() !== uid) {
    throw new CodeLoginError("permission-denied", "تعذر فتح حساب الإدارة.");
  }
}

async function bootstrapFirstAdmin({
  database,
  uid,
  requestedName,
  phone,
  linkCode,
  loginCode,
  now,
  nowMs,
}) {
  const [employeesSnapshot, bootstrapSnapshot] = await Promise.all([
    database.ref("employees").limitToFirst(1).get(),
    database.ref("system/bootstrap/adminUid").get(),
  ]);
  const bootstrapUid = String(bootstrapSnapshot.val() || "").trim();
  if (employeesSnapshot.exists() || (bootstrapUid && bootstrapUid !== uid)) {
    throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
  }
  await claimBootstrapAdmin({database, uid});
  const entityId = employeeIdForUid(uid);
  const name = normalizeName(requestedName) || "المدير العام";
  const identity = {
    uid,
    role: "admin",
    entityId,
    name,
    phone,
    email: "",
    active: true,
  };
  const identityMap = {
    ...identity,
    linkedWithCode: true,
    createdAt: now,
    updatedAt: now,
    lastSeenAt: now,
  };
  const auditId = database.ref("securityAudit/codeLogins").push().key ||
    crypto.randomUUID().replace(/-/g, "");
  await database.ref().update({
    [`employees/${entityId}`]: {
      id: entityId,
      authUid: uid,
      phone,
      email: "",
      linkCode,
      loginCode,
      name,
      role: "admin",
      jobType: "مدير عام",
      roleTitle: "مدير عام",
      active: true,
      status: "متصل الآن",
      lastAction: "تسجيل دخول آمن",
      createdAt: now,
      updatedAt: now,
    },
    [`linkInvitations/admin/${linkCode}`]: {
      role: "admin",
      entityId,
      entityName: name,
      phone,
      phoneNormalized: normalizePhoneDigits(phone),
      linkCode,
      active: true,
      createdBy: "",
      createdByName: "الإدارة",
      createdAt: now,
      updatedAt: now,
    },
    [`adminLoginSecrets/${linkCode}/${loginCode}`]: {
      role: "admin",
      entityId,
      linkCode,
      loginCode,
      active: true,
      createdAt: now,
      updatedAt: now,
    },
    [`userRoleProfiles/${uid}/admin`]: identityMap,
    [`userProfiles/${uid}`]: identityMap,
    [`accountProfiles/${uid}`]: {
      ...identity,
      requestedName: name,
      linkedWithCode: true,
      lastLinkedRole: "admin",
      lastLinkedEntityId: entityId,
      lastLinkedName: name,
      updatedAt: now,
      lastSeenAt: now,
    },
    [`securityAudit/codeLogins/${auditId}`]: {
      eventId: auditId,
      uid,
      role: "admin",
      entityId,
      kind: "bootstrap",
      createdAt: now,
      createdAtMs: nowMs,
    },
  });
  return {identity, bootstrapped: true};
}

function codeLoginInput(rawInput) {
  const input = asObject(rawInput);
  const role = String(input.role || "").trim().toLowerCase();
  if (!supportedRoles.has(role)) {
    throw new CodeLoginError("invalid-argument", "نوع الحساب غير صالح.");
  }
  const linkCode = normalizeCode(input.linkCode);
  const loginCode = normalizeCode(input.loginCode);
  if (linkCode.length < 4 || (role === "admin" && loginCode.length < 4)) {
    throw new CodeLoginError("invalid-argument", "بيانات الدخول غير مكتملة.");
  }
  const phone = normalizeName(input.phone);
  const phoneDigits = normalizePhoneDigits(phone);
  if (phoneDigits.length < 10) {
    throw new CodeLoginError("invalid-argument", "رقم الهاتف غير صالح.");
  }
  return {
    role,
    linkCode,
    loginCode,
    phone,
    phoneDigits,
    requestedName: normalizeName(input.requestedName),
  };
}

function legacyAdminInvitation({
  employeeId,
  employee,
  linkCode,
  now,
}) {
  return {
    role: "admin",
    entityId: employeeId,
    entityName: normalizeName(employee.name),
    phone: normalizeName(employee.phone),
    phoneNormalized: normalizePhoneDigits(employee.phone),
    linkCode,
    active: true,
    createdBy: "system",
    createdByName: "النظام",
    createdAt: normalizeName(employee.createdAt) || now,
    updatedAt: now,
    compatibilityRepair: true,
  };
}

function legacyAdminSecret({
  employeeId,
  linkCode,
  loginCode,
  now,
}) {
  return {
    role: "admin",
    entityId: employeeId,
    linkCode,
    loginCode,
    active: true,
    createdAt: now,
    updatedAt: now,
    compatibilityRepair: true,
  };
}

function validAdminLoginIndex(record, employeeId) {
  const value = asObject(record);
  return value.active === true &&
    String(value.role || "").trim().toLowerCase() === "admin" &&
    String(value.entityId || "").trim() === employeeId;
}

async function repairAdminInvitationMetadata({
  database,
  data,
  entityId,
  invitation,
  employee,
  now,
  nowMs,
}) {
  const employeeName = normalizeName(employee.name);
  const employeePhone = normalizeName(employee.phone);
  const employeePhoneDigits = normalizePhoneDigits(employeePhone);
  const observedInvitationName = normalizeNameKey(invitation.entityName);
  const metadataAlreadyCurrent =
    observedInvitationName === normalizeNameKey(employeeName) &&
    normalizePhoneDigits(invitation.phone) === employeePhoneDigits &&
    normalizePhoneDigits(invitation.phoneNormalized) === employeePhoneDigits;
  if (metadataAlreadyCurrent) return false;

  const invitationRef = database
      .ref(`linkInvitations/admin/${data.linkCode}`);
  const transaction = await invitationRef.transaction((current) => {
    if (!validAdminLoginIndex(current, entityId)) return;
    const value = asObject(current);
    if (normalizeNameKey(value.entityName) !== observedInvitationName ||
        normalizePhoneDigits(value.phone) !== data.phoneDigits) {
      return;
    }
    return {
      ...value,
      entityName: employeeName,
      phone: employeePhone,
      phoneNormalized: employeePhoneDigits,
      updatedAt: now,
      compatibilityRepair: true,
    };
  });
  if (!transaction.committed) return false;

  const repairAuditId =
    `legacy_admin_invitation_metadata_repair_${entityId}`;
  await database.ref(`securityAudit/codeLogins/${repairAuditId}`)
      .transaction((current) => current || {
        eventId: repairAuditId,
        role: "admin",
        entityId,
        kind: "legacy_admin_invitation_metadata_repair",
        repairedName: true,
        createdAt: now,
        createdAtMs: nowMs,
      });
  return true;
}

async function createAdminLoginIndexIfMissing({
  reference,
  value,
  employeeId,
}) {
  const transaction = await reference.transaction((current) => {
    if (current !== undefined && current !== null) return;
    return value;
  });
  return {
    created: transaction.committed,
    valid: transaction.snapshot.exists() &&
      validAdminLoginIndex(transaction.snapshot.val(), employeeId),
  };
}

function staleRoleProfileUpdates({
  profiles,
  role,
  entityId,
  authenticatedUid,
  now,
}) {
  const updates = {};
  const records = asObject(profiles);
  for (const [uid, roles] of Object.entries(records)) {
    if (uid === authenticatedUid) continue;
    const profile = asObject(asObject(roles)[role]);
    if (profile.active !== true ||
        String(profile.entityId || "").trim() !== entityId) {
      continue;
    }
    updates[`userRoleProfiles/${uid}/${role}/active`] = false;
    updates[`userRoleProfiles/${uid}/${role}/revokedAt`] = now;
    updates[`userRoleProfiles/${uid}/${role}/replacedByUid`] =
      authenticatedUid;
  }
  return updates;
}

async function repairLegacyBootstrapAdminLogin({
  database,
  data,
  now,
  nowMs,
}) {
  if (data.role !== "admin") return false;
  const bootstrapSnapshot = await database
      .ref("system/bootstrap/adminUid")
      .get();
  const bootstrapUid = String(bootstrapSnapshot.val() || "").trim();
  if (!bootstrapUid) return false;
  const employeeId = employeeIdForUid(bootstrapUid);
  const employeeRef = database.ref(`employees/${employeeId}`);
  const invitationRef = database
      .ref(`linkInvitations/admin/${data.linkCode}`);
  const secretRef = database
      .ref(`adminLoginSecrets/${data.linkCode}/${data.loginCode}`);
  const [employeeSnapshot, invitationSnapshot, secretSnapshot] =
    await Promise.all([
      employeeRef.get(),
      invitationRef.get(),
      secretRef.get(),
    ]);
  const employee = asObject(employeeSnapshot.val());
  if (!employeeSnapshot.exists() ||
      String(employee.id || "").trim() !== employeeId ||
      String(employee.role || "").trim().toLowerCase() !== "admin" ||
      normalizeNameKey(employee.roleTitle || employee.jobType) !==
        normalizeNameKey("مدير عام") ||
      operationalRecordBlocked(employee) ||
      normalizeNameKey(employee.name) !==
        normalizeNameKey(data.requestedName) ||
      normalizePhoneDigits(employee.phone) !== data.phoneDigits ||
      normalizeCode(employee.linkCode) !== data.linkCode ||
      normalizeCode(employee.loginCode) !== data.loginCode) {
    return false;
  }
  if (invitationSnapshot.exists() &&
      !validAdminLoginIndex(invitationSnapshot.val(), employeeId)) {
    return false;
  }
  if (secretSnapshot.exists() &&
      !validAdminLoginIndex(secretSnapshot.val(), employeeId)) {
    return false;
  }
  if (invitationSnapshot.exists() && secretSnapshot.exists()) return false;

  const invitationResult = invitationSnapshot.exists() ?
    {created: false, valid: true} :
    await createAdminLoginIndexIfMissing({
      reference: invitationRef,
      value: legacyAdminInvitation({
        employeeId,
        employee,
        linkCode: data.linkCode,
        now,
      }),
      employeeId,
    });
  if (!invitationResult.valid) return false;
  const secretResult = secretSnapshot.exists() ?
    {created: false, valid: true} :
    await createAdminLoginIndexIfMissing({
      reference: secretRef,
      value: legacyAdminSecret({
        employeeId,
        linkCode: data.linkCode,
        loginCode: data.loginCode,
        now,
      }),
      employeeId,
    });
  if (!secretResult.valid) return false;
  if (!invitationResult.created && !secretResult.created) return false;

  const repairAuditId =
    `legacy_admin_login_index_repair_${employeeId}`;
  await database.ref(`securityAudit/codeLogins/${repairAuditId}`)
      .transaction((current) => current || {
        eventId: repairAuditId,
        role: "admin",
        entityId: employeeId,
        kind: "legacy_admin_login_index_repair",
        repairedInvitation: invitationResult.created,
        repairedSecret: secretResult.created,
        createdAt: now,
        createdAtMs: nowMs,
      });
  return true;
}

async function linkAccountWithCodeCore({
  database,
  uid,
  input,
  nowMs = Date.now(),
  allowFirstAdminBootstrap = false,
  expectedStoreId,
}) {
  const authenticatedUid = safeDatabaseKey(uid, "جلسة الدخول");
  const data = codeLoginInput(input);
  const now = new Date(nowMs).toISOString();
  await repairLegacyBootstrapAdminLogin({
    database,
    data,
    now,
    nowMs,
  });
  const invitationSnapshot = await database
      .ref(`linkInvitations/${data.role}/${data.linkCode}`)
      .get();
  const invitation = asObject(invitationSnapshot.val());
  if (!invitationSnapshot.exists() || invitation.active !== true) {
    if (data.role === "admin" && allowFirstAdminBootstrap === true) {
      return bootstrapFirstAdmin({
        database,
        uid: authenticatedUid,
        requestedName: data.requestedName,
        phone: data.phone,
        linkCode: data.linkCode,
        loginCode: data.loginCode,
        now,
        nowMs,
      });
    }
    throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
  }
  if (String(invitation.role || data.role).trim().toLowerCase() !== data.role) {
    throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
  }
  const entityId = safeDatabaseKey(invitation.entityId, "معرّف الحساب");
  if (data.role === "store" && expectedStoreId && entityId !== expectedStoreId) {
    throw new CodeLoginError("aborted", "تغير ربط الحساب. أعد تسجيل الدخول.");
  }
  const invitationPhone = normalizePhoneDigits(invitation.phone);
  if (invitationPhone && invitationPhone !== data.phoneDigits) {
    throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
  }
  if (data.role === "admin") {
    const secretSnapshot = await database
        .ref(`adminLoginSecrets/${data.linkCode}/${data.loginCode}`)
        .get();
    const secret = asObject(secretSnapshot.val());
    if (!secretSnapshot.exists() ||
        secret.active !== true ||
        String(secret.entityId || "") !== entityId) {
      throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
    }
  }

  const collection = roleCollections[data.role];
  const entityRef = database.ref(`${collection}/${entityId}`);
  const entitySnapshot = await entityRef.get();
  const currentEntity = asObject(entitySnapshot.val());
  if (!entitySnapshot.exists() || operationalRecordBlocked(currentEntity)) {
    throw new CodeLoginError(
        "failed-precondition",
        "الحساب غير موجود أو موقوف من الإدارة.",
    );
  }
  const entityPhone = normalizePhoneDigits(
      currentEntity.phone || currentEntity.driverPhone,
  );
  if (entityPhone && entityPhone !== data.phoneDigits) {
    throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
  }
  if (data.role === "admin") {
    const entityName = normalizeNameKey(currentEntity.name);
    if (!entityName ||
        entityName !== normalizeNameKey(data.requestedName)) {
      throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
    }
  }
  const shouldRepairAdminInvitationMetadata =
    data.role === "admin" &&
    normalizeNameKey(invitation.entityName) !==
      normalizeNameKey(currentEntity.name);
  const previousUid = String(currentEntity.authUid || "").trim();

  const transaction = await entityRef.transaction((current) => {
    if (current === null) {
      // A cold RTDB transaction can run once with an empty local cache before
      // the server returns the real value. Returning null keeps the transaction
      // alive so Firebase can retry it with the authoritative record.
      return null;
    }
    if (typeof current !== "object" || operationalRecordBlocked(current)) {
      return;
    }
    const next = {
      ...current,
      authUid: authenticatedUid,
      linkedAt: now,
      linkedByUid: authenticatedUid,
      lastCodeLoginAt: now,
      updatedAt: now,
    };
    if (data.role === "driver") {
      next.registrationStatus = "linked";
      next.status = "offline";
      next.isOnline = false;
      next.acceptingOrders = false;
    } else if (data.role === "admin") {
      next.status = "متصل الآن";
      next.lastAction = "تسجيل دخول آمن";
    }
    return next;
  });
  if (!transaction.committed || !transaction.snapshot.exists()) {
    throw new CodeLoginError(
        "failed-precondition",
        "الحساب غير موجود أو موقوف من الإدارة.",
    );
  }
  if (shouldRepairAdminInvitationMetadata) {
    try {
      await repairAdminInvitationMetadata({
        database,
        data,
        entityId,
        invitation,
        employee: currentEntity,
        now,
        nowMs,
      });
    } catch (_) {
      // Metadata compatibility repair must never block a valid login.
    }
  }

  const identity = identityFor({
    uid: authenticatedUid,
    role: data.role,
    entityId,
    requestedName: data.requestedName,
    phone: data.phone,
    invitation,
    entity: currentEntity,
  });
  const identityMap = {
    ...identity,
    linkedWithCode: true,
    createdAt: now,
    updatedAt: now,
    lastSeenAt: now,
  };
  const auditId = database.ref("securityAudit/codeLogins").push().key ||
    crypto.randomUUID().replace(/-/g, "");
  const roleProfilesSnapshot = await database.ref("userRoleProfiles").get();
  const updates = {
    ...staleRoleProfileUpdates({
      profiles: roleProfilesSnapshot.val(),
      role: data.role,
      entityId,
      authenticatedUid,
      now,
    }),
    [`userRoleProfiles/${authenticatedUid}/${data.role}`]: identityMap,
    [`userProfiles/${authenticatedUid}`]: identityMap,
    [`accountProfiles/${authenticatedUid}`]: {
      ...identity,
      requestedName: data.requestedName,
      linkedWithCode: true,
      lastLinkedRole: data.role,
      lastLinkedEntityId: entityId,
      lastLinkedName: identity.name,
      updatedAt: now,
      lastSeenAt: now,
    },
    [`securityAudit/codeLogins/${auditId}`]: {
      eventId: auditId,
      uid: authenticatedUid,
      role: data.role,
      entityId,
      kind: previousUid && previousUid !== authenticatedUid ?
        "rebind" : "login",
      replacedUid: previousUid && previousUid !== authenticatedUid ?
        previousUid : "",
      createdAt: now,
      createdAtMs: nowMs,
    },
  };
  if (previousUid && previousUid !== authenticatedUid) {
    updates[`userRoleProfiles/${previousUid}/${data.role}/active`] = false;
    updates[`userRoleProfiles/${previousUid}/${data.role}/revokedAt`] = now;
    updates[`userRoleProfiles/${previousUid}/${data.role}/replacedByUid`] =
      authenticatedUid;
  }
  await database.ref().update(updates);
  return {
    identity,
    bootstrapped: false,
    rebound: Boolean(previousUid && previousUid !== authenticatedUid),
  };
}

function codeLoginLifecycleOperationId(uid, data) {
  return `code_role_link_${crypto
      .createHash("sha256")
      .update([
        String(uid || ""),
        String(data.role || ""),
        String(data.linkCode || ""),
      ].join("\u001f"))
      .digest("hex")
      .slice(0, 40)}`;
}

// Count before credential lookup, including failures. Anonymous UIDs can be
// rotated, so the normalized account and server-observed IP have independent
// budgets. Store only hashes and counters, never phone numbers or access codes.
function storeLoginLimitKey(scope, value) {
  return crypto.createHash("sha256").update(`store-login|${scope}|${value}`).digest("hex");
}

async function consumeStoreLoginBudget({database, uid, data, ip, nowMs = Date.now()}) {
  const windowMs = 10 * 60 * 1000;
  for (const [scope, value, limit] of [["uid", uid, 20], ["account", data.phoneDigits, 20],
    ...(ip ? [["ip", ip, 100]] : [])]) {
    const key = storeLoginLimitKey(scope, value);
    const ref = database.ref(`securityAudit/codeLoginLimits/${key}`);
    const warm = (await ref.get()).val();
    let first = true;
    const result = await ref.transaction(raw => {
      if (first && raw === null && warm !== null) {first = false; return null;}
      first = false;
      const row = asObject(raw);
      const current = Number(row.expiresAtMs) > nowMs;
      const count = current ? Number(row.count || 0) : 0;
      if (count >= limit) return;
      return {count: count + 1, expiresAtMs: current ? row.expiresAtMs : nowMs + windowMs};
    }, undefined, false);
    if (!result.committed || !result.snapshot.val()) {
      throw new CodeLoginError("resource-exhausted", "محاولات دخول كثيرة. انتظر 10 دقائق ثم حاول مجدداً.");
    }
  }
}

async function linkAccountWithCode(options = {}) {
  const database = options.database;
  const authenticatedUid = safeDatabaseKey(options.uid, "جلسة الدخول");
  const data = codeLoginInput(options.input);
  if (data.role === "store" && !options.expectedStoreId) {
    await consumeStoreLoginBudget({database, uid: authenticatedUid, data, ip: options.ip, nowMs: options.nowMs});
  }
  try {
    if (data.role === "store" && !options.expectedStoreId) {
      // Lock only after validating the credentials; never expose deletion state
      // by looking up a phone number alone. Revalidate the binding inside core.
      const invitation = asObject((await database.ref(`linkInvitations/store/${data.linkCode}`).get()).val());
      if (invitation.active !== true || String(invitation.role || "store").trim().toLowerCase() !== "store") {
        throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
      }
      const id = safeDatabaseKey(invitation.entityId, "معرّف الحساب");
      const phone = normalizePhoneDigits(invitation.phone) ||
        normalizePhoneDigits((await database.ref(`stores/${id}/phone`).get()).val());
      if (!phone || phone !== data.phoneDigits) {
        throw new CodeLoginError("permission-denied", "بيانات الدخول غير صحيحة.");
      }
      return await require("./store_lifecycle_guard").withStoreLifecycleReadLock({
        database, storeIds: [id], kind: "store_code_login", allowPendingDeletion: false,
      }, guarded => linkAccountWithCode({...options, database: guarded, expectedStoreId: id}));
    }
    return await withIdentityLifecycleMutation({
      database,
      uid: authenticatedUid,
      operationId: codeLoginLifecycleOperationId(authenticatedUid, data),
      role: data.role,
      mutationKind: "role_link",
      nowMs: options.nowMs,
      action: () => linkAccountWithCodeCore({
        ...options,
        uid: authenticatedUid,
        input: data,
      }),
    });
  } catch (error) {
    if (error instanceof CustomerAccountDeletionError || error.name === "StoreLifecycleError" || error.name === "StoreOperationsControlError") {
      throw new CodeLoginError(error.code, error.message, error.details);
    }
    throw error;
  }
}

module.exports = {
  storeLoginLimitKey,
  CodeLoginError,
  codeLoginInput,
  employeeIdForUid,
  linkAccountWithCode,
  normalizeCode,
  normalizePhoneDigits,
  operationalRecordBlocked,
  staleRoleProfileUpdates,
};
