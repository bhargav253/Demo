#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Provision/check optional ACT4 tools in an explicit external workspace (Linux x86-64)."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LOCK = REPO / 'third_party/sources.lock.json'


def environment(workspace: Path) -> dict[str, str]:
    workspace = workspace.resolve()
    lock = json.loads(LOCK.read_text())
    env = os.environ.copy()
    for name, rel in {
        'MISE_DATA_DIR': 'local/mise-data', 'MISE_CACHE_DIR': 'local/mise-cache',
        'MISE_CONFIG_DIR': 'local/mise-config', 'UV_CACHE_DIR': 'local/uv-cache',
        'UV_PYTHON_INSTALL_DIR': 'local/python', 'BUNDLE_PATH': 'local/gems',
        'BUNDLE_USER_HOME': 'local/bundle', 'XDG_DATA_HOME': 'local/share',
        'XDG_CACHE_HOME': 'local/cache', 'XDG_CONFIG_HOME': 'local/config',
    }.items():
        env[name] = str(workspace / rel)
    env['MISE_RUBY_COMPILE'] = 'false'
    env['PATH'] = os.pathsep.join([str(workspace/'local')] + [
        str(workspace / tool['bin']) for tool in lock['tools'].values() if 'bin' in tool
    ] + [env.get('PATH', '')])
    return env


def check(workspace: Path) -> dict[str, str]:
    env = environment(workspace)
    lock = json.loads(LOCK.read_text())
    commands = {'gcc': ['riscv-none-elf-gcc', '--version'],
                'sail': ['sail_riscv_sim', '--version'], 'ruby': ['ruby', '--version'],
                'uv': ['uv', '--version'], 'bundler': ['bundle', '--version']}
    versions = {}
    for name, command in commands.items():
        executable = shutil.which(command[0], path=env['PATH'])
        if not executable or not Path(executable).resolve().is_relative_to(workspace.resolve()):
            raise RuntimeError(f'Missing workspace-local {name}; run this setup script')
        value = subprocess.check_output(command, env=env, text=True).strip()
        expected = lock['tools'][name]['version']
        if name == 'gcc': expected = expected.split('-')[0]
        if expected not in value:
            raise RuntimeError(f'{name} version mismatch: expected {expected}, got {value}')
        versions[name] = value
    suite = workspace/'riscv-arch-test'
    revision = subprocess.check_output(['git', '-C', str(suite), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != lock['riscv_arch_test']['revision']:
        raise RuntimeError('ACT4 source revision differs from the dependency lock')
    if subprocess.check_output(['git','-C',str(suite),'status','--porcelain'],text=True).strip():
        raise RuntimeError('ACT4 checkout has local changes; use a clean pinned checkout')
    return versions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--check', action='store_true', help='Read-only dependency/version checks')
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    if workspace == REPO or workspace.is_relative_to(REPO):
        parser.error('Choose a generation workspace outside the source checkout')
    if args.check:
        print(json.dumps(check(workspace), indent=2)); return
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        parser.error('Pinned binary setup currently supports Linux x86-64 only')
    workspace.mkdir(parents=True, exist_ok=True)
    lock = json.loads(LOCK.read_text())
    env = environment(workspace)
    def run(cmd):
        print('+', ' '.join(map(str,cmd)), flush=True)
        subprocess.run(cmd, cwd=workspace, env=env, check=True)
    for name in ['gcc','sail','mise']:
        tool = lock['tools'][name]
        archive = workspace/'downloads'/tool['archive']
        archive.parent.mkdir(exist_ok=True)
        if not archive.exists():
            temporary = archive.with_suffix(archive.suffix+'.download')
            urllib.request.urlretrieve(tool['url'], temporary)
            temporary.replace(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != tool['sha256']:
            raise RuntimeError(f'Download checksum mismatch: {archive}')
        if name == 'mise':
            dest=workspace/'local/mise';dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(archive,dest);dest.chmod(0o755)
        elif not (workspace/tool['bin']).exists():
            dest=workspace/'local'/name;dest.mkdir(parents=True,exist_ok=True)
            with tarfile.open(archive) as tar: tar.extractall(dest,filter='data')
    run([str(workspace/'local/mise'),'install',
         'ruby@'+lock['tools']['ruby']['version'], 'uv@'+lock['tools']['uv']['version']])
    rubybin=workspace/lock['tools']['ruby']['bin']
    run([str(rubybin/'ruby'),str(rubybin/'gem'),'install','bundler','--version',
         lock['tools']['bundler']['version'],'--no-document'])
    suite=workspace/'riscv-arch-test'
    if not suite.exists():
        run(['git','clone',lock['riscv_arch_test']['url'],str(suite)])
        run(['git','-C',str(suite),'checkout','--detach',lock['riscv_arch_test']['revision']])
    check(workspace)  # Never silently reset a user's existing checkout.
    run(['uv','sync','--frozen','--no-dev','--project',str(suite),'--python',sys.executable])
    env['BUNDLE_GEMFILE']=str(suite/'framework/src/act/data/Gemfile')
    run(['bundle','install'])
    print('Generation environment ready. Normal firmware regression needs none of these tools.')


if __name__ == '__main__':
    try: main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
