import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { assertReadOnlyDependency } from './policy.mjs';

test('pinned dependency passes read-only integrity check and its actual open hook publishes no presence',()=>{
  assertReadOnlyDependency();
  const root=dirname(createRequire(import.meta.url).resolve('@whiskeysockets/baileys/package.json'));
  const source=readFileSync(join(root,'lib/Socket/chats.js'),'utf8');
  const start=source.indexOf("    ev.on('connection.update',");
  const end=source.indexOf("    ev.on('creds.update',",start);
  assert.ok(start>=0 && end>start);
  const hook=source.slice(start,end);
  for(const markOnline of [false,true]){
    let listener;const publications=[];
    // Execute the actual installed dependency hook, with no transport. An open
    // event without pending notifications returns before history-sync work.
    new Function('ev','fireInitQueries','sendPresenceUpdate','markOnlineOnConnect',hook)(
      {on:(name,callback)=>{assert.equal(name,'connection.update');listener=callback}},false,
      (...args)=>{publications.push(args);return Promise.resolve()},markOnline
    );
    listener({connection:'open'});assert.deepEqual(publications,[]);
  }
});
