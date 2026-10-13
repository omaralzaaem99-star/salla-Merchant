"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  CodeLoginError,
  linkAccountWithCode,
  normalizePhoneDigits,
} = require("../src/code_login");

test('merchant credential guessing is bounded across anonymous UIDs and resets after the window', async () => {
  const database = new Database({});
  const nowMs = Date.now();
  const input = {role:'store',phone:'07700000000',linkCode:'WRONG'};
  for (let i=0;i<20;i++) await assert.rejects(linkAccountWithCode({database,uid:`anon${i}`,input,nowMs}), {code:'permission-denied'});
  await assert.rejects(linkAccountWithCode({database,uid:'rotated',input,nowMs}), {code:'resource-exhausted'});
  await assert.rejects(linkAccountWithCode({database,uid:'rotated',input,nowMs:nowMs+600001}), {code:'permission-denied'});
  assert.equal(JSON.stringify(database.state.securityAudit).includes('07700000000'),false);
  assert.equal(JSON.stringify(database.state.securityAudit).includes('WRONG'),false);
});

test("store deletion state is shown only after correct credentials and cannot recreate membership", async () => {
  const database = new Database({
    linkInvitations: {store: {ABCD: invitation("store", "store-1")}},
    stores: {"store-1": {id: "store-1", phone: "+9647700000000", active: false, accountDeletionPending: true}},
  });
  const options = {database, uid: "new-device", input: {role: "store", phone: "+9647700000000", linkCode: "ABCD"}};
  await assert.rejects(linkAccountWithCode({...options, input: {...options.input, phone: "+9647700000001"}}),
    e => e.code === "permission-denied" && !e.message.includes("30"));
  await assert.rejects(linkAccountWithCode(options), e => e.details.reason === "store_deletion_scheduled");
  assert.equal(database.state.userRoleProfiles, undefined);
});

test("legacy store invitation without a phone still uses the verified store phone", async () => {
  const value = invitation("store", "store-1"); delete value.phone;
  const database = new Database({linkInvitations: {store: {ABCD: value}},
    stores: {"store-1": {id: "store-1", name: "متجر", phone: "+9647700000000", active: true}}});
  await linkAccountWithCode({database, uid: "new-device", input: {role: "store", phone: "+9647700000000", linkCode: "ABCD"}});
  assert.equal(database.state.userRoleProfiles["new-device"].store.active, true);
});

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value : {};
}

function parts(path) {
  return String(path || "").split("/").filter(Boolean);
}

function getPath(root, path) {
  let current = root;
  for (const part of parts(path)) {
    if (!current || typeof current !== "object") return undefined;
    current = current[part];
  }
  return current;
}

function setPath(root, path, value) {
  const keys = parts(path);
  if (keys.length === 0) {
    for (const key of Object.keys(root)) delete root[key];
    Object.assign(root, object(clone(value)));
    return;
  }
  let current = root;
  for (const key of keys.slice(0, -1)) {
    current[key] = object(current[key]);
    current = current[key];
  }
  if (value === null) delete current[keys.at(-1)];
  else current[keys.at(-1)] = clone(value);
}

class Snapshot {
  constructor(value) {
    this.value = clone(value);
  }
  val() {
    return clone(this.value);
  }
  exists() {
    return this.value !== undefined && this.value !== null;
  }
}

class Reference {
  constructor(database, path = "", limit = null) {
    this.database = database;
    this.path = path;
    this.limit = limit;
  }
  async get() {
    let value = clone(getPath(this.database.state, this.path));
    if (this.limit && value && typeof value === "object") {
      value = Object.fromEntries(
          Object.entries(value).slice(0, this.limit),
      );
    }
    return new Snapshot(value);
  }
  limitToFirst(limit) {
    return new Reference(this.database, this.path, Number(limit));
  }
  push() {
    this.database.pushCount += 1;
    return {key: `audit_${this.database.pushCount}`};
  }
  async transaction(callback) {
    const current = clone(getPath(this.database.state, this.path));
    if (this.database.coldTransactionPaths.delete(this.path)) {
      const initial = callback(null);
      if (initial === undefined) {
        return {committed: false, snapshot: new Snapshot(null)};
      }
    }
    const next = callback(current);
    if (next === undefined) {
      return {committed: false, snapshot: new Snapshot(current)};
    }
    setPath(this.database.state, this.path, next);
    return {committed: true, snapshot: new Snapshot(next)};
  }
  async update(updates) {
    if (this.path) {
      const current = object(getPath(this.database.state, this.path));
      setPath(this.database.state, this.path, {...current, ...clone(updates)});
      return;
    }
    for (const [path, value] of Object.entries(updates)) {
      setPath(this.database.state, path, value);
    }
  }
}

class Database {
  constructor(state = {}) {
    this.state = clone(state);
    this.pushCount = 0;
    this.coldTransactionPaths = new Set();
  }
  ref(path = "") {
    return new Reference(this, path);
  }
}

function invitation(role, entityId, phone = "+9647700000000") {
  return {
    role,
    entityId,
    entityName: "حساب اختبار",
    phone,
    linkCode: "ABCD",
    active: true,
  };
}

test("تسجيل السائق يتم خادمياً من دون حفظ الرموز في ملفه العام", async () => {
  const database = new Database({
    linkInvitations: {
      driver: {ABCD: invitation("driver", "driver-1")},
    },
    drivers: {
      "driver-1": {
        id: "driver-1",
        name: "سائق اختبار",
        phone: "+9647700000000",
        active: true,
        status: "offline",
      },
    },
  });
  const result = await linkAccountWithCode({
    database,
    uid: "uid-new",
    input: {
      role: "driver",
      requestedName: "اسم غير معتمد",
      phone: "+9647700000000",
      linkCode: "ab-cd",
    },
    nowMs: Date.parse("2026-07-25T00:00:00.000Z"),
  });
  assert.equal(result.identity.entityId, "driver-1");
  assert.equal(result.identity.name, "سائق اختبار");
  assert.equal(database.state.drivers["driver-1"].authUid, "uid-new");
  assert.equal(database.state.drivers["driver-1"].isOnline, false);
  const profile = database.state.userRoleProfiles["uid-new"].driver;
  assert.equal(profile.linkedWithCode, true);
  assert.equal("linkCodeUsed" in profile, false);
  assert.equal("loginCodeUsed" in profile, false);
  assert.equal(database.state.securityAudit.codeLogins.audit_1.role, "driver");
  assert.equal(
      database.state.customerAccountDeletionLocks["uid-new"]
          .lifecycleRevision,
      1,
  );
});

test("حاجز حذف الهوية يمنع ربط أي دور قبل استدعاء حذف المصادقة",
    async () => {
      const database = new Database({
        customerAccountDeletionLocks: {
          "uid-new": {
            deleted: true,
            operationId: "delete-operation",
            authDeletionFenced: true,
            authAttemptToken: "auth-delete-attempt",
          },
        },
        linkInvitations: {
          driver: {ABCD: invitation("driver", "driver-1")},
        },
        drivers: {
          "driver-1": {
            id: "driver-1",
            name: "سائق اختبار",
            phone: "+9647700000000",
            active: true,
          },
        },
      });

      await assert.rejects(
          () => linkAccountWithCode({
            database,
            uid: "uid-new",
            input: {
              role: "driver",
              phone: "+9647700000000",
              linkCode: "ABCD",
            },
            nowMs: Date.parse("2026-07-25T00:00:00.000Z"),
          }),
          (error) => error instanceof CodeLoginError &&
            error.code === "failed-precondition" &&
            error.details.reason ===
              "customer_account_deletion_in_progress",
      );
      assert.equal(database.state.drivers["driver-1"].authUid, undefined);
      assert.equal(database.state.userRoleProfiles, undefined);
    });

test("إعادة الربط تلغي عضوية الجهاز السابق للدور نفسه", async () => {
  const database = new Database({
    linkInvitations: {
      store: {ABCD: invitation("store", "store-1")},
    },
    stores: {
      "store-1": {
        id: "store-1",
        name: "متجر اختبار",
        phone: "+9647700000000",
        active: true,
        authUid: "uid-old",
      },
    },
    userRoleProfiles: {
      "uid-old": {
        store: {
          uid: "uid-old",
          role: "store",
          entityId: "store-1",
          active: true,
        },
      },
      "uid-older": {
        store: {
          uid: "uid-older",
          role: "store",
          entityId: "store-1",
          active: true,
        },
      },
      "uid-other-role": {
        driver: {
          uid: "uid-other-role",
          role: "driver",
          entityId: "driver-2",
          active: true,
        },
      },
    },
  });
  const result = await linkAccountWithCode({
    database,
    uid: "uid-new",
    input: {
      role: "store",
      requestedName: "متجر اختبار",
      phone: "+9647700000000",
      linkCode: "ABCD",
    },
  });
  assert.equal(result.rebound, true);
  assert.equal(
      database.state.userRoleProfiles["uid-old"].store.active,
      false,
  );
  assert.equal(
      database.state.userRoleProfiles["uid-older"].store.active,
      false,
  );
  assert.equal(
      database.state.userRoleProfiles["uid-other-role"].driver.active,
      true,
  );
  assert.equal(database.state.stores["store-1"].authUid, "uid-new");
});

test("الحساب الموقوف لا ينشئ أي عضوية", async () => {
  const database = new Database({
    linkInvitations: {
      driver: {ABCD: invitation("driver", "driver-1")},
    },
    drivers: {
      "driver-1": {
        id: "driver-1",
        phone: "+9647700000000",
        active: false,
      },
    },
  });
  await assert.rejects(
      () => linkAccountWithCode({
        database,
        uid: "uid-new",
        input: {
          role: "driver",
          phone: "+9647700000000",
          linkCode: "ABCD",
        },
      }),
      (error) => error instanceof CodeLoginError &&
        error.code === "failed-precondition",
  );
  assert.equal(database.state.userRoleProfiles, undefined);
});

test("دخول الإدارة يتطلب مطابقة الرمز الثاني والاسم", async () => {
  const database = new Database({
    linkInvitations: {
      admin: {ABCD: invitation("admin", "employee-1")},
    },
    adminLoginSecrets: {
      ABCD: {
        "7788": {
          role: "admin",
          entityId: "employee-1",
          linkCode: "ABCD",
          loginCode: "7788",
          active: true,
        },
      },
    },
    employees: {
      "employee-1": {
        id: "employee-1",
        name: "حساب اختبار",
        phone: "+9647700000000",
        roleTitle: "موظف دعم",
        linkCode: "ABCD",
        loginCode: "7788",
        active: true,
      },
    },
  });
  await assert.rejects(
      () => linkAccountWithCode({
        database,
        uid: "uid-admin",
        input: {
          role: "admin",
          requestedName: "حساب اختبار",
          phone: "+9647700000000",
          linkCode: "ABCD",
          loginCode: "0000",
        },
      }),
      (error) => error instanceof CodeLoginError &&
        error.code === "permission-denied",
  );
  await assert.rejects(
      () => linkAccountWithCode({
        database,
        uid: "uid-admin",
        input: {
          role: "admin",
          requestedName: "اسم مختلف",
          phone: "+9647700000000",
          linkCode: "ABCD",
          loginCode: "7788",
        },
      }),
      (error) => error instanceof CodeLoginError &&
        error.code === "permission-denied",
  );
  const result = await linkAccountWithCode({
    database,
    uid: "uid-admin",
    input: {
      role: "admin",
      requestedName: "حساب اختبار",
      phone: "+9647700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
  });
  assert.equal(result.identity.entityId, "employee-1");
});

test("المسار العام لا يسمح لأي مستخدم بامتلاك أول حساب إدارة", async () => {
  const database = new Database();
  await assert.rejects(
      () => linkAccountWithCode({
        database,
        uid: "uid-attacker",
        input: {
          role: "admin",
          requestedName: "مدير غير موثوق",
          phone: "+9647700000000",
          linkCode: "ABCD",
          loginCode: "7788",
          allowFirstAdminBootstrap: true,
        },
      }),
      (error) => error instanceof CodeLoginError &&
        error.code === "permission-denied",
  );
  assert.equal(database.state.employees, undefined);
  assert.equal(getPath(database.state, "system/bootstrap/adminUid"), undefined);
  assert.equal(database.state.linkInvitations, undefined);
  assert.equal(database.state.adminLoginSecrets, undefined);
});

test("أداة المالك الموثوقة وحدها تنشئ أول مدير ثم يُغلق التأسيس", async () => {
  const database = new Database();
  const ownerInput = {
    role: "admin",
    requestedName: "منتظر نصير عبدالامير",
    phone: "+9647765294438",
    linkCode: "OWNER2026",
    loginCode: "77889911",
  };
  const result = await linkAccountWithCode({
    database,
    uid: "owner-production-uid",
    input: ownerInput,
    allowFirstAdminBootstrap: true,
    nowMs: Date.parse("2026-08-26T00:00:00.000Z"),
  });
  assert.equal(result.bootstrapped, true);
  assert.equal(result.identity.name, "منتظر نصير عبدالامير");
  const employee = database.state.employees[result.identity.entityId];
  assert.equal(employee.roleTitle, "مدير عام");
  assert.equal(employee.authUid, "owner-production-uid");
  assert.equal(
      getPath(database.state, "system/bootstrap/adminUid"),
      "owner-production-uid",
  );
  assert.equal("linkCode" in database.state.userProfiles[
    "owner-production-uid"
  ], false);
  assert.equal("loginCode" in database.state.userProfiles[
    "owner-production-uid"
  ], false);

  await assert.rejects(
      () => linkAccountWithCode({
        database,
        uid: "second-owner-uid",
        input: {
          ...ownerInput,
          requestedName: "مدير ثان",
          phone: "+9647700000001",
          linkCode: "SECOND2026",
          loginCode: "99887766",
        },
        allowFirstAdminBootstrap: true,
      }),
      (error) => error instanceof CodeLoginError &&
        error.code === "permission-denied",
  );
  assert.equal(Object.keys(database.state.employees).length, 1);
});

test("دخول كل موظفي الإدارة يتسامح مع همزات ومسافات الاسم العربي", async () => {
  const database = new Database({
    linkInvitations: {
      admin: {ABCD: invitation("admin", "employee-leader")},
    },
    adminLoginSecrets: {
      ABCD: {
        "7788": {
          role: "admin",
          entityId: "employee-leader",
          linkCode: "ABCD",
          loginCode: "7788",
          active: true,
        },
      },
    },
    employees: {
      "employee-leader": {
        id: "employee-leader",
        name: "بارق نصير عبد الأمير",
        phone: "+9647700000000",
        roleTitle: "ليدر السائقين",
        linkCode: "ABCD",
        loginCode: "7788",
        active: true,
      },
    },
  });

  const result = await linkAccountWithCode({
    database,
    uid: "uid-leader",
    input: {
      role: "admin",
      requestedName: "بارق  نصير عبدالامير",
      phone: "+9647700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
  });

  assert.equal(result.identity.entityId, "employee-leader");
  assert.equal(
      database.state.employees["employee-leader"].authUid,
      "uid-leader",
  );
});

test("دخول الإدارة ينتظر سجل الموظف عند بداية معاملة فايربيس الباردة", async () => {
  const database = new Database({
    linkInvitations: {
      admin: {ABCD: invitation("admin", "employee-1")},
    },
    adminLoginSecrets: {
      ABCD: {
        "7788": {
          role: "admin",
          entityId: "employee-1",
          linkCode: "ABCD",
          loginCode: "7788",
          active: true,
        },
      },
    },
    employees: {
      "employee-1": {
        id: "employee-1",
        name: "حساب اختبار",
        phone: "+9647700000000",
        role: "admin",
        roleTitle: "مدير عام",
        linkCode: "ABCD",
        loginCode: "7788",
        active: true,
      },
    },
  });
  database.coldTransactionPaths.add("employees/employee-1");

  const result = await linkAccountWithCode({
    database,
    uid: "uid-admin-cold",
    input: {
      role: "admin",
      requestedName: "حساب اختبار",
      phone: "+9647700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
  });

  assert.equal(result.identity.entityId, "employee-1");
  assert.equal(
      database.state.employees["employee-1"].authUid,
      "uid-admin-cold",
  );
});

test("دخول الإدارة يصلح اسم الدعوة القديم بعد مطابقة السجل والرمزين", async () => {
  const database = new Database({
    linkInvitations: {
      admin: {
        ABCD: {
          ...invitation("admin", "employee-1"),
          entityName: "اسم إداري قديم",
          phoneNormalized: "9647700000000",
        },
      },
    },
    adminLoginSecrets: {
      ABCD: {
        "7788": {
          role: "admin",
          entityId: "employee-1",
          linkCode: "ABCD",
          loginCode: "7788",
          active: true,
        },
      },
    },
    employees: {
      "employee-1": {
        id: "employee-1",
        name: "المدير العام",
        phone: "+9647700000000",
        role: "admin",
        roleTitle: "مدير عام",
        linkCode: "ABCD",
        loginCode: "7788",
        active: true,
      },
    },
  });

  const result = await linkAccountWithCode({
    database,
    uid: "uid-admin",
    input: {
      role: "admin",
      requestedName: "  المدير   العام  ",
      phone: "07700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
    nowMs: Date.parse("2026-07-27T01:00:00.000Z"),
  });

  assert.equal(result.identity.entityId, "employee-1");
  assert.equal(
      database.state.linkInvitations.admin.ABCD.entityName,
      "المدير العام",
  );
  const repairAudit = Object.values(
      database.state.securityAudit.codeLogins,
  ).find((entry) =>
    entry.kind === "legacy_admin_invitation_metadata_repair");
  assert.equal(repairAudit.entityId, "employee-1");
  const repairAuditText = JSON.stringify(repairAudit);
  assert.doesNotMatch(
      repairAuditText,
      /ABCD|7788|المدير العام|9647700000000/,
  );
});

test("اسم إداري خاطئ لا يغيّر اسم الدعوة القديم", async () => {
  const database = new Database({
    linkInvitations: {
      admin: {
        ABCD: {
          ...invitation("admin", "employee-1"),
          entityName: "اسم إداري قديم",
        },
      },
    },
    adminLoginSecrets: {
      ABCD: {
        "7788": {
          role: "admin",
          entityId: "employee-1",
          active: true,
        },
      },
    },
    employees: {
      "employee-1": {
        id: "employee-1",
        name: "المدير العام",
        phone: "+9647700000000",
        role: "admin",
        roleTitle: "مدير عام",
        linkCode: "ABCD",
        loginCode: "7788",
        active: true,
      },
    },
  });

  await assert.rejects(
      () => linkAccountWithCode({
        database,
        uid: "uid-admin",
        input: {
          role: "admin",
          requestedName: "اسم غير صحيح",
          phone: "07700000000",
          linkCode: "ABCD",
          loginCode: "7788",
        },
      }),
      (error) => error instanceof CodeLoginError &&
        error.code === "permission-denied",
  );
  assert.equal(
      database.state.linkInvitations.admin.ABCD.entityName,
      "اسم إداري قديم",
  );
  assert.equal(database.state.securityAudit, undefined);
});

test("دخول الإدارة يرفض السجل الذي لا يملك اسماً معتمداً", async () => {
  const database = new Database({
    linkInvitations: {
      admin: {ABCD: invitation("admin", "employee-1")},
    },
    adminLoginSecrets: {
      ABCD: {
        "7788": {
          role: "admin",
          entityId: "employee-1",
          active: true,
        },
      },
    },
    employees: {
      "employee-1": {
        id: "employee-1",
        name: "",
        phone: "+9647700000000",
        role: "admin",
        active: true,
      },
    },
  });

  await assert.rejects(
      () => linkAccountWithCode({
        database,
        uid: "uid-admin",
        input: {
          role: "admin",
          requestedName: "حساب اختبار",
          phone: "07700000000",
          linkCode: "ABCD",
          loginCode: "7788",
        },
      }),
      (error) => error instanceof CodeLoginError &&
        error.code === "permission-denied",
  );
  assert.equal(database.state.userRoleProfiles, undefined);
});

test("دخول المدير المؤسس القديم يصلح عقدتي الربط والسر الناقصتين فقط", async () => {
  const employeeId = "EMP-UIDBOOTSTR";
  const database = new Database({
    system: {
      bootstrap: {adminUid: "uid-bootstrap"},
    },
    employees: {
      [employeeId]: {
        id: employeeId,
        authUid: "uid-bootstrap",
        name: "المدير العام",
        phone: "+9647700000000",
        role: "admin",
        roleTitle: "مدير عام",
        linkCode: "ABCD",
        loginCode: "7788",
        active: true,
      },
    },
  });
  const result = await linkAccountWithCode({
    database,
    uid: "uid-new",
    input: {
      role: "admin",
      requestedName: "المدير العام",
      phone: "07700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
    nowMs: Date.parse("2026-07-27T00:00:00.000Z"),
  });
  assert.equal(result.identity.entityId, employeeId);
  assert.equal(result.rebound, true);
  assert.equal(
      database.state.linkInvitations.admin.ABCD.entityId,
      employeeId,
  );
  assert.equal(
      database.state.adminLoginSecrets.ABCD["7788"].entityId,
      employeeId,
  );
  assert.equal(
      database.state.system.bootstrap.adminUid,
      "uid-bootstrap",
  );
  const repairAudit = Object.values(
      database.state.securityAudit.codeLogins,
  ).find((entry) => entry.kind === "legacy_admin_login_index_repair");
  assert.equal(repairAudit.entityId, employeeId);
  assert.equal(repairAudit.repairedInvitation, true);
  assert.equal(repairAudit.repairedSecret, true);
  const repairAuditText = JSON.stringify(repairAudit);
  assert.doesNotMatch(
      repairAuditText,
      /ABCD|7788|المدير العام|9647700000000/,
  );

  await linkAccountWithCode({
    database,
    uid: "uid-new",
    input: {
      role: "admin",
      requestedName: "المدير العام",
      phone: "07700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
    nowMs: Date.parse("2026-07-27T00:01:00.000Z"),
  });
  assert.equal(
      Object.values(database.state.securityAudit.codeLogins)
          .filter((entry) =>
            entry.kind === "legacy_admin_login_index_repair").length,
      1,
  );
});

test("إصلاح دخول المدير القديم ينشئ الجزء الناقص فقط", async () => {
  const employeeId = "EMP-UIDBOOTSTR";
  for (const missing of ["invitation", "secret"]) {
    const state = {
      system: {
        bootstrap: {adminUid: "uid-bootstrap"},
      },
      employees: {
        [employeeId]: {
          id: employeeId,
          authUid: "uid-bootstrap",
          name: "المدير العام",
          phone: "+9647700000000",
          role: "admin",
          roleTitle: "مدير عام",
          linkCode: "ABCD",
          loginCode: "7788",
          active: true,
        },
      },
      linkInvitations: {
        admin: {
          ABCD: invitation("admin", employeeId),
        },
      },
      adminLoginSecrets: {
        ABCD: {
          "7788": {
            role: "admin",
            entityId: employeeId,
            linkCode: "ABCD",
            loginCode: "7788",
            active: true,
          },
        },
      },
    };
    state.linkInvitations.admin.ABCD.entityName = "المدير العام";
    if (missing === "invitation") delete state.linkInvitations;
    if (missing === "secret") delete state.adminLoginSecrets;
    const database = new Database(state);
    await linkAccountWithCode({
      database,
      uid: `uid-${missing}`,
      input: {
        role: "admin",
        requestedName: "المدير العام",
        phone: "+9647700000000",
        linkCode: "ABCD",
        loginCode: "7788",
      },
    });
    assert.equal(
        database.state.linkInvitations.admin.ABCD.entityId,
        employeeId,
    );
    assert.equal(
        database.state.adminLoginSecrets.ABCD["7788"].entityId,
        employeeId,
    );
    const repairAudit = Object.values(
        database.state.securityAudit.codeLogins,
    ).find((entry) => entry.kind === "legacy_admin_login_index_repair");
    assert.equal(
        repairAudit.repairedInvitation,
        missing === "invitation",
    );
    assert.equal(repairAudit.repairedSecret, missing === "secret");
  }
});

test("إصلاح دخول المدير القديم لا يعيد تنشيط فهرس معطل أو متعارض", async () => {
  const employeeId = "EMP-UIDBOOTSTR";
  for (const conflict of ["inactive_invitation", "inactive_secret"]) {
    const state = {
      system: {
        bootstrap: {adminUid: "uid-bootstrap"},
      },
      employees: {
        [employeeId]: {
          id: employeeId,
          authUid: "uid-bootstrap",
          name: "المدير العام",
          phone: "+9647700000000",
          role: "admin",
          roleTitle: "مدير عام",
          linkCode: "ABCD",
          loginCode: "7788",
          active: true,
        },
      },
      linkInvitations: {
        admin: {
          ABCD: {
            ...invitation("admin", employeeId),
            entityName: "المدير العام",
            active: conflict !== "inactive_invitation",
          },
        },
      },
      adminLoginSecrets: {
        ABCD: {
          "7788": {
            role: "admin",
            entityId: employeeId,
            linkCode: "ABCD",
            loginCode: "7788",
            active: conflict !== "inactive_secret",
          },
        },
      },
    };
    const database = new Database(state);
    await assert.rejects(
        () => linkAccountWithCode({
          database,
          uid: "uid-new",
          input: {
            role: "admin",
            requestedName: "المدير العام",
            phone: "+9647700000000",
            linkCode: "ABCD",
            loginCode: "7788",
          },
        }),
        (error) => error instanceof CodeLoginError &&
          error.code === "permission-denied",
    );
    assert.equal(
        database.state.linkInvitations.admin.ABCD.active,
        conflict !== "inactive_invitation",
    );
    assert.equal(
        database.state.adminLoginSecrets.ABCD["7788"].active,
        conflict !== "inactive_secret",
    );
  }
});

test("إصلاح دخول المدير القديم لا يقبل رمزاً خاطئاً أو مديراً غير مؤسس", async () => {
  const employeeId = "EMP-UIDBOOTSTR";
  const baseState = {
    system: {
      bootstrap: {adminUid: "uid-bootstrap"},
    },
    employees: {
      [employeeId]: {
        id: employeeId,
        authUid: "uid-bootstrap",
        name: "المدير العام",
        phone: "+9647700000000",
        role: "admin",
        roleTitle: "مدير عام",
        linkCode: "ABCD",
        loginCode: "7788",
        active: true,
      },
    },
  };
  for (const input of [
    {
      role: "admin",
      requestedName: "المدير العام",
      phone: "+9647700000000",
      linkCode: "ABCD",
      loginCode: "0000",
    },
    {
      role: "admin",
      requestedName: "اسم مختلف",
      phone: "+9647700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
  ]) {
    const database = new Database(baseState);
    await assert.rejects(
        () => linkAccountWithCode({
          database,
          uid: "uid-new",
          input,
        }),
        (error) => error instanceof CodeLoginError &&
          error.code === "permission-denied",
    );
    assert.equal(database.state.linkInvitations, undefined);
    assert.equal(database.state.adminLoginSecrets, undefined);
  }
});

test("إصلاح دخول المدير القديم لا يمسح مجموعة الموظفين", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "..", "src", "code_login.js"),
      "utf8",
  );
  assert.doesNotMatch(
      source,
      /database\.ref\(["']employees["']\)\.get\(\)/,
  );
});

test("دخول مدير الوكالة يحفظ نطاق الوكالة والفروع في ملف الدور", async () => {
  const employeeId = "EMP-AGENCY";
  const database = new Database({
    employees: {
      [employeeId]: {
        id: employeeId,
        name: "مدير وكالة بغداد",
        phone: "+9647700000000",
        role: "admin",
        roleTitle: "مدير وكالة",
        agencyId: "agency_baghdad",
        agencyName: "وكالة بغداد الأولى",
        provinceId: "baghdad",
        provinceName: "بغداد",
        ownershipType: "agency",
        active: true,
      },
    },
    linkInvitations: {
      admin: {
        ABCD: {
          ...invitation("admin", employeeId),
          entityName: "مدير وكالة بغداد",
        },
      },
    },
    adminLoginSecrets: {
      ABCD: {
        "7788": {
          role: "admin",
          entityId: employeeId,
          linkCode: "ABCD",
          loginCode: "7788",
          active: true,
        },
      },
    },
  });

  const result = await linkAccountWithCode({
    database,
    uid: "uid-agency-manager",
    input: {
      role: "admin",
      requestedName: "مدير وكالة بغداد",
      phone: "+9647700000000",
      linkCode: "ABCD",
      loginCode: "7788",
    },
  });

  assert.equal(result.identity.agencyId, "agency_baghdad");
  assert.equal(result.identity.provinceId, "baghdad");
  assert.equal(
      database.state.userRoleProfiles["uid-agency-manager"].admin.agencyId,
      "agency_baghdad",
  );
});

test("تطبيع رقم الهاتف يطابق الصيغ العراقية المعتادة", () => {
  assert.equal(normalizePhoneDigits("0770 000 0000"), "9647700000000");
  assert.equal(normalizePhoneDigits("+964 770 000 0000"), "9647700000000");
  assert.equal(normalizePhoneDigits("٠٧٧٠٠٠٠٠٠٠٠"), "9647700000000");
});
