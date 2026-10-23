import test from 'node:test';
import assert from 'node:assert/strict';
import {ChatNames} from './names.mjs';
import {seal,open} from './data.mjs';
import {randomBytes} from 'node:crypto';
test('saved contact names label linked-device chats without changing their IDs',()=>{
  const names=new ChatNames();names.contacts([{id:'441111@s.whatsapp.net',lid:'777@lid',name:'Fixture parent',notify:'Profile name'}]);
  const chats={'777@lid':''},messages={m:{chat:'777@lid',sentByMe:false,sender:'777@lid'}};
  assert.deepEqual(names.list(chats,messages),[{id:'777@lid',name:'Fixture parent',group:false}]);
  names.contacts([{id:'777@lid',notify:'Lower priority'}]);names.messages([{key:{remoteJid:'777@lid'},pushName:'Another profile name'}]);
  assert.equal(names.label('777@lid'),'Fixture parent');
  assert.equal(messages.m.chat,'777@lid');
  names.contacts([{id:'441111@s.whatsapp.net',name:'Updated parent'}]);assert.equal(names.label('777@lid'),'Updated parent');
});
test('existing encrypted session mappings restore names and stay encrypted on restart',()=>{
  const names=new ChatNames({}, {'441111@s.whatsapp.net':'Fixture parent'});names.keys({'441111':'777','777_reverse':'441111'});
  const key=randomBytes(32),encrypted=seal(JSON.stringify(names.snapshot()),key);
  assert.equal(encrypted.includes(Buffer.from('Fixture parent')),false);
  assert.equal(new ChatNames(JSON.parse(open(encrypted,key))).label('777@lid'),'Fixture parent');
  const before=names.label('777@lid');names.keys({'bad':'evil','other':null});assert.equal(names.label('777@lid'),before);
});
test('message alternate addresses and explicit mapping updates connect only display labels',()=>{
  const names=new ChatNames();names.contacts([{id:'441111@s.whatsapp.net',name:'Fixture parent'}]);
  names.messages([{key:{remoteJid:'777:3@lid',remoteJidAlt:'441111:0@s.whatsapp.net',fromMe:true},pushName:'Me'}]);
  assert.equal(names.label('777@lid'),'Fixture parent');
  names.mapping('888@lid','441111@s.whatsapp.net');assert.equal(names.label('777@lid'),undefined);assert.equal(names.label('888@lid'),'Fixture parent');
  names.mapping('unrelated@g.us','441111@s.whatsapp.net');assert.equal(names.label('unrelated@g.us'),undefined);
});
test('missing histories and legacy groups remain available without inventing names or duplicate contacts',()=>{
  const names=new ChatNames({}, {'one@g.us':'Fixture group'});names.contacts([{id:'441111@s.whatsapp.net',lid:'777@lid',name:'Fixture parent'}]);
  assert.equal(names.list({'777@lid':''},{}).filter(c=>c.name==='Fixture parent').length,1);
  assert.equal(names.list({},{}).filter(c=>c.name==='Fixture parent').length,1);
  assert.equal(names.list({'999@lid':''},{}).find(c=>c.id==='999@lid').name,'999');
  assert.equal(names.list({},{}).find(c=>c.id==='one@g.us').name,'Fixture group');
  assert.equal(names.list({'status@broadcast':'Status'},{}).some(c=>c.id==='status@broadcast'),false);
  names.put('999@lid','🧘'.repeat(130),4);assert.equal(Array.from(names.label('999@lid')).length,120);
});
