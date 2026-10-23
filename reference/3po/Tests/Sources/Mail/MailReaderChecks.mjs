import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';

const source=readFileSync(new URL('../../../MissionControl/Sources/Mail/MailReader.js',import.meta.url),'utf8');
function reader() {
  const context=createContext({Date,ObjC:{import:()=>{},unwrap:value=>value}});
  runInContext(source,context);return context;
}
function fixture({names=['Inbox','Sent','Archive'],enabled=true,before=false,after=before,identity='fixture@example.invalid',changedIdentity=identity,throwBody=false}={}) {
  let bodyReads=0,stateReads=0,identityReads=0;
  const mailboxes=names.map(name=>()=>({messages:{byId:id=>()=>id===42?{
    messageId:()=>++identityReads===1?identity:changedIdentity,
    readStatus:(...args)=>{assert.equal(args.length,0,'read state must never be written');return ++stateReads===1?before:after},
    content:()=>{bodyReads++;if(throwBody)throw Error('Fixture content unavailable');return name+' disposable body'}
  }:undefined}}));
  mailboxes.name=()=>names;
  const account={enabled:()=>enabled,mailboxes};
  const mail={accounts:{byId:id=>()=>id==='fixture-account'?account:undefined}};
  return {mail,reads:()=>({bodyReads,stateReads,identityReads})};
}
const request={accountID:'fixture-account',messageID:42,expectedInternetMessageID:'fixture@example.invalid'};

test('account discovery returns healthy inboxes and exact failed-account identities together',()=>{
  const healthyBoxes=[()=>({name:()=> 'Inbox'})];healthyBoxes.name=()=>['Inbox'];
  const brokenBoxes=[];brokenBoxes.name=()=>[];
  const accounts=[
    {enabled:()=>true,id:()=> 'healthy',name:()=> 'Healthy',mailboxes:healthyBoxes},
    {enabled:()=>true,id:()=> 'broken',name:()=> 'Broken',mailboxes:brokenBoxes}
  ];
  const result=reader().probeInboxes({accounts:()=>accounts});
  assert.deepEqual(Array.from(result.accounts,account=>account.id),['healthy']);
  assert.deepEqual(Array.from(result.unavailableAccounts,account=>account.id),['broken']);
  assert.equal(result.errors.length,1);assert.ok(result.accountErrors.broken.startsWith('Account broken:'));
});

test('actual JXA helper previews exact Inbox/Sent/Archive sources with unchanged unread state and no writes',()=>{
  for(const name of ['Inbox','Sent','Archive'])for(const state of [false,true,0,1]){
    const f=fixture({before:state}),context=reader();
    const result=context.runBody(f.mail,{...request,mailboxName:name});
    assert.equal(result.errors.length,0);assert.equal(result.body,name+' disposable body');
    assert.equal(result.unreadBefore,state===false||state===0);assert.equal(result.unreadAfter,result.unreadBefore);
    assert.deepEqual(f.reads(),{bodyReads:1,stateReads:2,identityReads:2});
  }
});
test('changed exact message identity is rejected before content access',()=>{
  const f=fixture({identity:'replacement@example.invalid'});
  const result=reader().runBody(f.mail,request);
  assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,0);
});
test('ambiguous mailbox, disabled account, different account and vanished ID cannot fall through to another source',()=>{
  const cases=[
    [fixture({names:['Archive','Archive']}),{...request,mailboxName:'Archive'}],
    [fixture({enabled:false}),request],
    [fixture(),{...request,accountID:'different-account'}],
    [fixture(),{...request,messageID:43}],
    [fixture(),{...request,mailboxName:'Missing'}]
  ];
  for(const [f,input] of cases){const result=reader().runBody(f.mail,input);assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,0);}
});
test('missing read status fails closed before reading; changed or unavailable after-state discards the body',()=>{
  for(const before of [null,'false',undefined,2]){
    const f=fixture({before:before===undefined?null:before});
    const result=reader().runBody(f.mail,request);
    assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,0);
  }
  for(const after of [true,null,'false']){
    const f=fixture({before:false,after});const result=reader().runBody(f.mail,request);
    assert.equal(result.body,'');assert.equal(result.errors.length,1);assert.equal(f.reads().bodyReads,1);
  }
});
test('identity changes during content retrieval or unavailable content never become a verified preview',()=>{
  for(const f of [fixture({changedIdentity:'changed@example.invalid'}),fixture({throwBody:true})]){
    const result=reader().runBody(f.mail,request);assert.equal(result.body,'');assert.equal(result.errors.length,1);
  }
});

function batchFixture({count=75,changed=false}={}) {
  let idReads=0,individualReads=0,filterReads=0,resolutions=0,resolvedIDReads=0;
  const ids=Array.from({length:count},(_,i)=>i+1);
  const dated=()=>{resolutions++;return ids.map((id,index)=>({
    id:()=>{resolvedIDReads++;return changed&&resolvedIDReads>ids.length?ids[ids.length-1-index]:id},
    messageId:()=>`fixture${id}@example.invalid`,
    subject:()=>id===70?'Engineering Part IIB: module choices':'Unrelated newsletter',
    sender:()=> 'Coordinator <fixture@example.invalid>'
  }))};
  Object.assign(dated,{
    id:()=>{idReads++;return changed&&idReads>1?ids.slice().reverse():ids},
    subject:()=>ids.map(id=>id===70?'Engineering Part IIB: module choices':'Unrelated newsletter'),
    sender:()=>ids.map(()=> 'Coordinator <fixture@example.invalid>'),
    messageId:()=>ids.map(id=>`fixture${id}@example.invalid`)
  });
  const box={messages:{
    whose:()=>{filterReads++;return dated},
    byId:id=>()=>{individualReads++;return {
      dateReceived:()=>new Date('2026-10-05T12:00:00Z'),dateSent:()=>new Date('2026-10-05T12:00:00Z'),
      messageId:()=>`fixture${id}@example.invalid`,sender:()=> 'Coordinator <fixture@example.invalid>',
      subject:()=>id===70?'Engineering Part IIB: module choices':'Unrelated newsletter',
      readStatus:()=>false,wasRepliedTo:()=>false,flaggedStatus:()=>false,
      toRecipients:{address:()=>['Alice@example.invalid'],name:()=>['Alice']}
    }}
  }};
  const mailboxes=[()=>box];mailboxes.name=()=>['Inbox'];
  const account={enabled:()=>true,name:()=> 'Fixture',mailboxes};
  return {mail:{accounts:{byId:()=>()=>account}},reads:()=>({idReads,individualReads,filterReads,resolutions})};
}
const batchRequest={accountID:'fixture-account',start:Date.parse('2026-10-05T00:00:00Z')/1000,end:Date.parse('2026-10-06T00:00:00Z')/1000,offset:0,limit:20};
test('arrival scan gets date-filtered IDs in one bulk read, then only the bounded page',()=>{
  const f=batchFixture(),result=reader().runBatch(f.mail,batchRequest);
  assert.equal(result.messages.length,20);assert.equal(result.complete,false);assert.equal(result.nextOffset,20);
  assert.deepEqual(f.reads(),{idReads:1,individualReads:20,filterReads:1,resolutions:0});
  const second=reader().runBatch(f.mail,{...batchRequest,messageIDs:Array.from(result.messageIDs),offset:20});
  assert.equal(second.messages.length,20);assert.equal(f.reads().idReads,1,'resuming must reuse exact saved IDs');
});
test('on-demand header matching finds a later hit without spending pages on unrelated mail',()=>{
  const f=batchFixture(),result=reader().runBatch(f.mail,{...batchRequest,searchTerms:['Part IIB'],mailboxRole:'inbox'});
  assert.equal(result.messages.length,1);assert.equal(result.messages[0].messageID,70);assert.equal(result.complete,true);
  assert.equal(f.reads().individualReads,1);assert.equal(f.reads().idReads,0);assert.equal(f.reads().resolutions,1);
});
test('changing header collection fails closed; Sent retains recipient-only candidates',()=>{
  assert.throws(()=>reader().runBatch(batchFixture({changed:true}).mail,{...batchRequest,searchTerms:['IIB']}),/changed or moved/);
  const result=reader().runBatch(batchFixture().mail,{...batchRequest,searchTerms:['Alice'],mailboxRole:'sent'});
  assert.equal(result.messages.length,20);assert.equal(result.messages[0].recipients[0],'Alice <Alice@example.invalid>');
});

test('identity delta finds late received mail without rehydrating known headers; reused native IDs do not hide replacements',()=>{
  const known=Object.fromEntries(Array.from({length:75},(_,i)=>[String(i+1),`fixture${i+1}@example.invalid`]));
  delete known['70'];known['71']='old-replaced@example.invalid';
  const f=batchFixture(),result=reader().runBatch(f.mail,{...batchRequest,knownMessages:known});
  assert.deepEqual(Array.from(result.messageIDs),[70,71]);assert.equal(result.messages.length,2);
  assert.equal(result.retainedIDs.length,73);assert.equal(f.reads().individualReads,2);assert.equal(f.reads().idReads,0);assert.equal(f.reads().resolutions,1);
  const allKnown=reader().runBatch(batchFixture().mail,{...batchRequest,knownMessages:Object.fromEntries(Array.from({length:75},(_,i)=>[String(i+1),`fixture${i+1}@example.invalid`]))});
  assert.equal(allKnown.messages.length,0);assert.equal(allKnown.retainedIDs.length,75);assert.equal(allKnown.complete,true);
});

test('resolved arrival identities retain continuation cursors and never rerun date filtering on later pages',()=>{
  const f=batchFixture(),known={'1':'fixture1@example.invalid'};
  const first=reader().runBatch(f.mail,{...batchRequest,knownMessages:known});
  const next=reader().runBatch(f.mail,{...batchRequest,messageIDs:Array.from(first.messageIDs),offset:first.nextOffset,knownMessages:known});
  assert.equal(next.messages[0].messageID,22);
  assert.deepEqual(f.reads(),{idReads:0,individualReads:40,filterReads:1,resolutions:1});
});
test('a resolved identity change fails closed before hiding known rows',()=>{
  assert.throws(()=>reader().runBatch(batchFixture({changed:true}).mail,{...batchRequest,knownMessages:{'1':'fixture1@example.invalid'}}),/changed or moved/);
});

// Mail's Apple-event date predicate truncates to whole seconds, independently
// of the helper's exact logical interval. Reproduce that transport behaviour.
function datePrecisionFixture(dates,hydratedDates=dates) {
  let queries=0;
  const record=(id,received)=>({
    id:()=>Number(id),messageId:()=>`precision${id}@example.invalid`,
    dateReceived:()=>new Date(received),dateSent:()=>new Date(received),
    sender:()=> 'Fixture',subject:()=> 'Fixture date boundaries',
    readStatus:()=>false,wasRepliedTo:()=>false,flaggedStatus:()=>false
  });
  const records=Object.entries(dates).map(([id,date])=>record(id,date));
  const messages={
    whose:({_and:[lower,upper]})=>{
      queries++;
      const field=Object.keys(lower)[0];
      const start=Math.floor(lower[field]._greaterThanEquals.getTime()/1000)*1000;
      const end=Math.floor(upper[field]._lessThan.getTime()/1000)*1000;
      const selected=records.filter(message=>message[field]().getTime()>=start&&message[field]().getTime()<end);
      return Object.assign(()=>selected,{id:()=>selected.map(message=>message.id())});
    },
    byId:id=>()=>record(id,hydratedDates[id])
  };
  const mailboxes=[()=>({messages})];mailboxes.name=()=>['Inbox'];
  const account={enabled:()=>true,name:()=> 'Fixture',mailboxes};
  return {mail:{accounts:{byId:()=>()=>account}},queries:()=>queries};
}
const fractionalRequest={...batchRequest,start:Date.parse('2026-10-05T12:00:00.731Z')/1000,end:Date.parse('2026-10-05T12:00:03.421Z')/1000};
const boundaryDates={1:'2026-10-05T12:00:00Z',2:'2026-10-05T12:00:01Z',3:'2026-10-05T12:00:02Z',4:'2026-10-05T12:00:03Z',5:'2026-10-05T12:00:04Z'};
test('whole-second Mail predicates preserve exact fractional range before known identity retention',()=>{
  const f=datePrecisionFixture(boundaryDates),result=reader().runBatch(f.mail,{...fractionalRequest,knownMessages:{'1':'precision1@example.invalid','2':'precision2@example.invalid'}});
  assert.deepEqual(Array.from(result.messageIDs),[3,4]);
  assert.deepEqual(Array.from(result.retainedIDs),[2]);
  assert.equal(result.messages.length,2);assert.equal(result.complete,true);assert.equal(f.queries(),1);
  const direct=reader().runBatch(datePrecisionFixture(boundaryDates).mail,fractionalRequest);
  assert.deepEqual(Array.from(direct.messageIDs),[2,3,4]);
});
test('persisted pages retain exact dates and reject actual moved or unavailable dates without requerying',()=>{
  for(const changedDate of ['2026-10-05T12:00:00Z','2026-10-05T12:00:04Z',undefined]) {
    const f=datePrecisionFixture(boundaryDates,{...boundaryDates,3:changedDate});
    assert.throws(()=>reader().runBatch(f.mail,{...fractionalRequest,messageIDs:[3]}),/changed or moved/);
    assert.equal(f.queries(),0,'a saved exact ID page must never silently broaden or replace its range');
  }
});
