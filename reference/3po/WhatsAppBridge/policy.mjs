import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';

export function assertReadOnlyDependency() {
  const root=dirname(createRequire(import.meta.url).resolve('@whiskeysockets/baileys/package.json'));
  const version=JSON.parse(readFileSync(join(root,'package.json'))).version;
  const digest=createHash('sha256').update(readFileSync(join(root,'lib/Socket/chats.js'))).digest('hex');
  if(version!=='7.0.0-rc14'||digest!=='78059958eef094b94c3f7eb572fcc2e1abcd1623e5e9a44b8ab6529e963b5fc9')throw Error('Unverified read-only dependency');
}
