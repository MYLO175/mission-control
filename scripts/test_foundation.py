#!/usr/bin/env python3
"""Compile and run offline tests with disposable paths; never sign in or read native sources."""
import os, platform, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    if platform.system()!='Darwin': raise SystemExit('Swift foundation checks require macOS and Xcode')
    base=ROOT/'foundation'; provider=base/'Sources/Provider'; core=base/'Sources/Core'
    env=os.environ.copy();env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
    with tempfile.TemporaryDirectory(prefix='mission-control-check-',dir='/private/tmp') as name:
        tmp=Path(name)
        identity=tmp/'AppIdentity.swift'
        identity.write_text('import Foundation\nenum AppIdentity { static let name="Fixture"; static let bundleID="io.missioncontrol.fixture"; static let keychainService="io.missioncontrol.fixture.never-opened"; static let dataDirectory=URL(fileURLWithPath:'+repr(str(tmp/'must-not-be-created')).replace("'",'"')+') }\n')
        sets=[('auth',[provider/'ChatGPTOAuth.swift',base/'Tests/ChatGPTAuthChecks.swift']),
              ('stream',[core/'AIUsage.swift',provider/'ChatGPTStream.swift',provider/'ChatGPTRecovery.swift',base/'Tests/ChatGPTStreamChecks.swift']),
              ('workspace',[*sorted(core.glob('*.swift')),*sorted(provider.glob('*.swift')),identity,base/'Tests/WorkspaceChecks.swift'])]
        for label,files in sets:
            binary=tmp/label
            subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-module-cache-path',str(tmp/'module-cache'),*map(str,files),'-o',str(binary)],check=True,env=env)
            subprocess.run([str(binary)],check=True,env=env)
        print('All three offline foundation suites passed.')
if __name__=='__main__':main()
