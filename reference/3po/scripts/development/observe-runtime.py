#!/usr/bin/env python3
"""Read-only installed acceptance snapshots. Output contains metadata, never prose.

Integration owner only: explicit store/app/since/output paths, no inference,
source helpers, native operations, settings changes or application launch.
Snapshots do not themselves establish the full reliability acceptance criteria.
"""
import argparse
from collections import Counter
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess


def identity(value):
    return hashlib.sha256(str(value).encode()).hexdigest()[:24]


def timestamp(value):
    if isinstance(value, (int, float)):
        return datetime(2001, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=value)
    if isinstance(value, str):
        return datetime.fromisoformat(value.replace('Z', '+00:00'))
    return None


def date(value):
    parsed = timestamp(value)
    return parsed.isoformat() if parsed else None


def brief_metadata(value):
    return {
        'id': identity(value['id']), 'owner': identity(value.get('registration')),
        'day': value.get('day'), 'created': date(value.get('created')),
        'morningID': identity(value['morningID']) if value.get('morningID') else None,
        'heartbeatID': identity(value['heartbeatID']) if value.get('heartbeatID') else None,
        'widgetOnly': value.get('widgetOnly'), 'invalidated': value.get('invalidated'),
        'recordSHA256': hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                                  allow_nan=False).encode()).hexdigest(),
    }


def snapshot(store, app, since):
    connection = sqlite3.connect(store.as_uri() + '?mode=ro', uri=True, timeout=5)
    try:
        rows = connection.execute('SELECT ZKEY,ZDATA FROM ZCACHEDDASHBOARD').fetchall()
    finally:
        connection.close()
    records = {}
    for key, value in rows:
        if key in records:
            raise ValueError('Duplicate cache key; observation is unavailable')
        records[key] = value
    def read(key, default):
        # Missing and unreadable are deliberately different.
        return json.loads(records[key]) if key in records else default

    accounts = []
    for owner, value in read('paHeartbeat', {}).get('accounts', {}).items():
        runs = []
        for run in value.get('reviews', []):
            began = timestamp(run.get('started'))
            if began is None or began < since:
                continue
            runs.append({
                'id': identity(run['id']), 'started': date(run.get('started')),
                'finished': date(run.get('finished')), 'phase': run.get('phase'),
                'calls': run.get('calls'), 'manual': run.get('manual'),
                'briefUpdated': run.get('briefUpdated'), 'hasFailure': bool(run.get('failure')),
                'checkedAccounts': run.get('checkedAccounts'), 'waitingAccounts': run.get('waitingAccounts'),
                'mailCollectionIndependent': run.get('mailCollectionIndependent'),
                'steps': [{'id': s.get('id'), 'status': s.get('status')} for s in run.get('steps', [])],
            })
        accounts.append({
            'owner': identity(owner), 'phase': value.get('phase'), 'budgetDay': value.get('budgetDay'),
            'calls': value.get('calls'), 'checked': date(value.get('checked')),
            'assessed': date(value.get('assessed')), 'pending': value.get('pending'),
            'retryAfter': date(value.get('retryAfter')), 'retryReason': value.get('retryReason'),
            'mailLanes': [{'account': identity(k), 'checked': date(v.get('checked')),
                           'assessed': date(v.get('assessed')), 'pending': v.get('pending'),
                           'hasIssue': bool(v.get('issue'))} for k, v in value.get('mailLanes', {}).items()],
            'runs': runs,
        })
    brief = read('dailyBriefings', {})
    morning = [{'id': identity(v['id']), 'owner': identity(v.get('registration')), 'day': v.get('day')}
               for v in brief.get('records', []) if timestamp(v.get('created')) is not None and timestamp(v['created']) >= since]
    drafts = read('assistantDrafts', {})
    memory = read('paMemory', {})
    result = {
        'schemaVersion': 2,
        'snapshotUTC': datetime.now(timezone.utc).isoformat(), 'sinceUTC': since.isoformat(),
        'applicationSHA256': hashlib.sha256((app / 'Contents/MacOS/3PO').read_bytes()).hexdigest(),
        'recordCount': len(records), 'heartbeat': accounts, 'morningRecords': morning,
        # Include pre-install delivery identities so subsequent widget updates
        # can be compared with the original morning record without exporting prose.
        'morningHistory': [brief_metadata(v) for v in brief.get('records', [])],
        'widgetBriefs': {identity(k): brief_metadata(v) for k, v in brief.get('updatedBriefs', {}).items()},
        'notificationClaims': sorted(identity(v) for v in brief.get('notificationClaims', [])),
        'savedDraftCount': len(drafts.get('values', {})),
        'memoryRecordCount': len(memory.get('records', [])),
        'queueStates': dict(Counter(v.get('state', 'unknown') for v in read('paRequestQueue', []))),
        'learningClaims': [{'owner': identity(k), 'day': v.get('day'), 'attempts': v.get('attempts'),
                            'lastAttempt': date(v.get('lastAttempt')), 'servedLanes': sorted(v.get('lastServed', {})),
                            'laneClaims': {lane: date(claim) for lane, claim in sorted(v.get('lastServed', {}).items())}}
                           for k, v in read('paCombinedLearningBudget', {}).items()],
        'sourceHealth': {k: {'stored': k in records, 'lastSuccess': date(read(k, {}).get('lastSuccess')),
                             'hasError': bool(read(k, {}).get('error')), 'loading': read(k, {}).get('loading', False)}
                         for k in ['calendarHealth', 'reminderHealth', 'mailHealth', 'paOrientationHealth']},
    }
    try:
        listing = subprocess.run(['/bin/ps', '-axo', 'command='], check=True, capture_output=True, text=True, timeout=10)
        result['installedProcessCount'] = sum(line.strip().startswith(str(app / 'Contents/MacOS/3PO')) for line in listing.stdout.splitlines())
    except (OSError, subprocess.SubprocessError):
        result['installedProcessCount'] = None
    try:
        power = subprocess.run(['/usr/bin/pmset', '-g', 'log'], check=True, capture_output=True, text=True, timeout=20)
        events = []
        for line in power.stdout.splitlines():
            match = re.match(r'^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4})\s+(Sleep|Wake|DarkWake)\s', line)
            if not match:
                continue
            when = datetime.strptime(match[1], '%Y-%m-%d %H:%M:%S %z')
            if when >= since:
                events.append({'date': when.isoformat(), 'kind': match[2],
                               'lidRelated': bool(re.search(r'Clamshell|LidOpen|Lid Open', line, re.I))})
        result['powerEvents'] = events[-1000:]
        result['powerEventsTruncated'] = len(events) > 1000
        result['powerObservationAvailable'] = True
    except (OSError, ValueError, subprocess.SubprocessError):
        result['powerObservationAvailable'] = False
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--store', type=Path, required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--since', required=True, help='Installed acceptance start, ISO8601 with UTC offset')
    parser.add_argument('--output', type=Path, required=True, help='Private JSON output outside any Git checkout')
    args = parser.parse_args()
    since = timestamp(args.since)
    if since is None or since.tzinfo is None:
        parser.error('--since must include an explicit UTC offset')
    output = args.output.expanduser().resolve()
    for directory in [output.parent, *output.parent.parents]:
        if (directory / '.git').exists():
            parser.error('Private runtime observations cannot be written inside a Git checkout')
    if output.exists():
        parser.error('Observation exists; use a fresh filename rather than overwrite evidence')
    result = snapshot(args.store.expanduser().resolve(), args.app.expanduser().resolve(), since)
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with output.open('x') as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
    output.chmod(0o600)
    print(json.dumps({'output': str(output), 'postInstallRuns': sum(len(v['runs']) for v in result['heartbeat']),
                      'installedProcessCount': result['installedProcessCount'], 'powerObservationAvailable': result['powerObservationAvailable']}))


if __name__ == '__main__':
    main()
