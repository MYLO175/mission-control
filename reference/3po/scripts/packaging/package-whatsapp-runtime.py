#!/usr/bin/env python3
"""Package a pinned official Node runtime, without modifying the system installation."""
from pathlib import Path
import hashlib, platform, subprocess, tarfile
root=Path(__file__).resolve().parents[2]
version='22.23.3'
checksums={'arm64':'23b25245dcfb9af7262f8ff142e9e2e0af025368117329e7a7458a51e5922f53','x64':'8a677b0219178efd6eb0e475457c4afb452b521a92f6e67845a73bd85727f2a8'}
arch='arm64' if platform.machine()=='arm64' else 'x64'
name=f'node-v{version}-darwin-{arch}'
cache=Path('/tmp/missioncontrol-node-runtime');cache.mkdir(exist_ok=True)
archive=cache/(name+'.tar.gz')
if not archive.exists():
    subprocess.run(['curl','--fail','--silent','--show-error','--location','--max-time','60',f'https://nodejs.org/dist/v{version}/{name}.tar.gz','-o',str(archive)],check=True)
if hashlib.sha256(archive.read_bytes()).hexdigest()!=checksums[arch]:
    raise SystemExit('Node runtime checksum mismatch; remove the cached archive and retry.')
out=root/'WhatsAppBridge'/'Runtime';out.mkdir(exist_ok=True)
with tarfile.open(archive) as tar:
    for source,dest in [('bin/node','node'),('LICENSE','LICENSE')]:
        data=tar.extractfile(name+'/'+source).read()
        (out/dest).write_bytes(data)
(out/'node').chmod(0o755)
(out/'VERSION').write_text(f'{version} darwin-{arch}\nOfficial Node.js runtime; see LICENSE.\n')
identity='Apple Development'
# Native addon dependencies share our signing team; no library-validation exception.
for path in sorted((root/'WhatsAppBridge'/'node_modules').rglob('*')):
    if path.suffix in ('.node','.dylib') and 'darwin' in str(path):
        subprocess.run(['codesign','--force','--sign',identity,str(path)],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['codesign','--force','--options','runtime','--entitlements',str(root/'scripts'/'packaging'/'node-runtime.entitlements'),'--sign',identity,str(out/'node')],check=True)
subprocess.run([str(out/'node'),'--version'],check=True)
