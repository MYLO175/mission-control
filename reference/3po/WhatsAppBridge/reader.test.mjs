import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { open } from './data.mjs';

async function exerciseReader(switchAccount=false) {
  const root=mkdtempSync(join(tmpdir(),'missioncontrol-wa-fixture-'));
  const key=randomBytes(32),events=[];
  // Only the two transport/QR imports are replaced. The actual reader, encrypted
  // files, pipe protocol, reconnect timer and bundled Node runtime run normally.
  // This fixture has no network socket and never reads the user's app storage.
  writeFileSync(join(root,'socket.mjs'),`
    import {EventEmitter} from 'node:events';
    export const BufferJSON={};
    export const initAuthCreds=()=>({me:{id:'fixture:1@s.whatsapp.net'}});
    export const DisconnectReason={loggedOut:401};
    export const proto={Message:{AppStateSyncKeyData:{fromObject:v=>v}}};
    let count=0,previous;
    const message=chat=>({key:{remoteJid:chat,id:'same'},messageTimestamp:100,pushName:'Fixture',message:{conversation:'Original'}});
    export default function makeSocket(config){
      const index=++count,ev=new EventEmitter();
      const identity=index===2&&${switchAccount}?'other-fixture:1@s.whatsapp.net':'fixture:1@s.whatsapp.net';
      config.auth.creds.me.id=identity;
      const socket={ev,user:{id:identity},end(){},groupMetadata:async()=>({}),authState:config.auth,
        appStatePatchMutex:{mutex:async fn=>fn()},resyncAppState:async(collections,initial)=>{
          if(JSON.stringify(collections)!=='["critical_unblock_low"]'||initial!==false)throw Error('Unexpected metadata scope');
          const changed=index===2&&${switchAccount};
          ev.emit('contacts.upsert',[{id:changed?'442222@s.whatsapp.net':'441111@s.whatsapp.net',lid:changed?'888@lid':'777@lid',name:changed?'Different fixture':'Fixture parent'}]);
        }};
      setTimeout(async()=>{
        ev.emit('connection.update',{connection:'open'});
        ev.emit('messages.upsert',{messages:[message('a'),message('b')]});
        for(let receipt=0;receipt<1000;receipt++)ev.emit('messages.update',[{key:{remoteJid:'a',id:'same'},update:{status:4}}]);
        if(index===1){
          ev.emit('connection.update',{qr:'disposable fixture only'});
          ev.emit('messages.update',[{key:{remoteJid:'a',id:'same'},update:{messageTimestamp:200,message:{editedMessage:{message:{conversation:'Corrected'}}}}}]);
          ev.emit('messages.delete',{keys:[{remoteJid:'b',id:'same'}]});
          ev.emit('messaging-history.set',{messages:[message('a'),message('b')],chats:[],contacts:[]});
          previous=config;
          ev.emit('connection.update',{connection:'close',lastDisconnect:{error:{output:{statusCode:500}}}});
        }else{
          await config.auth.keys.set({'fixture-key':{current:'second socket'}});
          await previous.auth.keys.set({'fixture-key':{obsolete:'old socket'}});
          previous.auth.creds.me.id='obsolete identity';
          ev.emit('creds.update',{});
          setTimeout(()=>ev.emit('messages.upsert',{messages:[message('a'),message('b')]}),300);
        }
      },10);
      return socket;
    }
  `);
  writeFileSync(join(root,'qr.mjs'),"export default {toDataURL:async()=>{await new Promise(r=>setTimeout(r,2200));return 'obsolete fixture QR'}};");
  writeFileSync(join(root,'loader.mjs'),`export async function resolve(specifier,context,next){
    if(context.parentURL?.endsWith('/reader.mjs')){
      if(specifier==='@whiskeysockets/baileys')return {url:${JSON.stringify(pathToFileURL(join(root,'socket.mjs')).href)},shortCircuit:true};
      if(specifier==='qrcode')return {url:${JSON.stringify(pathToFileURL(join(root,'qr.mjs')).href)},shortCircuit:true};
    }return next(specifier,context);
  }`);
  writeFileSync(join(root,'register.mjs'),`import {register} from 'node:module';register(${JSON.stringify(pathToFileURL(join(root,'loader.mjs')).href)});`);
  const child=spawn(process.execPath,['--import',join(root,'register.mjs'),fileURLToPath(new URL('./reader.mjs',import.meta.url))],{stdio:['pipe','pipe','pipe']});
  let buffer='',stderr='',timer,snapshotRequested=false;
  try {
    const finished=new Promise((resolve,reject)=>{
      timer=setTimeout(()=>reject(Error('Offline reader fixture timed out')),6000);
      child.stderr.on('data',data=>{stderr+=data});
      child.stdout.on('data',data=>{
        buffer+=data;
        let newline;
        while((newline=buffer.indexOf('\n'))>=0){events.push(JSON.parse(buffer.slice(0,newline)));buffer=buffer.slice(newline+1);}
        if(events.filter(event=>event.connected).length>=2 && events.filter(event=>event.type==='messages').length>=7){
          if(!snapshotRequested){snapshotRequested=true;child.stdin.write(JSON.stringify({action:'snapshot',requestID:'fixture-heartbeat'})+'\n');}
          else if(events.some(event=>event.snapshotID==='fixture-heartbeat')) child.stdin.write(JSON.stringify({action:'stop'})+'\n');
        }
      });
      child.on('error',reject);
      child.on('exit',code=>code===0?resolve():reject(Error('Offline reader exited: '+code+' '+stderr)));
    });
    child.stdin.write(JSON.stringify({action:'start',directory:join(root,'storage'),key:key.toString('base64')})+'\n');
    await finished;
    const final=events.filter(event=>event.type==='messages').at(-1);
    assert.ok(events.filter(event=>event.type==='messages').length<10,'receipt-only updates never publish an unchanged complete cache');
    assert.deepEqual(final.messages.map(message=>[message.id,message.text]),switchAccount?[['a:same','Original'],['b:same','Original']]:[['a:same','Corrected']]);
    const snapshot=events.find(event=>event.snapshotID==='fixture-heartbeat');
    assert.deepEqual(snapshot.messages,final.messages);
    assert.ok(snapshot.coverage.includes('partial'));
    const journal=JSON.parse(open(readFileSync(join(root,'storage/revisions.enc')),key));
    if(switchAccount)assert.equal(Object.keys(journal.entries).length,0);
    assert.equal(events.some(event=>event.type==='qr'),false);
    const auth=JSON.parse(open(readFileSync(join(root,'storage/auth.enc')),key));
    assert.equal(auth.keys['fixture-key'].current,'second socket');
    assert.equal(auth.keys['fixture-key'].obsolete,undefined);
    assert.equal(auth.creds.me.id,switchAccount?'other-fixture:1@s.whatsapp.net':'fixture:1@s.whatsapp.net');
    assert.equal(events.some(event=>event.status?.includes('failed')),false);
    const directory=JSON.parse(open(readFileSync(join(root,'storage/names.enc')),key));
    assert.equal(directory.refreshed,true);
    assert.equal(directory.names[switchAccount?'442222@s.whatsapp.net':'441111@s.whatsapp.net'].name,switchAccount?'Different fixture':'Fixture parent');
    if(switchAccount)assert.equal(directory.names['441111@s.whatsapp.net'],undefined);
    assert.equal(events.some(event=>event.namesBusy===true),true);
    assert.equal(events.some(event=>event.namesBusy===false),true);
  } finally {
    clearTimeout(timer);child.kill();rmSync(root,{recursive:true,force:true});
  }

}
test('actual reader rejects old history, socket key writes and late QR output with an offline transport',()=>exerciseReader());
test('replacement linked identity clears old message cache and replay journal',()=>exerciseReader(true));
