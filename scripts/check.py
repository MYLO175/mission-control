#!/usr/bin/env python3
"""Validate authored guidance, assets, reference integrity and independent-app generation."""
import hashlib, importlib.util, json, re, struct, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def require(condition,message):
    if not condition:raise AssertionError(message)
def main():
    catalogue=json.loads((ROOT/'catalog.json').read_text());features=catalogue['features']
    ids=[f['id'] for f in features]
    require(len(ids)==len(set(ids)),'Feature IDs must be unique')
    for f in features:
        require(re.fullmatch(r'[a-z][a-z0-9-]*',f['id']),'Invalid feature ID')
        require(f['requires']==['foundation'],'Unexpected required feature: '+f['id'])
        for path in [f['recipe'],f['image'],*['reference/3po/'+p for p in f['sourceFiles']]]:
            require((ROOT/path).is_file(),'Missing catalogue target: '+path)
    for path in (ROOT/'docs/assets').rglob('*.png'):
        data=path.read_bytes();require(data[:8]==b'\x89PNG\r\n\x1a\n','Invalid PNG: '+str(path))
        width,height=struct.unpack('>II',data[16:24]);require(width>=800 and height>=400,'Preview too small')
    manifest=json.loads((ROOT/'reference/manifest.json').read_text())
    require(re.fullmatch(r'[a-f0-9]{40}',manifest['sourceCommit']),'Invalid source commit')
    for name,digest in manifest['files'].items():
        path=ROOT/'reference/3po'/name
        require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==digest,'Reference drift: '+name)
    actual={str(p.relative_to(ROOT/'reference/3po')) for p in (ROOT/'reference/3po').rglob('*') if p.is_file()}
    require(actual==set(manifest['files']),'Unexpected or missing reference files')
    forbidden={'AGENTS.md','PLAN.md','STATUS.md','VALIDATION.md'}
    require(not forbidden.intersection(manifest['files']),'Personal coordination files must stay outside the snapshot')
    links=0
    for doc in ROOT.rglob('*.md'):
        relative=doc.relative_to(ROOT)
        if any(part in {'.git','.build','output','.playwright-cli'} for part in relative.parts) or relative.parts[:2]==('reference','3po'):continue
        for target in re.findall(r'!?\[[^\]]*\]\(([^)\n]+)\)',doc.read_text()):
            if re.match(r'[a-zA-Z][a-zA-Z0-9+.-]*:',target) or target.startswith('#'):continue
            target=target.split('#',1)[0]
            if target:
                require((doc.parent/target).exists(),f'Broken link in {relative}: {target}');links+=1
    template=(ROOT/'docs/chooser.template.html').read_text()
    expected=template.replace('__CATALOGUE_JSON__',json.dumps(catalogue,ensure_ascii=False).replace('</','<\\/'))
    require((ROOT/'docs/chooser.html').read_text()==expected,'Regenerate the chooser with build_catalogue.py')
    spec=importlib.util.spec_from_file_location('create_app',ROOT/'scripts/create_app.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='mission-control-generator-') as directory:
        a=module.create('Example',Path(directory)/'one');b=module.create('Example',Path(directory)/'two')
        first=json.loads((a/'app.json').read_text());second=json.loads((b/'app.json').read_text())
        require(first['bundleID']!=second['bundleID'],'Generated identities must be independent')
        require(not (a/'reference').exists() and not (a/'Sources/Sources').exists(),'Generator copied integrations/reference')
        try:module.create('Example',a);raise AssertionError('Generator overwrote an existing app')
        except FileExistsError:pass
        unicode_app=module.create('Atlas – café',Path(directory)/'unicode')
        require(json.loads((unicode_app/'app.json').read_text())['name']=='Atlas – café','Unicode name was changed')
        try:module.create('Nested',ROOT/'foundation'/'nested-fixture');raise AssertionError('Recursive destination accepted')
        except ValueError:pass
        try:module.create('../invalid',Path(directory)/'invalid');raise AssertionError('Invalid name accepted')
        except ValueError:pass
    print(f'PASS: {len(features)} features, {len(manifest["files"])} exact reference files, {links} local authored-document links, PNG assets, catalogue consistency and generator acceptance.')
if __name__=='__main__':main()
