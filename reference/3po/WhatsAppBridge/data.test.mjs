import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {BufferJSON} from '@whiskeysockets/baileys';
import {seal,open,textMessage,boundedMessages,applyMessageUpdates,applyMessageDeletes} from './data.mjs';
test('encrypted credentials round trip without plaintext, reject wrong key and tampering',()=>{
  const key=randomBytes(32), value={secret:Buffer.from('disposable session fixture')};
  const encrypted=seal(JSON.stringify(value,BufferJSON.replacer),key);
  assert.equal(encrypted.includes(Buffer.from('disposable')),false);
  assert.deepEqual(JSON.parse(open(encrypted,key),BufferJSON.reviver),value);
  assert.throws(()=>open(encrypted,randomBytes(32)));
  const changed=Buffer.from(encrypted);changed[changed.length-1]^=1;
  assert.throws(()=>open(changed,key));
});
test('chat identity prevents collisions and text wrappers preserve content',()=>{
  const fixture={key:{remoteJid:'chat-a',id:'same'},messageTimestamp:100,message:{ephemeralMessage:{message:{extendedTextMessage:{text:'Fixture'}}}}};
  const first=textMessage(fixture), second=textMessage({...fixture,key:{remoteJid:'chat-b',id:'same'}});
  assert.notEqual(first.id,second.id);assert.equal(first.text,'Fixture');assert.equal(first.time,100000);
  const records={[first.id]:first,[second.id]:second};records[first.id]=first;
  assert.equal(Object.keys(records).length,2);
  assert.equal(textMessage({...fixture,key:{remoteJid:'status@broadcast',id:'same'}}),undefined);
  assert.equal(textMessage({...fixture,message:{imageMessage:{}}}),undefined);
  assert.equal(textMessage({...fixture,messageTimestamp:undefined}),undefined);
});
test('cache keeps newest 2000 messages',()=>{
  const records=Object.fromEntries(Array.from({length:2010},(_,i)=>[String(i),{time:i}]));
  const result=boundedMessages(records);assert.equal(Object.keys(result).length,2000);
  assert.equal(result['0'],undefined);assert.equal(result['2009'].time,2009);
});
test('Baileys edit wrappers replace text without changing original identity, sender, direction or time',()=>{
  const a=textMessage({key:{remoteJid:'a',id:'same',fromMe:true},pushName:'Fixture',messageTimestamp:100,message:{conversation:'Old text'}});
  const b={...a,id:'b:same',chat:'b'};
  const edited=applyMessageUpdates({[a.id]:a,[b.id]:b},[{key:{remoteJid:'a',id:'same',fromMe:false},update:{messageTimestamp:200,message:{editedMessage:{message:{conversation:'Corrected'}}}}}]);
  assert.equal(edited[a.id].text,'Corrected');assert.equal(edited[a.id].sentByMe,true);assert.equal(edited[a.id].time,100000);assert.equal(edited[a.id].sender,'Fixture');assert.deepEqual(edited[b.id],b);
  assert.equal(a.text,'Old text');
  assert.deepEqual(applyMessageUpdates(edited,[{key:{remoteJid:'a',id:'same'},update:{status:4}}]),edited);
  assert.equal(applyMessageUpdates(edited,[{key:{remoteJid:'a',id:'same'},update:{message:{imageMessage:{}}}}])[a.id],undefined);
  assert.deepEqual(applyMessageUpdates({},[{key:{remoteJid:'a',id:'missing'},update:{message:{conversation:'Unknown'}}}]),{});
});
test('revocation and deletion preserve messages with the same ID in other chats',()=>{
  const records={'a:same':{id:'a:same',chat:'a',time:1},'b:same':{id:'b:same',chat:'b',time:1}};
  assert.deepEqual(Object.keys(applyMessageUpdates(records,[{key:{remoteJid:'a',id:'same'},update:{message:null}}])),['b:same']);
  assert.deepEqual(Object.keys(applyMessageDeletes(records,{keys:[{remoteJid:'a',id:'same'}]})),['b:same']);
  assert.deepEqual(Object.keys(applyMessageDeletes(records,{all:true,jid:'a'})),['b:same']);
  assert.equal(Object.keys(records).length,2);
});
