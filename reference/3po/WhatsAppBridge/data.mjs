import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
export function seal(text,key) {
  const iv=randomBytes(12), cipher=createCipheriv('aes-256-gcm',key,iv);
  const data=Buffer.concat([cipher.update(text),cipher.final()]);
  return Buffer.concat([iv,cipher.getAuthTag(),data]);
}
export function open(bytes,key) {
  const decipher=createDecipheriv('aes-256-gcm',key,bytes.subarray(0,12));
  decipher.setAuthTag(bytes.subarray(12,28));
  return Buffer.concat([decipher.update(bytes.subarray(28)),decipher.final()]).toString();
}
export function textMessage(m) {
  const chat=m.key?.remoteJid, id=m.key?.id;
  if(!id||!chat||chat==='status@broadcast') return;
  let content=m.message;
  for(let depth=0;depth<4;depth++) {
    const wrapped=content?.ephemeralMessage?.message || content?.viewOnceMessage?.message || content?.viewOnceMessageV2?.message || content?.viewOnceMessageV2Extension?.message || content?.documentWithCaptionMessage?.message || content?.editedMessage?.message;
    if(!wrapped) break; content=wrapped;
  }
  const body=content?.conversation ?? content?.extendedTextMessage?.text;
  const time=Number(m.messageTimestamp)*1000;
  if(typeof body!=='string'||!body||!Number.isFinite(time)) return;
  // Avoid an unpaired UTF-16 surrogate at the truncation boundary: Swift's JSON
  // decoder must receive valid text even for very long emoji messages.
  let text=body.slice(0,12000);
  if(/[\uD800-\uDBFF]$/.test(text))text=text.slice(0,-1);
  return {id:chat+':'+id,chat,sender:m.pushName||m.key.participant||chat,text,sentByMe:!!m.key.fromMe,time};
}
export function boundedMessages(messages) {
  const result=[];let bytes=2;
  for(const entry of Object.entries(messages).sort((a,b)=>b[1].time-a[1].time || (a[0]<b[0]?-1:a[0]>b[0]?1:0)).slice(0,2000)){
    const size=Buffer.byteLength(JSON.stringify(entry))+1;
    if(bytes+size>12_000_000)break;
    result.push(entry);bytes+=size;
  }
  return Object.fromEntries(result);
}
export function applyMessageUpdates(messages,updates) {
  const result={...messages};
  for(const {key,update} of updates??[]) {
    if(!key?.remoteJid||!key?.id||!update)continue;
    const id=key.remoteJid+':'+key.id,old=result[id];
    if(update.message===null){delete result[id];continue;}
    if(!old||!update.message)continue; // Status-only events never change received content.
    const value=textMessage({key:{...key,fromMe:old.sentByMe},message:update.message,messageTimestamp:old.time/1000,pushName:old.sender});
    if(value)result[id]=value;
    else delete result[id]; // An edited non-text payload must not leave stale text visible.
  }
  return boundedMessages(result);
}
export function applyMessageDeletes(messages,{keys,jid,all}={}) {
  const result={...messages};
  if(all&&jid)for(const [id,message] of Object.entries(result))if(message.chat===jid)delete result[id];
  for(const key of keys??[])if(key?.remoteJid&&key?.id)delete result[key.remoteJid+':'+key.id];
  return result;
}
