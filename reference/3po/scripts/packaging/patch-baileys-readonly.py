#!/usr/bin/env python3
"""Remove rc14's automatic availability publication from our pinned local copy."""
from pathlib import Path
import hashlib, json

root = Path(__file__).resolve().parents[2] / 'WhatsAppBridge' / 'node_modules' / '@whiskeysockets' / 'baileys'
original = '1e70aea7b1164d92757a63ee7f375cf537c7c9126478c6e7bbf1daf930abb691'
patched = '78059958eef094b94c3f7eb572fcc2e1abcd1623e5e9a44b8ab6529e963b5fc9'
path = root / 'lib' / 'Socket' / 'chats.js'
if json.loads((root / 'package.json').read_text())['version'] != '7.0.0-rc14':
    raise SystemExit('Unreviewed Baileys version; read-only patch needs review.')
data = path.read_bytes()
digest = hashlib.sha256(data).hexdigest()
if digest == patched:
    raise SystemExit(0)
if digest != original:
    raise SystemExit('Unexpected Baileys source; refusing an unverified read-only build.')
needle = "            sendPresenceUpdate(markOnlineOnConnect ? 'available' : 'unavailable').catch(error => onUnexpectedError(error, 'presence update requests'));"
text = data.decode().replace(needle, '            // Mission Control read-only build: never publish availability on connection.')
result = text.encode()
if hashlib.sha256(result).hexdigest() != patched:
    raise SystemExit('Read-only patch did not match the expected result.')
path.write_bytes(result)
