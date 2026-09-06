#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate a pinned ACT4 collection externally, then explicitly publish verified ELFs."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'tools/env'))
from riscv_testgen import environment, check, LOCK
DEFAULT_SUITE=REPO/'verification/riscv_arch/suite.json'


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def local_path(text):
    path=(REPO/text).resolve()
    if not path.is_relative_to(REPO): raise ValueError('Source path escapes repository')
    return path


def generate(args):
    workspace=args.workspace.resolve()
    if workspace.is_relative_to(REPO): raise ValueError('Generation workspace must be outside checkout')
    versions=check(workspace)
    suite_path=args.suite.resolve()
    suite=json.loads(suite_path.read_text())
    config=local_path(suite['config'])
    runs=workspace/'runs';runs.mkdir(exist_ok=True)
    run=Path(tempfile.mkdtemp(prefix=suite['name']+'-',dir=runs))
    snapshot=run/'config'
    shutil.copytree(config.parent,snapshot)
    inputs={str(p.relative_to(REPO)):sha(p) for p in config.parent.iterdir() if p.is_file()}
    for p in config.parent.iterdir():
        if p.is_file() and sha(snapshot/p.name)!=inputs[str(p.relative_to(REPO))]:
            raise ValueError('Configuration changed while snapshotting')
    upstream=workspace/'riscv-arch-test'
    command=['uv','run','--frozen','--no-dev','--project',str(upstream),'--python',sys.executable,
             'act',str(snapshot/config.name),'--workdir',str(run/'work'),
             '--test-dir',str(upstream/'tests'),'--coverpoint-dir',str(upstream/'coverpoints'),
             '--extensions',','.join(suite['extensions']),'--jobs',str(args.jobs)]
    print('Generation log:',run/'generate.log',flush=True)
    with (run/'generate.log').open('w') as log:
        status=subprocess.run(command,cwd=workspace,env=environment(workspace),
                              stdout=log,stderr=subprocess.STDOUT).returncode
    if status: raise RuntimeError(f'ACT4 failed ({status}); see {run / "generate.log"}')
    files=sorted((run/'work').glob('*/elfs/**/*.elf'))
    if len(files)!=len(suite['tests']) or {p.name for p in files}!=set(suite['tests']):
        raise RuntimeError('Generated inventory differs from the reviewed suite; nothing published')
    for source,digest in inputs.items():
        if sha(local_path(source))!=digest: raise RuntimeError('Platform inputs changed during generation')
    receipt={'schema_version':1,'status':'PASS','suite':suite,'suite_sha256':sha(suite_path),
             'dependency_lock_sha256':sha(LOCK),'versions':versions,
             'suite_revision':json.loads(LOCK.read_text())['riscv_arch_test']['revision'],
             'config_sha256':inputs,'command':command,
             'generator_sha256':sha(Path(__file__)),
             'tests':[{'file':str(p.relative_to(run)),'name':p.name,'sha256':sha(p)} for p in files]}
    (run/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print('Generation complete; source/prebuilt files unchanged. Receipt:',run/'receipt.json')


def publish(args):
    receipt_path=args.receipt.resolve()
    receipt=json.loads(receipt_path.read_text())
    suite_path=args.suite.resolve()
    suite=json.loads(suite_path.read_text())
    if receipt['status']!='PASS' or receipt['suite_sha256']!=sha(suite_path):
        raise ValueError('Receipt does not match current successful suite generation')
    if receipt['dependency_lock_sha256']!=sha(LOCK): raise ValueError('Dependency lock changed')
    if receipt['generator_sha256']!=sha(Path(__file__)): raise ValueError('Generation recipe changed')
    for source,digest in receipt['config_sha256'].items():
        if sha(local_path(source))!=digest: raise ValueError(f'Platform input changed: {source}')
    if len(receipt['tests'])!=len(suite['tests']) or {t['name'] for t in receipt['tests']}!=set(suite['tests']):
        raise ValueError('Receipt test inventory mismatch')
    for t in receipt['tests']:
        p=(receipt_path.parent/t['file']).resolve()
        if not p.is_relative_to(receipt_path.parent) or sha(p)!=t['sha256']:
            raise ValueError(f'Generated ELF changed: {t["name"]}')
    dest=local_path(suite['destination']);dest.parent.mkdir(parents=True,exist_ok=True)
    config=local_path(suite['config']).parent
    manifest={'suite':'riscv-arch-test ACT4','suite_revision':receipt['suite_revision'],
              'scope':suite['description'],'versions':receipt['versions'],
              'config_directory':os.path.relpath(config,dest),
              'config_sha256':{Path(p).name:v for p,v in receipt['config_sha256'].items()},
              'dependency_lock_sha256':receipt['dependency_lock_sha256'],
              'generation_command':'python3 tools/verification/riscv_arch.py generate --workspace <external-workspace>',
              'generation_receipt_sha256':sha(receipt_path),
              'tests':[{'file':t['name'],'sha256':t['sha256']} for t in receipt['tests']]}
    # Stage every source before replacing any published file; manifest is written last.
    with tempfile.TemporaryDirectory(prefix='.publish-',dir=dest.parent) as temp:
        stage=Path(temp)
        for t in receipt['tests']: shutil.copy2(receipt_path.parent/t['file'],stage/t['name'])
        (stage/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        dest.mkdir(exist_ok=True)
        for t in receipt['tests']: os.replace(stage/t['name'],dest/t['name'])
        os.replace(stage/'manifest.json',dest/'manifest.json')
    print(f'Published {len(receipt["tests"])} ELFs to {dest}')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='operation',required=True)
    gen=sub.add_parser('generate');gen.add_argument('--workspace',required=True,type=Path)
    gen.add_argument('--jobs',type=int,default=4)
    pub=sub.add_parser('publish');pub.add_argument('--receipt',required=True,type=Path)
    for p in (gen,pub):p.add_argument('--suite',type=Path,default=DEFAULT_SUITE)
    args=parser.parse_args()
    if args.operation=='generate':
        if args.jobs<1:parser.error('jobs must be positive')
        generate(args)
    else:publish(args)


if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,KeyError,OSError,subprocess.CalledProcessError) as e:
        raise SystemExit(str(e)) from e
