import { textMessage, boundedMessages } from './data.mjs';

const keyID = key => typeof key?.remoteJid === 'string' && typeof key?.id === 'string' && key.remoteJid && key.id ? key.remoteJid + ':' + key.id : null;
const timestamp = (value, fallback) => Number.isFinite(Number(value)) && Number(value) > 0 ? Number(value) * 1000 : fallback;

// Persist separately before messages.enc. Reapplying this journal on load makes a
// crash between the two atomic saves safe against stale text/history replay.
export class ReceivedTextCache {
  constructor(messages = {}, journal = {}) {
    this.messages = { ...messages };
    this.entries = { ...journal.entries };
    this.deletedChats = { ...journal.deletedChats };
    this.reconcile();
  }
  apply(value) {
    const revision = this.entries[value.id];
    if (revision?.kind === 'delete' || value.time <= (this.deletedChats[value.chat] ?? -Infinity)) return null;
    return revision?.kind === 'edit' ? { ...value, text: revision.text } : value;
  }
  reconcile() {
    this.messages = boundedMessages(Object.fromEntries(Object.values(this.messages).map(value => this.apply(value)).filter(Boolean).map(value => [value.id, value])));
  }
  ingest(messages = []) {
    for (const message of messages) {
      const value = textMessage(message);
      if (!value) continue;
      const current = this.apply(value);
      if (current) this.messages[value.id] = current;
      else delete this.messages[value.id];
    }
    this.reconcile();
  }
  update(updates = [], now = Date.now()) {
    let changed=false;
    for (const { key, update } of updates) {
      const id = keyID(key);
      if (!id || !update || !Object.hasOwn(update, 'message')) continue;
      const previous = this.entries[id];
      // Revocation is final for this exact message identity, including when the
      // original has not arrived yet. Status/receipt-only updates are ignored.
      if (update.message === null) {
        if(previous?.kind==='delete')continue;
        this.entries[id] = { kind: 'delete', updatedAt: now };
        delete this.messages[id];
        changed=true;
        continue;
      }
      if (!update.message || previous?.kind === 'delete') continue;
      const updatedAt = timestamp(update.messageTimestamp, now);
      if (previous && updatedAt < previous.updatedAt) continue;
      const original = this.messages[id];
      const value = textMessage({ key, message: update.message, messageTimestamp: original ? original.time / 1000 : updatedAt / 1000 });
      const entry=value ? { kind: 'edit', text: value.text, updatedAt } : { kind: 'delete', updatedAt };
      if(previous?.kind===entry.kind&&previous?.text===entry.text&&previous?.updatedAt===entry.updatedAt)continue;
      this.entries[id] = entry;changed=true;
      if (original) {
        const revised = this.apply(original);
        if (revised) this.messages[id] = revised;
        else delete this.messages[id];
      }
    }
    if(changed)this.reconcile();
    return changed;
  }
  delete({ keys, jid, all } = {}, now = Date.now()) {
    if (all && typeof jid === 'string') {
      this.deletedChats[jid] = Math.max(now, this.deletedChats[jid] ?? 0);
      for (const message of Object.values(this.messages)) if (message.chat === jid) {
        this.entries[message.id] = { kind: 'delete', updatedAt: now };
        delete this.messages[message.id];
      }
    }
    for (const key of keys ?? []) {
      const id = keyID(key);
      if (id) { this.entries[id] = { kind: 'delete', updatedAt: now }; delete this.messages[id]; }
    }
    this.reconcile();
  }
  journal() {
    // Retain revisions for every cached message, then the newest additional
    // tombstones/pending edits. This is bounded reconciliation, not full history.
    const entries = Object.entries(this.entries).sort((a,b) => Number(Object.hasOwn(this.messages,b[0])) - Number(Object.hasOwn(this.messages,a[0])) || b[1].updatedAt - a[1].updatedAt).slice(0,4000);
    let bytes=2;const retained=[];
    for(const entry of entries){const size=Buffer.byteLength(JSON.stringify(entry))+1;if(bytes+size>16_000_000)break;retained.push(entry);bytes+=size;}
    this.entries = Object.fromEntries(retained);
    this.deletedChats = Object.fromEntries(Object.entries(this.deletedChats).sort((a,b) => b[1]-a[1]).slice(0,256));
    return { entries: this.entries, deletedChats: this.deletedChats };
  }
}

export async function deliverIfCurrent(isCurrent, prepare, deliver) {
  if (!isCurrent()) return;
  try {
    const value = await prepare();
    if (isCurrent()) deliver(value);
  } catch (error) {
    if (isCurrent()) throw error;
  }
}
