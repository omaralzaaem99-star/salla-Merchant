"use strict";
const test=require('node:test'), assert=require('node:assert/strict');
const {StoreLifecycleDatabase,read}=require('./helpers/store_lifecycle_database');
const app=require('../src/store_applications');
const actor={uid:'manager',isGeneralManager:true};
const input={requestId:'guest-request-12345678901',storeName:'متجر الاختبار',phone:'٠٧٧٧٥٦٥٥٣٦٧',address:'بغداد المنصور شارع الرواد',consent:true};
const send=(database,data=input,ip='127.0.0.1')=>app.submit({database,data,ip,nowMs:1791600000000});

test('deleted or deleting identity cannot create a new application using an unexpired token',async()=>{
 for(const fence of [{authDeleted:true},{authDeletionFenced:true}]) {
  const db=new StoreLifecycleDatabase({customerAccountDeletionLocks:{deleted:fence}});
  await assert.rejects(app.submit({database:db,data:input,ip:'ip',applicantUid:'deleted'}));
  assert.equal(read(db.data,app.ROOT),null);
 }
});

test('deleted identity rejection survives the real callable error mapping without becoming internal',async()=>{
 const fs=require('fs'),vm=require('vm'),s=fs.readFileSync(require.resolve('../src/firebase_functions'),'utf8');
 const mapperCode=s.slice(s.indexOf('function storeAccountManagementCallableError('),s.indexOf('function storeLeaderWorkspaceCallableError('));
 const callableCode=s.slice(s.indexOf('async function runStoreAccountManagementCallable('),s.indexOf('async function runStoreLeaderWorkspaceCallable('));
 const {StoreAccountManagementError}=require('../src/store_account_management');
 for(const fence of [{authDeleted:true},{authDeletionFenced:true}]) {
  const db=new StoreLifecycleDatabase({customerAccountDeletionLocks:{deleted:fence}});
  const fn=vm.runInNewContext(mapperCode+'\n'+callableCode+'\nrunStoreAccountManagementCallable',{
   StoreAccountManagementError,StoreReferralError:class extends Error {},
   HttpsError:class extends Error {constructor(code,message,details){super(message);this.code=code;this.details=details;}},
   getWorker:()=>{},callableData:r=>r.data,require:()=>app,getDatabase:()=>db,
   runWhenFirebaseOwnsOperations:async(_e,work)=>work(),
  });
  await assert.rejects(fn({auth:{uid:'deleted'},rawRequest:{ip:'ip'},data:{...input,action:'create_pending_store_account'}}),{code:'failed-precondition'});
  assert.equal(read(db.data,app.ROOT),null);
 }
});

test('pending account belongs to submitting session; preparation is not approval; retries do not grant or steal access',async()=>{
 const db=new StoreLifecycleDatabase({});
 const result=await app.submit({database:db,data:input,ip:'ip',applicantUid:'applicant'});
 const id=result.applicationId;assert.match(id,/^[a-f0-9]{64}$/);
 assert.equal(db.data.userRoleProfiles,undefined);
 await assert.rejects(app.ownStatus({database:db,uid:'intruder',data:{applicationId:id}}),{code:'permission-denied'});
 await assert.rejects(app.ownStatus({database:db,uid:'',data:{applicationId:id}}),{code:'unauthenticated'});
 await assert.rejects(app.submit({database:db,data:input,ip:'ip',applicantUid:'intruder'}),{code:'already-exists'});
 await assert.rejects(app.submit({database:db,data:{...input,address:'different address'},ip:'ip',applicantUid:'applicant'}),{code:'failed-precondition'});
 assert.deepEqual(await app.ownStatus({database:db,uid:'applicant',data:{applicationId:id}}),{ok:true,status:'pending'});
 db.data.stores={s1:{phone:'07775655367',active:true,branchId:'b1',serviceZoneId:'z1',linkCode:'ABCD1234',name:'Store'}};
 db.data.linkInvitations={store:{ABCD1234:{active:true,entityId:'s1'}}};
 await app.link({database:db,actor,applicationId:id,storeId:'s1'});
 const row=read(db.data,`${app.ROOT}/${id}`);assert.equal(row.status,'prepared');
 assert.equal((await app.ownStatus({database:db,uid:'applicant',data:{applicationId:id}})).linkCode,undefined);
 const approval={applicationId:id,requestId:'approval-request-1234567890',expectedRevision:row.revision,contactConfirmed:true};
 await assert.rejects(app.approve({database:db,actor:{uid:'staff'},data:approval}),{code:'permission-denied'});
 await assert.rejects(app.approve({database:db,actor,data:{...approval,contactConfirmed:false}}),{code:'failed-precondition'});
 await assert.rejects(app.approve({database:db,actor,data:{...approval,expectedRevision:999}}),{code:'aborted'});
 db.coldPaths.add(`${app.ROOT}/${id}`);
 await app.approve({database:db,actor,data:approval});
 const approved=structuredClone(read(db.data,`${app.ROOT}/${id}`));
 await app.approve({database:db,actor,data:approval});
 assert.deepEqual(read(db.data,`${app.ROOT}/${id}`),approved);
 const status=await app.ownStatus({database:db,uid:'applicant',data:{applicationId:id}});
 assert.equal(status.status,'approved');assert.equal(status.linkCode,'ABCD1234');
 assert.equal(db.data.userRoleProfiles,undefined); // Login remains the existing trusted callable.
 const baseRef=db.ref.bind(db); let audit=0;
 db.ref=(path='')=>({...baseRef(path),push:()=>({key:`test-audit-${++audit}`})});
 const {linkAccountWithCode}=require('../src/code_login');
 await linkAccountWithCode({database:db,uid:'applicant',input:{role:'store',requestedName:status.storeName,phone:status.phone,linkCode:status.linkCode}});
 assert.equal(read(db.data,'stores/s1/authUid'),'applicant');
 assert.equal(read(db.data,'userRoleProfiles/applicant/store/entityId'),'s1');
 assert.equal((await app.ownStatus({database:db,uid:'applicant',data:{applicationId:id}})).status,'active');
 db.data.stores.s1.authUid='another-device';
 assert.deepEqual(await app.ownStatus({database:db,uid:'applicant',data:{applicationId:id}}),{ok:true,status:'sign_in_required'});
 db.data.stores.s1.authUid='applicant';
 db.data.userRoleProfiles={applicant:{store:{entityId:'s1',active:true}}};
 assert.deepEqual(await app.ownStatus({database:db,uid:'applicant',data:{applicationId:id}}),{ok:true,status:'active'});
 db.data.userRoleProfiles.applicant.store.active=false;
 assert.equal((await app.ownStatus({database:db,uid:'applicant',data:{applicationId:id}})).status,'sign_in_required');
});

test('legacy phone enquiry cannot be claimed as a pending account; incomplete store cannot be approved',async()=>{
 const db=new StoreLifecycleDatabase({});await send(db);
 await assert.rejects(app.submit({database:db,data:input,ip:'ip',applicantUid:'new'}),{code:'already-exists'});
 const db2=new StoreLifecycleDatabase({});
 const {applicationId}=await app.submit({database:db2,data:input,ip:'ip',applicantUid:'owner'});
 db2.data.stores={s:{phone:'07775655367',active:true}};
 await app.link({database:db2,actor,applicationId,storeId:'s'});
 await assert.rejects(app.approve({database:db2,actor,data:{applicationId,contactConfirmed:true,requestId:'approval-123456789012345',expectedRevision:2}}),{code:'failed-precondition'});
 const db3=new StoreLifecycleDatabase({stores:{store_75655367:{active:true,phone:'07775655367'}}});
 await assert.rejects(app.submit({database:db3,data:input,ip:'ip',applicantUid:'owner'}),{code:'already-exists'});
 assert.equal(read(db3.data,app.ROOT),null);
});
test('public enquiry normalizes Arabic digits without creating account or exposing data; retries and cold callback deduplicate',async()=>{
 const db=new StoreLifecycleDatabase({});
 const result=await send(db); assert.equal(result.received,true);
 const rows=read(db.data,app.ROOT),row=Object.values(rows)[0];
 assert.equal(row.phone,'07775655367');assert.equal(row.phoneVerified,false);
 db.coldPaths.add(`${app.ROOT}/${row.id}`);
 await send(db,{...input,storeName:'different name',requestId:'second-request-1234567890'});
 assert.deepEqual(read(db.data,app.ROOT),rows);
 assert.equal(JSON.stringify(result).includes(input.address),false);
 assert.deepEqual(Object.keys(db.data),['system']);
});
test('invalid input cannot write and enquiry is rate-limited',async()=>{
 for(const change of [{phone:'123'}, {consent:false}, {address:'a'}, {storeName:'a\nb'}, {requestId:'short'}]) {
  const db=new StoreLifecycleDatabase({}); await assert.rejects(send(db,{...input,...change}),{code:'invalid-argument'}); assert.deepEqual(db.data,{});
 }
 const db=new StoreLifecycleDatabase({});for(let i=0;i<30;i++)await send(db);
 await assert.rejects(send(db),{code:'resource-exhausted'});
});
test('only general manager can list applications or link an existing account, including cold and repeated links',async()=>{
 const db=new StoreLifecycleDatabase({});await send(db);const row=Object.values(read(db.data,app.ROOT))[0];
 for(const bad of [{},{uid:'employee',permissionKeys:['manage_stores']},{uid:'store'}]) {
  await assert.rejects(app.list({database:db,actor:bad,data:{}}),{code:'permission-denied'});
  await assert.rejects(app.validateRegistration({database:db,actor:bad,data:{merchantApplicationId:row.id,phone:input.phone}}),{code:'permission-denied'});
 }
 await app.validateRegistration({database:db,actor,data:{merchantApplicationId:row.id,phone:input.phone}});
 await assert.rejects(app.validateRegistration({database:db,actor,data:{merchantApplicationId:row.id,phone:'07701234567'}}),{code:'failed-precondition'});
 db.data.stores={store1:{phone:'07775655367'}};db.coldPaths.add(`${app.ROOT}/${row.id}`);
 await app.link({database:db,actor,applicationId:row.id,storeId:'store1'});
 const completed=structuredClone(read(db.data,app.ROOT));
 await app.link({database:db,actor,applicationId:row.id,storeId:'store1'});
 assert.deepEqual(read(db.data,app.ROOT),completed);
 assert.equal(Object.values(completed)[0].status,'completed');
});
test('callable only permits submission before admin authorization',async()=>{
 const fs=require('fs'),vm=require('vm'),s=fs.readFileSync(require.resolve('../src/firebase_functions'),'utf8');
 const code=s.slice(s.indexOf('async function runStoreAccountManagementCallable('),s.indexOf('async function runStoreLeaderWorkspaceCallable('));
 const db=new StoreLifecycleDatabase({});let auth=0;
 const fn=vm.runInNewContext(code+'\nrunStoreAccountManagementCallable',{
  getWorker:()=>{},callableData:r=>r.data,require:n=>n==='./store_applications'?app:{SELF_ACTIONS:new Set()},getDatabase:()=>db,
  runWhenFirebaseOwnsOperations:async(_e,work)=>work(),authorizeStoreAccountManagement:async()=>{auth++;throw Object.assign(Error('denied'),{code:'unauthenticated'});},storeAccountManagementCallableError:e=>e,
 });
 await fn({data:{...input,action:'submit_store_application'},rawRequest:{ip:'127.0.0.1'}});assert.equal(auth,0);
 for(const action of ['register','list_store_applications','update_account'])await assert.rejects(fn({data:{action}}),{code:'unauthenticated'});
 assert.equal(auth,3);
});

test('pending callable authenticates status and ignores a client-supplied applicant uid',async()=>{
 const fs=require('fs'),vm=require('vm'),s=fs.readFileSync(require.resolve('../src/firebase_functions'),'utf8');
 const code=s.slice(s.indexOf('async function runStoreAccountManagementCallable('),s.indexOf('async function runStoreLeaderWorkspaceCallable('));
 const db=new StoreLifecycleDatabase({});
 const fn=vm.runInNewContext(code+'\nrunStoreAccountManagementCallable',{
  getWorker:()=>{},callableData:r=>r.data,require:()=>app,getDatabase:()=>db,
  HttpsError:class extends Error {constructor(code,message){super(message);this.code=code;}},
  runWhenFirebaseOwnsOperations:async(_e,work)=>work(),storeAccountManagementCallableError:e=>e,
 });
 for(const action of ['create_pending_store_account','get_pending_store_account']) await assert.rejects(fn({data:{...input,action}}),{code:'unauthenticated'});
 const result=await fn({auth:{uid:'trusted-session'},rawRequest:{ip:'ip'},data:{...input,action:'create_pending_store_account',applicantUid:'victim'}});
 assert.equal(read(db.data,`${app.ROOT}/${result.applicationId}`).applicantUid,'trusted-session');
 await assert.rejects(fn({auth:{uid:'victim'},data:{action:'get_pending_store_account',applicationId:result.applicationId}}),{code:'permission-denied'});
});
test('inbox pagination handles equal timestamps and excludes private submission receipts',async()=>{
 const rows=Array.from({length:65},(_,i)=>({id:i.toString(16).padStart(64,'0'),createdAt:'2026-10-10T00:00:00.000Z',requestId:'private',digest:'private',storeName:`Store ${i}`}));
 const database={ref(path){assert.equal(path,app.ROOT);return {orderByChild(field){assert.equal(field,'createdAt');let end=null,limit=0;return {
  endAt(at,id){end={at,id};return this;},limitToLast(n){limit=n;return this;},async get(){const data=rows.filter(r=>!end||r.createdAt<end.at||(r.createdAt===end.at&&r.id<=end.id)).slice(-limit);return {forEach(cb){data.forEach(r=>cb({val:()=>r}));}};}
 };}};}};
 const seen=[];let cursor;do{const result=await app.list({database,actor,data:{cursor}});assert.ok(result.applications.length<=30);for(const row of result.applications){assert.equal(row.requestId,undefined);assert.equal(row.digest,undefined);seen.push(row.id);}cursor=result.nextCursor;}while(cursor);
 assert.equal(new Set(seen).size,65);assert.equal(seen.length,65);assert.deepEqual(seen,[...rows].reverse().map(r=>r.id));
});
