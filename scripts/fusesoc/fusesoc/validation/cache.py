# SPDX-License-Identifier: Apache-2.0
"""Versioned local simulator cache with immutable entries and per-key locks."""
from contextlib import contextmanager
import copy
import fcntl
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time
import uuid

from .model import identity, sha
from .report import save

VERSION = 1


def canonical_inputs(edam, work, root, provenance):
    """Hash prepared sources and compile configuration, excluding runtime plusargs."""
    configuration = copy.deepcopy(edam)
    configuration['parameters'] = {k: v for k, v in configuration.get('parameters', {}).items()
                                   if v.get('paramtype') != 'plusarg'}
    def normalize(value):
        if isinstance(value, dict):
            return {k: normalize(v) for k, v in value.items()}
        if isinstance(value, list):
            return [normalize(v) for v in value]
        if isinstance(value, str):
            return value.replace(str(work), '${WORK}').replace(str(root), '${REPO}')
        return value
    sources = {}
    for item in edam.get('files', []):
        path = work/item['name']
        if not path.is_file():
            raise ValueError(f'Missing build input: {path}')
        sources[normalize(item['name'])] = sha(path)
        # Include-directory contents can change include search resolution even
        # when the newly added file was not in a previous compiler depfile.
        if item.get('include_path'):
            directory = work/item['include_path']
            for included in sorted(directory.rglob('*')):
                if included.is_file():
                    sources[normalize(str(included))] = sha(included)
    exported = work/'src'
    if exported.exists():
        for path in sorted(exported.rglob('*')):
            if path.is_file():
                sources[path.relative_to(work).as_posix()] = sha(path)
    return {'cache_version': VERSION, 'edam': normalize(configuration), 'sources': sources,
            'tool_versions': provenance['tool_versions'],
            'repository_tools': provenance['repository_tools_sha256'],
            'toolchain': provenance['cache_toolchain'],
            'environment_sha256': provenance['cache_environment_sha256'],
            'host': {'system': platform.system(), 'machine': platform.machine(),
                     'libc': platform.libc_ver(), 'release': platform.release()}}


def toolchain_identity(resolved):
    """Include compiler executables, installed toolchain versions, and Verilator runtime."""
    result = {'executables': {name: {'path': path, 'sha256': sha(path)}
                             for name, path in resolved.items() if path}}
    for name in ('cc1plus', 'collect2', 'as', 'ld'):
        output = subprocess.check_output(['g++', '-print-prog-name='+name], text=True, timeout=15).strip()
        path = Path(shutil.which(output) or output).resolve()
        if path.is_file():
            result['executables'][name] = {'path': str(path), 'sha256': sha(path)}
    version = subprocess.check_output(['verilator', '-V'], text=True, timeout=15)
    match = re.search(r'^\s*VERILATOR_ROOT\s*=\s*(.+)$', version, re.M)
    verilator_root = Path(os.environ.get('VERILATOR_ROOT') or (match.group(1).strip() if match else '/usr/share/verilator'))
    result['verilator_runtime'] = {str(p): sha(p) for area in ('include', 'bin')
                                  for p in sorted((verilator_root/area).rglob('*')) if p.is_file()}
    # System C/C++ headers/libraries are provided by the local package set.
    # User-supplied include/library search roots are hashed separately below.
    if shutil.which('dpkg-query'):
        packages = subprocess.check_output(['dpkg-query', '-W', '-f=${Package}=${Version}\n'], text=True, timeout=15)
        result['system_packages_sha256'] = identity(packages)
    else:
        result['system_packages_sha256'] = None
    probe = subprocess.run(['g++', '-E', '-x', 'c++', '-', '-v'], input='', text=True,
                           capture_output=True, check=True, timeout=15)
    search = probe.stderr.split('#include <...> search starts here:')[-1].split('End of search list.')[0]
    headers = {}
    roots = sorted({str(Path(line.strip()).resolve()) for line in search.splitlines() if line.strip() and Path(line.strip()).is_dir()})
    for directory in roots:
        for path in sorted(Path(directory).rglob('*')):
            if path.is_file():
                headers[str(path.resolve())] = sha(path)
    result['system_header_roots'] = roots
    result['system_headers_sha256'] = identity(headers)
    libraries = {}
    for name in ('libstdc++.so', 'libstdc++.a', 'libgcc.a', 'libgcc_s.so.1', 'libc.so', 'libc.so.6',
                 'libm.so', 'libm.so.6', 'libz.so', 'libz.so.1', 'libpthread.a', 'libpthread.so.0',
                 'librt.a', 'librt.so.1', 'libatomic.so', 'crtbegin.o', 'crtend.o', 'Scrt1.o', 'crti.o', 'crtn.o'):
        path = Path(subprocess.check_output(['g++', '-print-file-name='+name], text=True, timeout=15).strip())
        if path.is_file():
            libraries[str(path.resolve())] = sha(path)
    result['system_link_inputs'] = libraries
    extra = {}
    for key in ('CPATH', 'CPLUS_INCLUDE_PATH', 'C_INCLUDE_PATH', 'LIBRARY_PATH', 'COMPILER_PATH', 'LD_LIBRARY_PATH'):
        for directory in os.environ.get(key, '').split(os.pathsep):
            if directory:
                for path in sorted(Path(directory).rglob('*')):
                    if path.is_file():
                        extra[str(path.resolve())] = sha(path)
    result['environment_search_files'] = extra
    return result


def eligibility(edam):
    """Only the qualified standalone Verilator adapter is cached in version 1."""
    tool = edam.get('flow_options', {}).get('tool')
    if tool != 'verilator' and 'verilator' not in edam.get('tool_options', {}):
        return 'Only standalone Verilator simulation builds are cacheable'
    if edam.get('hooks') or edam.get('vpi'):
        return 'Build hooks/VPI require a separate cache adapter'
    # Options can name undeclared files or external libraries. Those builds
    # remain correct by compiling fresh until their file inputs are declared.
    options = json.dumps([edam.get('flow_options', {}), edam.get('tool_options', {})])
    if re.search(r'-I|-L|-CFLAGS|-LDFLAGS|--exe|--lib|--Mdir|--relative-includes|\"-l|\"@', options):
        return 'External compiler/include/library options require uncached execution'
    return None


class Cache:
    def __init__(self, root):
        self.root = Path(root)/'build/cache/validation'/f'v{VERSION}'
        for name in ('entries', 'locks', 'access'):
            (self.root/name).mkdir(parents=True, exist_ok=True)

    def entry(self, key):
        if not re.fullmatch('[0-9a-f]{64}', key):
            raise ValueError('Cache key must be a full SHA-256 digest')
        return self.root/'entries'/key

    @contextmanager
    def lock(self, key, cancel, timeout=600, blocking=True):
        self.entry(key)
        with (self.root/'locks'/key).open('a') as stream:
            start = time.monotonic()
            while True:
                if cancel.is_set():
                    raise InterruptedError('Cache wait cancelled')
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if not blocking:
                        yield False
                        return
                    if time.monotonic()-start >= timeout:
                        raise TimeoutError('Timed out waiting for simulator cache lock')
                    cancel.wait(.05)
            try:
                yield True
            finally:
                fcntl.flock(stream, fcntl.LOCK_UN)

    def check(self, key):
        entry = self.entry(key)
        if not entry.exists():
            return None, 'No completed entry for these build inputs'
        try:
            record = json.loads((entry/'complete.json').read_text())
            if record['version'] != VERSION or identity(record['inputs']) != key:
                raise ValueError('Identity/version mismatch')
            for name in ('simulator', 'build.log'):
                path = entry/name
                if path.is_symlink() or sha(path) != record['hashes'][name]:
                    raise ValueError(f'Integrity mismatch: {name}')
            return record, 'Verified matching build inputs and retained files'
        except (OSError, ValueError, KeyError) as exc:
            return None, f'Invalid entry: {exc}'

    def restore(self, key, destination):
        # Caller holds the key lock through copy so pruning cannot race it.
        record, reason = self.check(key)
        if record:
            for name in ('simulator', 'build.log'):
                shutil.copyfile(self.entry(key)/name, destination/name)
                if sha(destination/name) != record['hashes'][name]:
                    raise ValueError('Cache content changed during restore')
            (destination/'simulator').chmod(0o555)
            (self.root/'access'/key).touch()
        return record, reason

    def remove(self, key):
        entry = self.entry(key)
        if entry.exists():
            trash = self.root/'entries'/('.trash-'+key+'-'+uuid.uuid4().hex)
            entry.rename(trash)
            for directory in [trash, *[p for p in trash.rglob('*') if p.is_dir()]]:
                directory.chmod(0o755)
            shutil.rmtree(trash)
        (self.root/'access'/key).unlink(missing_ok=True)

    def publish(self, key, inputs, executable, log, origin):
        if identity(inputs) != key:
            raise ValueError('Cache publication key mismatch')
        temporary = self.root/'entries'/('.tmp-'+key+'-'+uuid.uuid4().hex)
        temporary.mkdir()
        try:
            shutil.copyfile(executable, temporary/'simulator')
            shutil.copyfile(log, temporary/'build.log')
            record = {'version': VERSION, 'inputs': inputs, 'origin': origin,
                      'created_at': time.time(),
                      'hashes': {name: sha(temporary/name) for name in ('simulator', 'build.log')}}
            # Completion marker is last; no partially written entry is visible.
            save(temporary/'complete.json', record)
            for path in temporary.iterdir():
                path.chmod(0o555 if path.name == 'simulator' else 0o444)
            temporary.chmod(0o555)
            if self.entry(key).exists():
                self.remove(key)
            temporary.rename(self.entry(key))
            (self.root/'access'/key).touch()
        finally:
            if temporary.exists():
                temporary.chmod(0o755)
                shutil.rmtree(temporary)

    def listing(self):
        result = []
        for entry in sorted((self.root/'entries').iterdir()):
            if not re.fullmatch('[0-9a-f]{64}', entry.name):
                continue
            record, reason = self.check(entry.name)
            access = self.root/'access'/entry.name
            result.append({'key': entry.name, 'valid': record is not None, 'reason': reason,
                           'bytes': sum(p.stat().st_size for p in entry.rglob('*') if p.is_file()),
                           'last_used': (access if access.exists() else entry).stat().st_mtime})
        return result

    def orphans(self):
        result = []
        for path in (self.root/'entries').iterdir():
            match = re.fullmatch(r'\.(?:tmp|trash)-([0-9a-f]{64})-[0-9a-f]+', path.name)
            if match and path.is_dir():
                result.append({'name': path.name, 'key': match.group(1),
                               'bytes': sum(p.stat().st_size for p in path.rglob('*') if p.is_file())})
        return result

    def prune(self, max_bytes, cancel, dry_run=False):
        items = sorted(self.listing(), key=lambda x: (x['last_used'], x['key']))
        total = sum(x['bytes'] for x in items)
        removed, busy = [], []
        orphan_removed = []
        for orphan in self.orphans():
            with self.lock(orphan['key'], cancel, blocking=False) as acquired:
                if not acquired:
                    busy.append(orphan['name'])
                    continue
                if not dry_run:
                    path = self.root/'entries'/orphan['name']
                    path.chmod(0o755)
                    shutil.rmtree(path)
                orphan_removed.append(orphan['name'])
        for item in items:
            if total <= max_bytes:
                break
            with self.lock(item['key'], cancel, blocking=False) as acquired:
                if not acquired:
                    busy.append(item['key'])
                    continue
                if not dry_run:
                    self.remove(item['key'])
                total -= item['bytes']
                removed.append(item['key'])
        return {'removed' if not dry_run else 'would_remove': removed, 'busy': busy, 'remaining_bytes': total, 'orphan_directories': orphan_removed}


def command(fs, args):
    import threading
    cache = Cache(Path(fs.config._path).resolve().parent)
    try:
        if args.cache_action == 'list':
            result = {'entries': cache.listing(), 'incomplete': cache.orphans()}
        elif args.cache_action == 'show':
            result, reason = cache.check(args.key)
            if not result:
                raise ValueError(reason)
        elif args.cache_action == 'diff':
            left, left_reason = cache.check(args.left)
            right, right_reason = cache.check(args.right)
            if not left or not right:
                raise ValueError(left_reason if not left else right_reason)
            result = {key: {'left': left['inputs'].get(key), 'right': right['inputs'].get(key)}
                      for key in sorted(set(left['inputs']) | set(right['inputs']))
                      if left['inputs'].get(key) != right['inputs'].get(key)}
        else:
            if args.max_mib < 0:
                raise ValueError('--max-mib cannot be negative')
            result = cache.prune(args.max_mib*1024**2, threading.Event(), args.dry_run)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError) as exc:
        print(f'Cache error: {exc}')
        raise SystemExit(2)


def register(subparsers):
    parser = subparsers.add_parser('cache', help='Inspect or prune the local compiled-simulator cache')
    commands = parser.add_subparsers(dest='cache_action', required=True)
    commands.add_parser('list').set_defaults(func=command)
    show = commands.add_parser('show'); show.add_argument('key'); show.set_defaults(func=command)
    diff = commands.add_parser('diff'); diff.add_argument('left'); diff.add_argument('right'); diff.set_defaults(func=command)
    prune = commands.add_parser('prune'); prune.add_argument('--max-mib', type=int, required=True)
    prune.add_argument('--dry-run', action='store_true'); prune.set_defaults(func=command)
