import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { seal, open, textMessage, boundedMessages } from './data.mjs';
import { ReceivedTextCache, deliverIfCurrent } from './reconciliation.mjs';

const original = (chat='a',id='same',text='Original') => ({key:{remoteJid:chat,id,fromMe:true},pushName:'Fixture',messageTimestamp:100,message:{conversation:text}});
const edit = (text,at=200) => ({key:{remoteJid:'a',id:'same',fromMe:false},update:{messageTimestamp:at,message:{editedMessage:{message:{conversation:text}}}}});

test('older history cannot undo an edit, including after interrupted persistence and restart',()=>{
  const cache=new ReceivedTextCache();cache.ingest([original(),original('b')]);
  const previousMessages=JSON.parse(JSON.stringify(cache.messages));
  cache.update([edit('Corrected')]);
  cache.ingest([original()]);
  assert.equal(cache.messages['a:same'].text,'Corrected');
  assert.equal(cache.messages['a:same'].sender,'Fixture');
  assert.equal(cache.messages['a:same'].sentByMe,true);
  assert.equal(cache.messages['a:same'].time,100000);
  assert.equal(cache.messages['b:same'].text,'Original');
  const key=randomBytes(32),encrypted=seal(JSON.stringify(cache.journal()),key);
  assert.equal(encrypted.includes(Buffer.from('Corrected')),false);
  // Simulate a crash after journal save but before message snapshot save.
  const restored=new ReceivedTextCache(previousMessages,JSON.parse(open(encrypted,key)));
  restored.ingest([original()]);
  assert.equal(restored.messages['a:same'].text,'Corrected');
  restored.update([edit('Stale edit',150)]);
  assert.equal(restored.messages['a:same'].text,'Corrected');
});

test('edits and revocations arriving before their originals remain authoritative',()=>{
  const cache=new ReceivedTextCache();cache.update([edit('Pending edit')]);
  assert.equal(Object.keys(cache.messages).length,0);
  cache.ingest([original()]);assert.equal(cache.messages['a:same'].text,'Pending edit');
  cache.update([{key:{remoteJid:'a',id:'same'},update:{message:null}}],300000);
  const restored=new ReceivedTextCache({},cache.journal());
  restored.ingest([original(),original('b')]);restored.update([edit('Must not resurrect',400)]);
  assert.equal(restored.messages['a:same'],undefined);assert.equal(restored.messages['b:same'].text,'Original');
  restored.update([{key:{remoteJid:'c',id:'missing'},update:{message:null}}]);
  restored.ingest([original('c','missing')]);assert.equal(restored.messages['c:missing'],undefined);
});

test('exact and chat deletions reject old history while allowing new chat messages',()=>{
  const cache=new ReceivedTextCache();cache.ingest([original(),original('b')]);
  cache.delete({keys:[{remoteJid:'a',id:'same'}]},200000);
  cache.ingest([original()]);assert.equal(cache.messages['a:same'],undefined);
  cache.delete({all:true,jid:'b'},200000);
  cache.ingest([original('b','historical'),{...original('b','new'),messageTimestamp:201}]);
  assert.equal(cache.messages['b:historical'],undefined);assert.equal(cache.messages['b:new'].text,'Original');
  const restored=new ReceivedTextCache(cache.messages,cache.journal());
  restored.ingest([original('b','another-old')]);assert.equal(restored.messages['b:another-old'],undefined);
});

test('receipt-only updates and malformed identities do not mutate text; non-text edits remove it',()=>{
  const cache=new ReceivedTextCache();cache.ingest([original()]);
  const before=cache.messages;
  assert.equal(cache.update([{key:{remoteJid:'a',id:'same'},update:{status:4}},{key:{id:'same'},update:{message:null}}]),false);
  assert.equal(cache.messages,before,'status-only events do not even rebuild the bounded message snapshot');
  assert.equal(cache.messages['a:same'].text,'Original');
  cache.update([{key:{remoteJid:'a',id:'same'},update:{message:{imageMessage:{}}}}]);
  cache.ingest([original()]);assert.equal(cache.messages['a:same'],undefined);
});

test('a large receipt-only batch requires no persistence or publication',()=>{
  const messages=Object.fromEntries(Array.from({length:2000},(_,i)=>['a:'+i,{id:'a:'+i,chat:'a',sender:'Fixture',text:'x'.repeat(5000),time:100000,sentByMe:true}]));
  const cache=new ReceivedTextCache(messages),before=cache.messages;
  const updates=Array.from({length:2000},(_,i)=>({key:{remoteJid:'a',id:String(i)},update:{status:4}}));
  assert.equal(cache.update(updates),false);
  assert.equal(cache.messages,before);
  assert.equal(Object.keys(cache.entries).length,0);
});

test('cache bytes, Unicode truncation and replay journal remain bounded',()=>{
  const long='🧘'.repeat(7000);
  const parsed=textMessage(original('a','long',long));
  assert.equal(parsed.text.length,12000);
  const odd=textMessage(original('a','odd','x'+long));
  assert.equal(odd.text.length,11999);assert.equal(odd.text.endsWith('🧘'),true);
  const records=Object.fromEntries(Array.from({length:2000},(_,i)=>[String(i),{...parsed,id:String(i),time:i}]));
  const bounded=boundedMessages(records);
  assert.ok(Object.keys(bounded).length<2000);assert.ok(Buffer.byteLength(JSON.stringify(bounded))<=12_000_000);
  const cache=new ReceivedTextCache();
  cache.delete({keys:Array.from({length:4500},(_,i)=>({remoteJid:'a',id:String(i)}))},200000);
  for(let i=0;i<300;i++)cache.delete({all:true,jid:'chat'+i},200000+i);
  const journal=cache.journal();assert.ok(Object.keys(journal.entries).length<=4000);assert.equal(Object.keys(journal.deletedChats).length,256);
});

test('asynchronous results are discarded after connection replacement or stopping',async()=>{
  let current=true,release,delivered=[];
  const pending=deliverIfCurrent(()=>current,()=>new Promise(resolve=>{release=resolve}),value=>delivered.push(value));
  current=false;release('obsolete QR');await pending;assert.deepEqual(delivered,[]);
  let prepared=false;
  await deliverIfCurrent(()=>false,async()=>{prepared=true;return 'unused'},value=>delivered.push(value));
  assert.equal(prepared,false);
  await deliverIfCurrent(()=>true,async()=> 'current QR',value=>delivered.push(value));
  assert.deepEqual(delivered,['current QR']);
  let reject;
  current=true;
  const failed=deliverIfCurrent(()=>current,()=>new Promise((_,fail)=>{reject=fail}),value=>delivered.push(value));
  current=false;reject(Error('obsolete failure'));await failed;
  await assert.rejects(deliverIfCurrent(()=>true,async()=>{throw Error('current failure')},()=>{}),/current failure/);
});
