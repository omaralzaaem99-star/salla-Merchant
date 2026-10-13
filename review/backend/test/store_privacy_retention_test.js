"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const {StoreLifecycleDatabase, read} = require("./helpers/store_lifecycle_database");
const {scheduleStorePrivacyDeletion, restoreStorePrivacyAccount, GRACE_MS} = require("../src/store_privacy_schedule");
const {purgeDueStorePrivacy, reconcileStorePrivacyRetention} = require("../src/store_privacy_retention");
const {ROOT} = require("../src/store_privacy_requests");
const at = Date.parse("2026-10-12T00:00:00Z");
async function setup(shared=false, immediate=false) {
  const db = new StoreLifecycleDatabase({stores:{s:{id:"s",name:"Store",phone:"07701234567",authUid:"u",active:true,commissionPercent:18}},
    userProfiles:{u:{uid:"u",role:"store",entityId:"s",active:true,phone:"07701234567"},gm:{active:true}},
    userRoleProfiles:{u:{store:{uid:"u",role:"store",entityId:"s",active:true},...(shared?{driver:{uid:"u",role:"driver",entityId:"d",active:true,phone:"driver-phone"}}:{})},gm:{admin:{entityId:"e",active:true}}},
    employees:{e:{authUid:"gm",active:true,roleTitle:"مدير عام"}},
    ...(shared?{drivers:{d:{authUid:"u",active:true}}}:{}),
    orders:{o:{storeId:"s",status:"delivered",amount:5000}},storeSettlements:{s:{amount:1234}},
    linkInvitations:{store:{A:{entityId:"s",phone:"07701234567"},B:{entityId:"other"}}},
    system:{storeApplications:{requests:{a:{storeId:"s",phone:"07701234567"}}}},
    unrelated:{large:"a".repeat(34*1024*1024)},
  });
  const receipt = await scheduleStorePrivacyDeletion({database:db,uid:"u",nowMs:at,data:{storeId:"s",requestId:"schedule-0001",confirmation:immediate ? "DELETE_STORE_ACCOUNT_NOW" : "DELETE_STORE_ACCOUNT",graceDays:immediate ? 0 : 30}});
  const removed=[];
  const input={database:db,storeId:"s",expectedRequestId:receipt.request.id,nowMs:at+GRACE_MS,
    authAdmin:{async deleteUser(uid){removed.push(uid);}},storageBucket:{async getFiles(){return [[]];}}};
  db.beforeGet = path => {assert.notEqual(path,"","never read entire live database");};
  return {db,input,removed};
}

test("immediate confirmation purges now, preserves named audit and exact financial records, and replays after Auth removal",async()=>{
  const {db,input,removed}=await setup(false,true);
  const finance=structuredClone(db.data.storeSettlements);
  const {deleteStorePrivacyNow}=require('../src/store_privacy_retention');
  const options={...input,uid:'u',nowMs:at,data:{storeId:'s',requestId:'schedule-0001',confirmation:'DELETE_STORE_ACCOUNT_NOW',graceDays:0}};
  const result=await deleteStorePrivacyNow(options);
  assert.equal(result.completed,true);assert.equal(result.signOut,true);assert.equal(result.request.storeName,'Store');
  assert.equal(result.request.deletionMode,'immediate');assert.equal(result.request.phone,'');
  assert.deepEqual(removed,['u']);assert.deepEqual(db.data.storeSettlements,finance);
  assert.equal(read(db.data,'stores/s/phone'),null);assert.equal(read(db.data,'userProfiles/u'),null);
  assert.equal(Object.values(db.data.auditLogs)[0].targetName,'Store');
  const again=await deleteStorePrivacyNow(options);assert.equal(again.completed,true);assert.deepEqual(removed,['u']);
  const status=await require('../src/store_privacy_schedule').ownScheduledPrivacyStatus({database:db,uid:'u',data:{storeId:'s'}});
  assert.equal(status.request.status,'completed');assert.equal(status.signOut,true);
  await assert.rejects(require('../src/store_privacy_schedule').ownScheduledPrivacyStatus({database:db,uid:'other',data:{storeId:'s'}}));
});

test("immediate partial failure is resumable, never completed early and never restorable",async()=>{
  const {db,input}=await setup(false,true);let offline=true;
  input.storageBucket.getFiles=async()=>{if(offline)throw Error('offline');return [[]];};
  const options={...input,uid:'u',nowMs:at,data:{storeId:'s',requestId:'schedule-0001',confirmation:'DELETE_STORE_ACCOUNT_NOW',graceDays:0}};
  const {deleteStorePrivacyNow}=require('../src/store_privacy_retention');
  const first=await deleteStorePrivacyNow(options);assert.equal(first.completed,false);assert.equal(first.request.status,'purging');
  await assert.rejects(restoreStorePrivacyAccount({database:db,actor:{uid:'gm',isGeneralManager:true},nowMs:at-1,
    data:{storeId:'s',expectedRequestId:first.request.id}}),e=>e.details.reason==='privacy_restore_expired');
  offline=false;assert.equal((await deleteStorePrivacyNow(options)).completed,true);
});

test("immediate deletion does not accept the old 30 day confirmation or shorten existing grace",async()=>{
  const {db}=await setup();const before=structuredClone(db.data);
  await assert.rejects(scheduleStorePrivacyDeletion({database:db,uid:'u',nowMs:at,data:{storeId:'s',requestId:'schedule-0001',confirmation:'DELETE_STORE_ACCOUNT',graceDays:0}}));
  await assert.rejects(scheduleStorePrivacyDeletion({database:db,uid:'u',nowMs:at,data:{storeId:'s',requestId:'schedule-0001',confirmation:'DELETE_STORE_ACCOUNT_NOW',graceDays:0}}));
  assert.deepEqual(db.data,before);
});

test("pending signup immediate deletion can confirm receipt after application is removed",async()=>{
  const aid='b'.repeat(64);
  const db=new StoreLifecycleDatabase({system:{storeApplications:{requests:{[aid]:{applicantUid:'u',accountApplication:true,phone:'07701234567',storeName:'Pending',status:'pending'}}}}});
  const options={database:db,uid:'u',nowMs:at,data:{applicationId:aid,requestId:'delete-now-001',confirmation:'DELETE_STORE_ACCOUNT_NOW',graceDays:0},
    authAdmin:{async deleteUser(){}},storageBucket:{async getFiles(){return [[]];}}};
  const {deleteStorePrivacyNow}=require('../src/store_privacy_retention');
  const result=await deleteStorePrivacyNow(options);assert.equal(result.completed,true);assert.equal(result.request.applicationId,aid);
  assert.equal(read(db.data,`system/storeApplications/requests/${aid}`),null);
  assert.equal((await deleteStorePrivacyNow(options)).completed,true);
  assert.equal((await require('../src/store_privacy_schedule').ownScheduledPrivacyStatus({database:db,uid:'u',data:{applicationId:aid}})).request.status,'completed');
  await assert.rejects(deleteStorePrivacyNow({...options,uid:'other'}));
});
test("immediate deletion preserves a shared driver identity",async()=>{
  const {db,input,removed}=await setup(true,true);
  const result=await require('../src/store_privacy_retention').deleteStorePrivacyNow({...input,uid:'u',nowMs:at,
    data:{storeId:'s',requestId:'schedule-0001',confirmation:'DELETE_STORE_ACCOUNT_NOW',graceDays:0}});
  assert.equal(result.completed,true);assert.deepEqual(removed,[]);
  assert.equal(db.data.userRoleProfiles.u.driver.active,true);
  assert.equal(db.data.userProfiles.u.phone,'driver-phone');assert.equal(read(db.data,'userRoleProfiles/u/store'),null);
});

test("legacy unexecuted request requires new explicit immediate consent and active orders still block deletion",async()=>{
  const {db,input}=await setup();
  await restoreStorePrivacyAccount({database:db,actor:{uid:'gm',isGeneralManager:true},nowMs:at+1,
    data:{storeId:'s',expectedRequestId:input.expectedRequestId}});
  await db.ref(`${ROOT}/s`).set({id:'old-request',storeId:'s',requestedByUid:'u',status:'pending'});
  const status=await require('../src/store_privacy_schedule').ownScheduledPrivacyStatus({database:db,uid:'u',data:{storeId:'s'}});
  assert.equal(status.canConfirmImmediateDeletion,true);assert.equal(status.signOut,false);
  db.data.orders.o.status='accepted';const before=structuredClone(db.data);
  const options={...input,uid:'u',nowMs:at+2,data:{storeId:'s',requestId:'new-consent-0001',confirmation:'DELETE_STORE_ACCOUNT_NOW',graceDays:0}};
  await assert.rejects(require('../src/store_privacy_retention').deleteStorePrivacyNow(options),e=>e.details.reason==='active_orders');
  assert.deepEqual(db.data,before);
  db.data.orders.o.status='delivered';
  assert.equal((await require('../src/store_privacy_retention').deleteStorePrivacyNow(options)).completed,true);
});

test("due purge removes contact and Auth with a database larger than old root limit; keeps exact finance",async()=>{
  const {db,input,removed}=await setup(); const orders=structuredClone(db.data.orders), finance=structuredClone(db.data.storeSettlements);
  const result=await purgeDueStorePrivacy(input);
  assert.equal(result.completed,true);assert.deepEqual(removed,["u"]);
  assert.deepEqual(db.data.orders,orders);assert.deepEqual(db.data.storeSettlements,finance);
  assert.equal(read(db.data,"stores/s/phone"),null);assert.equal(read(db.data,`${ROOT}/s/phone`),null);
  assert.equal(read(db.data,"system/storeApplications/requests/a"),null);
  assert.ok(db.data.linkInvitations.store.B);assert.equal(read(db.data,"userProfiles/u"),null);
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);assert.deepEqual(removed,["u"]);
});
test("shared driver role and its contact survive merchant deletion",async()=>{
  const {db,input,removed}=await setup(true);await purgeDueStorePrivacy(input);
  assert.deepEqual(removed,[]);assert.equal(db.data.userProfiles.u.phone,"driver-phone");
  assert.equal(db.data.userRoleProfiles.u.driver.active,true);
  assert.equal(db.data.customerAccountDeletionLocks.u.authDeletionFenced,false);
});

test("purge removes contact snapshots, notification inbox and store login trail, preserving finance and other roles",async()=>{
  const {db,input}=await setup();
  Object.assign(db.data.orders.o,{storePhone:'private',storeAddress:'private',storeLat:33,storeLng:44});
  db.data.stores.s.storeReferralId='ref';
  db.data.storeReferrals={ref:{linkedStoreId:'s',phone:'private',phoneNormalized:'private',linkedStorePhone:'private',storeAddress:'private',rewardAmount:1000}};
  db.data.notifications={store:{s:{n:{body:'private'}}}};
  db.data.operationalOrderRefs={stores:{s:{o:{publicOrder:{storePhone:'private'}}}}};
  db.data.securityAudit={codeLogins:{old:{uid:'u',role:'store',entityId:'s'},rebind:{replacedUid:'u',role:'store',entityId:'s'},driver:{uid:'u',role:'driver',entityId:'d'}}};
  await purgeDueStorePrivacy(input);
  assert.deepEqual(db.data.orders.o,{storeId:'s',status:'delivered',amount:5000});
  assert.deepEqual(db.data.storeReferrals.ref,{linkedStoreId:'s',rewardAmount:1000});
  assert.equal(read(db.data,'notifications/store/s'),null);
  assert.equal(read(db.data,'operationalOrderRefs/stores/s'),null);
  assert.deepEqual(Object.keys(db.data.securityAudit.codeLogins),['driver']);
});
test("not-due or restored requests never purge",async()=>{
  const {db,input,removed}=await setup();
  assert.equal((await purgeDueStorePrivacy({...input,nowMs:at+GRACE_MS-1})).skipped,true);
  await restoreStorePrivacyAccount({database:db,actor:{uid:"gm",isGeneralManager:true},nowMs:at+1,
    data:{storeId:"s",expectedRequestId:input.expectedRequestId}});
  assert.equal((await purgeDueStorePrivacy(input)).skipped,true);assert.deepEqual(removed,[]);
});

test("deletion also clears hashed store login account and UID counters",async()=>{
  const {db,input}=await setup();
  const {storeLoginLimitKey,normalizePhoneDigits}=require('../src/code_login');
  const uidKey=storeLoginLimitKey('uid','u');
  const phoneKey=storeLoginLimitKey('account',normalizePhoneDigits('07701234567'));
  db.data.securityAudit={codeLoginLimits:{[uidKey]:{count:1},[phoneKey]:{count:2},other:{count:3}}};
  await purgeDueStorePrivacy(input);
  assert.deepEqual(db.data.securityAudit.codeLoginLimits,{other:{count:3}});
});
test("media failure remains resumable and does not retain phone after DB erasure",async()=>{
  const {db,input,removed}=await setup();let offline=true;
  input.storageBucket.getFiles=async()=>{if(offline)throw new Error("offline");return [[]];};
  await assert.rejects(purgeDueStorePrivacy(input));
  assert.equal(read(db.data,`${ROOT}/s/status`),"purging");assert.equal(read(db.data,`${ROOT}/s/phone`),null);
  offline=false;assert.equal((await purgeDueStorePrivacy(input)).completed,true);assert.deepEqual(removed,["u"]);
});
test("scheduler selects only indexed due rows and erases its retry deadline on completion",async()=>{
  const {db,input}=await setup();
  const result=await reconcileStorePrivacyRetention(input);
  assert.deepEqual(result,{checked:1,completed:1,failed:0});
  assert.deepEqual(await reconcileStorePrivacyRetention(input),{checked:0,completed:0,failed:0});
});

test("cold callbacks and lost Auth response resume without deleting another identity",async()=>{
  const {db,input,removed}=await setup();
  for(const p of ['userRoleProfiles/u/store','userProfiles/u',`${ROOT}/s`,'stores/s']) db.coldPaths.add(p);
  let first=true;
  input.authAdmin.deleteUser=async uid=>{removed.push(uid);if(first){first=false;throw new Error('response lost after deletion');}throw Object.assign(new Error('absent'),{code:'auth/user-not-found'});};
  await assert.rejects(purgeDueStorePrivacy(input));
  assert.equal(read(db.data,`${ROOT}/s/status`),'purging');
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);
  assert.deepEqual(removed,['u','u']);
});

test("OTP graph aliases and ownerless references are removed; another UID remains intact",async()=>{
  const {db,input}=await setup();
  db.data.authOtpRequests={r:{authUid:'u',phone:'private'},other:{uid:'other',phone:'safe'}};
  db.data.authOtpVerifications={v:{requestId:'r',code:'private'},foreign:{requestId:'r',uid:'other'}};
  db.data.authOtpSessions={r:{requestId:'r',phoneHash:'h'}};
  db.data.authOtpPhoneSessions={h:{requestId:'r'}};
  db.data.authOtpVerifiedPhones={h:{verificationId:'v'}};
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);
  assert.equal(read(db.data,'authOtpRequests/r'),null);
  assert.equal(read(db.data,'authOtpVerifications/v'),null);
  assert.equal(read(db.data,'authOtpPhoneSessions/h'),null);
  assert.equal(read(db.data,'authOtpVerifiedPhones/h'),null);
  assert.equal(db.data.authOtpRequests.other.phone,'safe');
  assert.equal(db.data.authOtpVerifications.foreign.uid,'other');
});

test("pending signup can close and purge without an activated store",async()=>{
  const db=new StoreLifecycleDatabase({system:{storeApplications:{requests:{['a'.repeat(64)]:{applicantUid:'u',accountApplication:true,phone:'07701234567',storeName:'Pending',status:'pending'}}}}});
  const result=await scheduleStorePrivacyDeletion({database:db,uid:'u',nowMs:at,data:{applicationId:'a'.repeat(64),requestId:'pending-0001',confirmation:'DELETE_STORE_ACCOUNT',graceDays:30}});
  const deleted=[];
  await purgeDueStorePrivacy({database:db,storeId:result.request.storeId,expectedRequestId:result.request.id,nowMs:at+GRACE_MS,
    authAdmin:{async deleteUser(uid){deleted.push(uid);}},storageBucket:{async getFiles(){return [[]];}}});
  assert.equal(read(db.data,`system/storeApplications/requests/${'a'.repeat(64)}`),null);
  assert.deepEqual(deleted,['u']);
});

test("indexed paging clears more than 200 related records",async()=>{
  const {db,input}=await setup();
  for(let i=0;i<205;i++) db.data.linkInvitations.store[`inv${String(i).padStart(4,'0')}`]={entityId:'s'};
  await purgeDueStorePrivacy(input);
  assert.deepEqual(Object.keys(db.data.linkInvitations.store),['B']);
});

test("busy identity is retried without extending the deletion deadline",async()=>{
  const {db,input}=await setup();
  db.data.customerAccountDeletionLocks={u:{active:true,leaseUntilMs:Date.now()+100000}};
  const result=await reconcileStorePrivacyRetention(input);
  assert.equal(result.failed,1);
  assert.equal(read(db.data,`${ROOT}/s/deleteAfterMs`),at+GRACE_MS);
  assert.equal(read(db.data,`${ROOT}/s/nextAttemptAtMs`),at+GRACE_MS+15*60*1000);
  assert.equal(read(db.data,'userRoleProfiles/u/store/entityId'),'s');
});

test("financial settlement access survives privacy tombstone but ordinary mutations remain blocked",async()=>{
  const {db,input}=await setup(); await purgeDueStorePrivacy(input);
  const {withStoreLifecycleReadLock}=require('../src/store_lifecycle_guard');
  let entered=false;
  await withStoreLifecycleReadLock({database:db,storeIds:['s'],allowPrivacySettlement:true},async()=>{entered=true;});
  assert.equal(entered,true);
  await assert.rejects(withStoreLifecycleReadLock({database:db,storeIds:['s']},async()=>{}), e=>e.details.reason==='store_permanently_deleted');
});

test("deletion removes both pickup coordinate aliases, preserving delivery and financial evidence",async()=>{
  const {db,input}=await setup(false,true);
  Object.assign(db.data.orders.o,{storeName:'Store',storeLat:33.3,storeLng:44.3,lat:33.3,lng:44.3,
    deliveryLat:33.4,deliveryLng:44.4,phoneNumber:'recipient',driverId:'d',goodsAmount:5000,driverFare:2000});
  const retained={storeId:'s',status:'delivered',amount:5000,storeName:'Store',deliveryLat:33.4,
    deliveryLng:44.4,phoneNumber:'recipient',driverId:'d',goodsAmount:5000,driverFare:2000};
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);
  assert.deepEqual(db.data.orders.o,retained);
  assert.deepEqual(db.data.storeSettlements,{s:{amount:1234}});
});

test("deletion clears linked referral contacts even without reverse pointer, across pages",async()=>{
  assert.ok(require('../../database.rules.json').rules.storeReferrals['.indexOn'].includes('linkedStoreId'));
  const {db,input}=await setup(false,true);
  db.data.storeReferrals={foreign:{linkedStoreId:'other',phone:'keep',rewardAmount:900}};
  for(let n=0;n<201;n++) db.data.storeReferrals[`r${String(n).padStart(3,'0')}`]={
    linkedStoreId:'s',storeName:'Store',phone:'private',phoneNormalized:'private',linkedStorePhone:'private',
    storeAddress:'private',rewardAmount:1000,completedDeliveryCount:20,qualifyingOrderIds:{o:true}};
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);
  for(let n=0;n<201;n++) assert.deepEqual(db.data.storeReferrals[`r${String(n).padStart(3,'0')}`],{
    linkedStoreId:'s',storeName:'Store',rewardAmount:1000,completedDeliveryCount:20,qualifyingOrderIds:{o:true}});
  assert.equal(db.data.storeReferrals.foreign.phone,'keep');
});

test("a referral rebound between selection and transaction is not scrubbed",async()=>{
  const {db,input}=await setup(false,true);
  db.data.storeReferrals={r:{linkedStoreId:'s',phone:'belongs-to-other-after-rebind',rewardAmount:500}};
  db.beforeTransaction=path=>{
    if(path==='storeReferrals/r') db.data.storeReferrals.r.linkedStoreId='other';
  };
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);
  assert.equal(db.data.storeReferrals.r.phone,'belongs-to-other-after-rebind');
});

test("projection read failure leaves deletion resumable rather than claiming completed",async()=>{
  const {db,input,removed}=await setup(false,true);
  db.data.orders.o.storePhone='private';
  let failOnce=true;
  const guard=db.beforeGet;
  db.beforeGet=path=>{
    guard(path);
    if(path==='orders/o' && read(db.data,'orders/o/storePhone')===null &&
        read(db.data,`${ROOT}/s/status`)==='purging' && failOnce) {
      failOnce=false; throw new Error('transient projection read failure');
    }
  };
  await assert.rejects(purgeDueStorePrivacy(input),/transient projection/);
  assert.equal(read(db.data,`${ROOT}/s/status`),'purging');
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);
  assert.deepEqual(removed,['u']);
});

test("deletion reconciles stale terminal order projections for every audience without touching another order",async()=>{
  const {db,input}=await setup(false,true);
  Object.assign(db.data.orders.o,{driverId:'d',customerUid:'c',branchId:'b',agencyId:'a'});
  db.data.operationalOrderRefs={all:{o:{publicOrder:{storePhone:'private'}},other:{safe:true}}};
  for(const [scope,id] of [['drivers','d'],['customers','c'],['branches','b'],['agencies','a'],['stores','s']])
    db.data.operationalOrderRefs[scope]={[id]:{o:{publicOrder:{storeAddress:'private'}},other:{safe:true}}};
  assert.equal((await purgeDueStorePrivacy(input)).completed,true);
  for(const p of ['all','drivers/d','customers/c','branches/b','agencies/a']) {
    assert.equal(read(db.data,`operationalOrderRefs/${p}/o`),null);
    assert.deepEqual(read(db.data,`operationalOrderRefs/${p}/other`),{safe:true});
  }
  assert.equal(read(db.data,'operationalOrderRefs/stores/s'),null);
});
