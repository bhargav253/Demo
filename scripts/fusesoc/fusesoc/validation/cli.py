# SPDX-License-Identifier: Apache-2.0
"""One FuseSoC command family for named tests, regressions and coverage."""
import json
from pathlib import Path
import subprocess
import signal
import threading
import uuid
from .engine import campaign, execute_job
from .model import sha, inside, identity, tree_identity
from .report import save


def invoke(fs,args):
    def interrupt(*_):
        raise KeyboardInterrupt
    previous={s:signal.signal(s,interrupt) for s in (signal.SIGINT,signal.SIGTERM)}
    try:
        if args.jobs is not None and args.jobs<1: raise ValueError('--jobs must be positive')
        if args.timeout is not None and args.timeout<1: raise ValueError('--timeout must be positive')
        if args.seed is not None and not 0<=args.seed<=4294967295: raise ValueError('Seed out of range')
        raise SystemExit(campaign(fs,args))
    except KeyboardInterrupt:
        print('Validation cancelled during startup')
        raise SystemExit(130)
    except (ValueError,RuntimeError,OSError) as exc:
        print(f'Validation error: {exc}')
        raise SystemExit(2)
    finally:
        for sig,handler in previous.items():signal.signal(sig,handler)


def replay(fs,args):
    try:
        source=Path(args.manifest).resolve()
        old=json.loads(source.read_text())
        executable=Path(old['executable'])
        if sha(executable)!=old['executable_sha256']: raise ValueError('Replay executable hash mismatch')
        root=Path(fs.config._path).resolve().parent
        job=dict(old)
        if old.get('elf_snapshot'):
            elf=Path(old['elf_snapshot'])
            if sha(elf)!=old['elf_sha256']: raise ValueError('Replay ELF hash mismatch')
            # execute_job verifies and snapshots its input again.
            if not elf.is_relative_to(root): raise ValueError('Replay must use artifacts in this checkout')
            job['elf']=str(elf)
            job['input_hashes']={str(elf.relative_to(root)):old['elf_sha256']}
        destination=root/'artifacts'/old['core'].replace(':','_')/'replay'/uuid.uuid4().hex[:12]
        cancel=threading.Event()
        previous={sig:signal.signal(sig,lambda *_:cancel.set()) for sig in (signal.SIGINT,signal.SIGTERM)}
        try:
            result=execute_job(job,old['build'],executable,destination,old['policy'],cancel,root,old['core'],old['config_sha256'])
        finally:
            for sig,handler in previous.items():signal.signal(sig,handler)
        result['replay_of']=str(source)
        result['original_build_identity']=old.get('build_identity',old.get('original_build_identity'))
        save(destination/'run.json',result)
        print(f"Replay: {result['status']}\nManifest: {destination/'run.json'}")
        raise SystemExit(0 if result['status']=='PASS' else 1)
    except (ValueError,KeyError,OSError) as exc:
        print(f'Replay error: {exc}');raise SystemExit(2)


def status(fs,args):
    try:
        root=Path(fs.config._path).resolve().parent
        core=fs.get_core(args.core)
        latest=root/'artifacts'/str(core.name).replace(':','_')/'validation/latest.json'
        pointer=json.loads(latest.read_text())
        manifest=inside(root,pointer['manifest'])
        data=json.loads(manifest.read_text())
        revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
        diff=subprocess.check_output(['git','diff','HEAD','--binary'],cwd=root,text=True).strip()
        tree_status=subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
        stale=(revision!=data['provenance']['revision'] or identity(diff)!=data['provenance']['diff_sha256']
               or tree_status!=data['provenance']['git_status'])
        stale=stale or tree_identity(root)!=data['provenance'].get('source_tree_sha256')
        cfg=core.get_validation()
        stale=stale or identity(cfg)!=data['config_sha256']
        print(f"Latest suite: {data['suite']}\nResult: {data['status']}\nCounts: {data['counts']}\n"
              f"Recorded: {data['finished_at']}\nRevision/tree changed: {stale}\n"
              f"Health: {manifest.parent/'health.html'}\nRerun: {data['rerun_command']}")
        if data['provenance']['dirty']:
            print('Recorded from a dirty tree; freshness also checks the full source-content fingerprint.')
        raise SystemExit(0 if data['status']=='PASS' and not stale else 1)
    except (OSError,ValueError,KeyError) as exc:
        print(f'No usable health record: {exc}');raise SystemExit(2)


def register(subparsers):
    from .impact import register as register_impact
    register_impact(subparsers)
    from .cache import register as register_cache
    register_cache(subparsers)
    for action in ('test','regress','coverage'):
        parser=subparsers.add_parser(action,help=f'Axon validation {action}')
        parser.add_argument('core')
        parser.add_argument('--suite',default='health')
        parser.add_argument('--test',required=action=='test')
        parser.add_argument('--seed',type=int)
        parser.add_argument('--run-mode')
        parser.add_argument('--jobs',type=int)
        parser.add_argument('--timeout',type=int)
        parser.add_argument('--list',action='store_true')
        parser.add_argument('--dry-run',action='store_true')
        parser.add_argument('--no-cache',action='store_true',help='Compile a fresh simulator without reading or publishing the cache')
        parser.set_defaults(func=invoke,action=action)
    parser=subparsers.add_parser('status',help='Show latest recorded core health and revision freshness')
    parser.add_argument('core')
    parser.set_defaults(func=status)
    parser=subparsers.add_parser('replay',help='Replay a recorded simulation using verified executable/ELF snapshots')
    parser.add_argument('manifest')
    parser.set_defaults(func=replay)
