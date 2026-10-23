#!/usr/bin/env python3
"""Capture only the authored fictional illustrations with an isolated Playwright CLI session."""
import argparse, json, os, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli',type=Path,required=True,help='Path to playwright-cli or its wrapper')
    parser.add_argument('--base-url',default='http://127.0.0.1:8765')
    parser.add_argument('--session',default='mission-control-guide')
    args=parser.parse_args()
    def call(*parts):
        result=subprocess.run([str(args.cli),'--session',args.session,*parts],cwd=ROOT,text=True,capture_output=True)
        if result.returncode or '### Error' in result.stdout: raise SystemExit(result.stdout+result.stderr)
        return result.stdout
    call('resize','1160','720')
    for feature in json.loads((ROOT/'catalog.json').read_text())['features']:
        call('goto',args.base_url.rstrip('/')+'/docs/preview-source.html?feature='+feature['id'])
        call('screenshot','--filename',str(ROOT/feature['image']))
        print('Captured '+feature['id'],flush=True)
if __name__=='__main__': main()
