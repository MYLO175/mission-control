// Names are display metadata only. Aliases never merge message IDs or PA permissions.
const direct = value => typeof value === 'string' && /^\d+(?::\d+)?@(lid|s\.whatsapp\.net)$/.test(value) ? value.replace(/:\d+@/, '@') : null;
const clean = value => typeof value === 'string' ? Array.from(value.trim()).slice(0,120).join('') : '';
export class ChatNames {
  constructor(saved = {}, legacy = {}) {
    this.names = { ...saved.names }; this.aliases = { ...saved.aliases };this.refreshed=saved.refreshed === true;
    for (const [id,name] of Object.entries(legacy)) this.put(id,name,2);
  }
  put(id,name,rank) {
    const label=clean(name);if(typeof id !== 'string'||!label||id==='status@broadcast')return;
    if(!this.names[id] || rank >= this.names[id].rank)this.names[id]={name:label,rank};
  }
  mapping(lid,pn) {
    lid=direct(lid);pn=direct(pn);
    if(!lid?.endsWith('@lid')||!pn?.endsWith('@s.whatsapp.net'))return;
    // Retire superseded one-to-one mappings, rather than giving an old address a new person's name.
    for(const id of [lid,pn]) { const old=this.aliases[id];if(old&&this.aliases[old]===id)delete this.aliases[old]; }
    this.aliases[lid]=pn;this.aliases[pn]=lid;
  }
  keys(values={}) {
    for(const [pn,lid] of Object.entries(values))if(/^\d+$/.test(pn)&&typeof lid==='string'&&/^\d+$/.test(lid))this.mapping(lid+'@lid',pn+'@s.whatsapp.net');
  }
  contacts(values=[]) {
    for(const contact of values) {
      const id=direct(contact.id);if(!id)continue;
      this.mapping(contact.lid || (id.endsWith('@lid')?id:null),contact.phoneNumber || (id.endsWith('@s.whatsapp.net')?id:null));
      this.put(id,contact.name,4);this.put(id,contact.notify || contact.verifiedName,1);
    }
  }
  messages(values=[]) {
    for(const message of values) {
      const id=direct(message.key?.remoteJid),alt=direct(message.key?.remoteJidAlt);
      if(!id)continue;
      if(alt)this.mapping(id.endsWith('@lid')?id:alt,id.endsWith('@s.whatsapp.net')?id:alt);
      if(!message.key.fromMe)this.put(id,message.pushName,1);
    }
  }
  label(id) {
    const normalized=direct(id)||id;
    const own=this.names[normalized],other=this.names[this.aliases[normalized]];
    return (other && (!own || other.rank>own.rank) ? other : own)?.name;
  }
  list(chats={},messages={}) {
    const actual=new Set([...Object.keys(chats),...Object.values(messages).map(m=>m.chat)]);
    const ids=new Set(actual);
    for(const id of Object.keys(this.names)) {
      const alias=this.aliases[id];
      // Offer named contacts too, but don't invent a duplicate address when a known chat exists.
      if(!actual.has(id)&&!actual.has(alias)&&(!alias||!ids.has(alias)))ids.add(id);
    }
    return [...ids].filter(id=>id!=='status@broadcast').slice(0,5000).map(id=>({id,
      name:this.label(id)||clean(chats[id])||Object.values(messages).find(m=>m.chat===id&&!m.sentByMe&&m.sender!==id&&!id.endsWith('@g.us'))?.sender||(id.endsWith('@g.us')?'Group · '+id.split('@')[0].slice(-6):id.split('@')[0]),group:id.endsWith('@g.us')}));
  }
  snapshot() {
    this.names=Object.fromEntries(Object.entries(this.names).slice(-5000));
    this.aliases=Object.fromEntries(Object.entries(this.aliases).slice(-10000));
    return {names:this.names,aliases:this.aliases,refreshed:this.refreshed};
  }
}
