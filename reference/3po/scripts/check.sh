#!/bin/zsh
# Source-free by default. --list explains the separate integration-only tiers.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import argparse
from datetime import datetime, timezone
import json
import hashlib
import plistlib
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import time

repository = Path.cwd()
manifest_path = repository / 'scripts/checks/check-suites.json'
manifest = json.loads(manifest_path.read_text())

class CandidateCheckError(RuntimeError):
    pass


def candidate_metadata(value, tool_runner=subprocess.run):
    binary = Path(value)
    if not binary.is_absolute():
        raise CandidateCheckError('--candidate-binary must be absolute')
    try:
        binary = binary.resolve(strict=True)
    except OSError as error:
        raise CandidateCheckError('candidate executable is unavailable') from error
    bundle = binary.parent.parent.parent
    if binary.name != '3PO' or binary.parent.name != 'MacOS' or binary.parent.parent.name != 'Contents' or bundle.name != '3PO.app' or not binary.is_file() or not os.access(binary, os.X_OK):
        raise CandidateCheckError('candidate must be the executable at 3PO.app/Contents/MacOS/3PO')
    result = tool_runner(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise CandidateCheckError('candidate signature verification failed')
    try:
        with (bundle / 'Contents/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise CandidateCheckError('candidate Info.plist is unreadable') from error
    if info.get('CFBundleIdentifier') != 'com.mylomichael.missioncontrol' or info.get('CFBundleExecutable') != binary.name:
        raise CandidateCheckError('candidate bundle identity/executable does not match 3PO')
    # The signed protocol declaration prevents probing older binaries that would
    # ignore the handshake argument and enter ordinary personal-data startup.
    if type(info.get('3POEvaluationProtocol')) is not int or info['3POEvaluationProtocol'] != 1:
        raise CandidateCheckError('candidate has no signed evaluation protocol declaration')
    with binary.open('rb') as stream:
        digest_builder = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1048576), b''):
            digest_builder.update(chunk)
        digest = digest_builder.hexdigest()
    return {'binary': str(binary), 'bundle': str(bundle), 'bundleID': info['CFBundleIdentifier'], 'protocol': 1, 'sha256': digest}


def validate_handshake(value, selected):
    if not isinstance(value, dict) or type(value.get('protocol')) is not int or value['protocol'] != 1:
        raise CandidateCheckError('evaluation handshake protocol is missing or incompatible')
    if value.get('debug') is not True:
        raise CandidateCheckError('candidate must be a DEBUG build for evaluation')
    if value.get('bundleID') != 'com.mylomichael.missioncontrol':
        raise CandidateCheckError('evaluation handshake bundle identity differs')
    modes = value.get('modes')
    if not isinstance(modes, list) or len(modes) > 100 or any(not isinstance(mode, list) or not mode or any(not isinstance(argument, str) for argument in mode) for mode in modes):
        raise CandidateCheckError('evaluation handshake modes are invalid')
    allowed = {tuple(mode) for mode in modes}
    for suite in selected:
        arguments = suite.get('arguments')
        if not isinstance(arguments, list) or tuple(arguments) not in allowed:
            raise CandidateCheckError('candidate does not support exact mode vector for ' + suite['id'])
        report_name = suite.get('report')
        if not isinstance(report_name, str) or Path(report_name).name != report_name or report_name in ('', '.', '..'):
            raise CandidateCheckError('manifest report filename is invalid for ' + suite['id'])
    return value


def validate_evaluation(value, tier):
    if not isinstance(value, dict):
        raise CandidateCheckError('evaluation report is not an object')
    for field in ('error', 'cleanupError'):
        if value.get(field) not in (None, '', False):
            raise CandidateCheckError('evaluation reports ' + field + ': ' + str(value[field]))
    total, passed = value.get('total'), value.get('passed')
    if type(total) is not int or total <= 0 or type(passed) is not int or passed != total:
        raise CandidateCheckError('evaluation must report a positive total with every check passed')
    checks = value.get('checks')
    if not isinstance(checks, (dict, list)) or len(checks) != total:
        raise CandidateCheckError('evaluation must include every counted check')
    if isinstance(checks, dict) and any(result is not True for result in checks.values()):
        raise CandidateCheckError('evaluation contains a non-passing check')
    if isinstance(checks, list) and any(not isinstance(result, dict) or result.get('passed') is not True for result in checks):
        raise CandidateCheckError('evaluation contains a non-passing check')
    if tier == 'app-memory':
        counters = [value[name] for name in ('requests', 'AIRequests') if name in value]
        if not counters or any(type(counter) is not int or counter != 0 for counter in counters):
            raise CandidateCheckError('app-memory evaluation must explicitly report zero inference requests')
    if tier == 'native' and 'cleanupError' not in value:
        raise CandidateCheckError('native evaluation does not report its cleanup outcome')
    return {'passed': passed, 'total': total, 'requests': {name: value[name] for name in ('requests', 'AIRequests') if name in value}}


def evaluation_handshake(candidate, selected, root, environment, seconds):
    stdout, stderr = root / 'handshake.json', root / 'handshake.stderr.log'
    with stdout.open('w') as output, stderr.open('w') as errors:
        process = subprocess.Popen([candidate['binary'], '--evaluation-handshake'], env=environment,
                                   stdout=output, stderr=errors, start_new_session=True)
        try:
            code = process.wait(timeout=min(seconds, 30))
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise CandidateCheckError('evaluation handshake timed out or was interrupted; no evaluation mode was launched')
    if code != 0:
        raise CandidateCheckError('evaluation handshake exited unsuccessfully')
    if stdout.stat().st_size > 65536:
        raise CandidateCheckError('evaluation handshake exceeds its byte limit')
    try:
        value = json.loads(stdout.read_text())
    except (OSError, ValueError) as error:
        raise CandidateCheckError('evaluation handshake did not produce valid JSON') from error
    return validate_handshake(value, selected)

parser = argparse.ArgumentParser(description='Run 3PO fictional regression checks in an isolated artifact directory.')
parser.add_argument('--tier', default='source-free', choices=list(manifest['tiers']))
parser.add_argument('--suite', action='append', default=[], help='Run only a named suite; repeat for several suites.')
parser.add_argument('--list', action='store_true', help='List suites and their effects without running or creating artifacts.')
parser.add_argument('--timeout', type=float, default=300, help='Maximum seconds per suite; default 300.')
parser.add_argument('--candidate-binary', help='Explicit signed DEBUG 3PO.app executable for app-memory/native/model tiers.')
parser.add_argument('--root', help='Parent artifact folder; defaults to MISSIONCONTROL_TEST_ROOT or /private/tmp.')
args = parser.parse_args()
if args.timeout <= 0:
    parser.error('--timeout must be positive')
all_suites = manifest['suites']
if len({suite['id'] for suite in all_suites}) != len(all_suites):
    parser.error('suite manifest has duplicate IDs')
if args.suite:
    wanted = set(args.suite)
    suites = [suite for suite in all_suites if suite['id'] in wanted]
    missing = wanted - {suite['id'] for suite in suites}
    if missing:
        parser.error('unknown suite(s): ' + ', '.join(sorted(missing)))
    wrong_tier = [suite['id'] for suite in suites if suite['tier'] != args.tier]
    if wrong_tier:
        parser.error('suite(s) outside selected tier: ' + ', '.join(wrong_tier))
else:
    suites = [suite for suite in all_suites if suite['tier'] == args.tier]
if args.list:
    tier = manifest['tiers'][args.tier]
    print(args.tier + ': ' + tier['description'])
    for suite in suites:
        command = suite.get('script') or '<signed DEBUG candidate> ' + ' '.join(suite.get('arguments', []))
        print(suite['id'] + ': ' + command + ' [' + ', '.join(suite['effects']) + ']')
    sys.exit(0)
candidate_tier = not manifest['tiers'][args.tier]['automatic']
if candidate_tier and not args.candidate_binary:
    parser.error('this integration-owner tier requires explicit --candidate-binary; inspect its effects with --list')
if not candidate_tier and args.candidate_binary:
    parser.error('--candidate-binary applies only to app-memory/native/model tiers')

# Newly added component scripts must be deliberately audited and listed, never silently omitted.
known_scripts = {suite['script'] for suite in all_suites if 'script' in suite}
component_scripts = {str(path.relative_to(repository)) for path in (repository / 'scripts/checks').glob('test*.sh')} | {'scripts/test.sh'}
unlisted = component_scripts - known_scripts
missing_scripts = known_scripts - component_scripts
if not candidate_tier and (unlisted or missing_scripts):
    parser.error('manifest/script inventory mismatch; unlisted=' + ','.join(sorted(unlisted)) + '; missing=' + ','.join(sorted(missing_scripts)))

parent = Path(args.root or os.environ.get('MISSIONCONTROL_TEST_ROOT', '/private/tmp')).expanduser()
parent.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='missioncontrol-check-', dir=parent)).resolve()
(root / 'logs').mkdir()
(root / 'suites').mkdir()
(root / 'modules').mkdir()
(root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

def git_output(arguments):
    return subprocess.check_output(['git', *arguments], cwd=repository, text=True).strip()

def now():
    return datetime.now(timezone.utc).isoformat()

report = {'schemaVersion': 1, 'tier': args.tier, 'repository': str(repository),
          'commit': git_output(['rev-parse', 'HEAD']), 'dirty': bool(git_output(['status', '--porcelain'])),
          'startedAt': now(), 'root': str(root), 'suites': [], 'completed': False,
          'counts': {'passed': 0, 'failed': 0, 'interrupted': 0, 'notRun': len(suites)}}

def save_report():
    # Persist progress after each suite; a terminated run remains resumable evidence.
    temporary = root / 'results.json.tmp'
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    temporary.replace(root / 'results.json')

save_report()
print('Artifacts: ' + str(root), flush=True)
candidate = None
if candidate_tier:
    report['preflight'] = {'status': 'running'}
    save_report()
    environment = os.environ.copy()
    environment['MISSIONCONTROL_TEST_ROOT'] = str(root)
    environment['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    (root / 'tmp').mkdir()
    environment['TMPDIR'] = str(root / 'tmp') + '/'
    try:
        candidate = candidate_metadata(args.candidate_binary)
        report['candidate'] = candidate
        handshake = evaluation_handshake(candidate, suites, root, environment, args.timeout)
        report['preflight'] = {'status': 'passed', 'handshake': handshake}
        save_report()
    except (CandidateCheckError, OSError, subprocess.SubprocessError) as error:
        report['preflight'] = {'status': 'failed', 'error': str(error)}
        report['finishedAt'] = now()
        save_report()
        print('Candidate preflight FAILED: ' + str(error), file=sys.stderr)
        print('Report: ' + str(root / 'results.json'), flush=True)
        sys.exit(1)
interrupted = False
for suite in suites:
    log = root / 'logs' / (suite['id'] + '.log')
    suite_root = root / 'suites' / suite['id']
    suite_root.mkdir()
    environment = os.environ.copy()
    environment['MISSIONCONTROL_TEST_ROOT'] = str(suite_root)
    environment['MISSIONCONTROL_TEST_MODULE_CACHE'] = str(root / 'modules')
    environment['DEVELOPER_DIR'] = '/Applications/Xcode.app/Contents/Developer'
    start = time.monotonic()
    command = [candidate['binary'], *suite['arguments']] if candidate_tier else [str(repository / suite['script'])]
    entry = {'id': suite['id'], 'command': command, 'startedAt': now(), 'log': str(log), 'artifacts': str(suite_root)}
    report['suites'].append(entry)
    report['counts']['notRun'] -= 1
    save_report()
    try:
        report_path = None
        if candidate_tier:
            fresh_candidate = candidate_metadata(candidate['binary'])
            if fresh_candidate['sha256'] != candidate['sha256']:
                raise CandidateCheckError('candidate executable changed after preflight')
            report_path = suite_root / suite['report']
            if report_path.exists():
                raise CandidateCheckError('evaluation report existed before this mode started')
            (suite_root / 'tmp').mkdir()
            environment['TMPDIR'] = str(suite_root / 'tmp') + '/'
        with log.open('w') as stream:
            process = subprocess.Popen(command, cwd=repository, env=environment,
                                       stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            entry['processID'] = process.pid
            save_report()
            try:
                code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
                entry['reason'] = 'suite timeout'
                if candidate_tier:
                    entry['cleanupVerified'] = False
                    entry['cleanupState'] = 'unverified after timeout; no automatic replay'
            except KeyboardInterrupt:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise
        entry['exitCode'] = code
        if candidate_tier and code == 0:
            if not report_path.is_file() or report_path.stat().st_size > 8388608:
                raise CandidateCheckError('fresh evaluation report is missing or exceeds its byte limit')
            try:
                value = json.loads(report_path.read_text())
            except (OSError, ValueError) as error:
                raise CandidateCheckError('evaluation did not produce a valid JSON report') from error
            entry['evaluation'] = validate_evaluation(value, args.tier)
            entry['report'] = str(report_path)
            if args.tier == 'native':
                entry['cleanupVerified'] = True
        entry['status'] = 'passed' if code == 0 else 'failed'
    except KeyboardInterrupt:
        entry['exitCode'] = 130
        entry['status'] = 'interrupted'
        if candidate_tier:
            entry['cleanupVerified'] = False
            entry['cleanupState'] = 'unverified after interruption; no automatic replay'
        interrupted = True
    except (CandidateCheckError, subprocess.SubprocessError) as error:
        entry['exitCode'] = 1
        entry['status'] = 'failed'
        entry['error'] = str(error)
        with log.open('a') as stream:
            stream.write('\nRunner validation failed: ' + str(error) + '\n')
    except OSError as error:
        entry['exitCode'] = 127
        entry['status'] = 'failed'
        entry['error'] = str(error)
        log.write_text(str(error) + '\n')
    entry['seconds'] = round(time.monotonic() - start, 3)
    entry['finishedAt'] = now()
    report['counts'][entry['status']] += 1
    save_report()
    print(entry['status'].upper() + ' ' + suite['id'] + ' (' + str(entry['seconds']) + 's)' +
          ('' if entry['status'] == 'passed' else ' — ' + str(log)), flush=True)
    if interrupted or (candidate_tier and entry.get('reason') == 'suite timeout'):
        break
report['completed'] = not interrupted and report['counts']['notRun'] == 0
report['finishedAt'] = now()
save_report()
counts = report['counts']
print(str(counts['passed']) + ' passed; ' + str(counts['failed']) + ' failed; ' + str(counts['interrupted']) + ' interrupted; ' + str(counts['notRun']) + ' not run.', flush=True)
print('Report: ' + str(root / 'results.json'), flush=True)
sys.exit(130 if interrupted else 1 if counts['failed'] else 0)
PY
