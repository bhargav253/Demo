# SPDX-License-Identifier: Apache-2.0
"""Portable JSON, Markdown, JUnit and self-contained HTML health reports."""
from collections import Counter
import html
import json
import uuid
from pathlib import Path
import xml.etree.ElementTree as ET


def save(path,data):
    path=Path(path)
    temp=path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
    temp.write_text(json.dumps(data,indent=2)+'\n')
    temp.replace(path)


def render(directory,data):
    counts=Counter(job['status'] for job in data['jobs'])
    data['counts']=dict(sorted(counts.items()))
    groups = {}
    for job in data['jobs']:
        if job['status'] not in ('PASS', 'QUEUED', 'RUNNING'):
            groups.setdefault(job.get('reason', job['status']), []).append(job['id'])
    data['failure_groups'] = groups
    save(directory/'run.json',data)
    title=f"{data['core']} — {data['suite']}: {data['status']}"
    lines=[f'# {title}', '',f"Revision: `{data['provenance']['revision']}`; dirty: {data['provenance']['dirty']}",
           '', ' | '.join(f'{k}: {v}' for k,v in sorted(counts.items())), '',
           '| Test | Mode / seed | Status | Cycles | Seconds | Log |',
           '|---|---|---|---:|---:|---|']
    build_rows=[]
    build_lines=['', '## Builds', '', '| Mode | Status | Cache | Evidence |', '|---|---|---|---|']
    for name,build in data.get('builds',{}).items():
        log=build.get('log','')
        cache=build.get('cache',{})
        cache_status=cache.get('status','—')
        build_lines.append(f"| {name} | {build['status']} | {cache_status} | [log]({log}) |")
        link=f'<a href="{html.escape(log,quote=True)}">log</a>' if log else '—'
        build_rows.append(f"<tr><td>{html.escape(name)}</td><td>{html.escape(build['status'])}</td><td title=\"{html.escape(cache.get('reason') or '',quote=True)}\">{html.escape(cache_status)}</td><td>{link}</td></tr>")
    lines[6:6]=build_lines+['', '## Tests', '']
    rows=[]
    xml=ET.Element('testsuite',name=data['core'],tests=str(len(data['jobs'])))
    for job in data['jobs']:
        log=job.get('log','')
        lines.append(f"| {job['test']} | {job['run_mode']} / {job['seed']} | {job['status']} | {job.get('cycles','—')} | {job.get('seconds','—')} | [log]({log}) |")
        rows.append('<tr>'+''.join('<td>'+html.escape(str(v))+'</td>' for v in
                    (job['test'],job['run_mode'],job['seed'],job['status'],job.get('cycles','—'),job.get('seconds','—')))+
                    f'<td><a href="{html.escape(log,quote=True)}">log</a></td></tr>')
        case=ET.SubElement(xml,'testcase',name=f"{job['test']}:{job['run_mode']}:{job['seed']}",time=str(job.get('seconds',0)))
        if job['status'] in ('NOT_RUN','QUEUED','CANCELLED'):
            ET.SubElement(case,'skipped',message=job['status'])
        elif job['status']!='PASS':
            ET.SubElement(case,'failure',message=job.get('reason',job['status'])).text=log
    coverage=data.get('coverage',{})
    lines += ['', '## Coverage', '', f"Status: {coverage.get('status','NOT_MEASURED')}"]
    for item in coverage.get('categories',[]):
        pct='N/A' if item['percent'] is None else f"{item['percent']:.2f}%"
        lines.append(f"- {item['name']}: {pct} ({item['covered']}/{item['total']})")
    if coverage.get('status')=='MEASURED':
        lines += ['', '[Uncovered points](coverage/summary.txt) · [Coverage data](coverage/summary.json)']
    lines += ['', '## Scope and gaps', '', *['- '+v for v in data['limitations']],
              '', '## Reproduce', '', '```sh', data['rerun_command'], '```',
              '', 'Per-job run.json contains exact replay commands and artifact hashes.']
    (directory/'summary.md').write_text('\n'.join(lines)+'\n')
    ET.SubElement(xml,'properties')
    xml.set('failures',str(sum(j['status'] not in ('PASS','NOT_RUN','QUEUED','CANCELLED') for j in data['jobs'])))
    xml.set('skipped',str(sum(j['status'] in ('NOT_RUN','QUEUED','CANCELLED') for j in data['jobs'])))
    if data['status']=='FAIL' and not any(j['status'] not in ('PASS','NOT_RUN','QUEUED','CANCELLED') for j in data['jobs']):
        case=ET.SubElement(xml,'testcase',name='campaign_integrity')
        ET.SubElement(case,'failure',message=data.get('error','Coverage or campaign integrity failure'))
        xml.set('tests',str(len(data['jobs'])+1));xml.set('failures','1')
    ET.ElementTree(xml).write(directory/'junit.xml',encoding='utf-8',xml_declaration=True)
    coverage_links='<p><a href="coverage/summary.txt">Uncovered points</a> · <a href="coverage/summary.json">Coverage data</a></p>' if coverage.get('status')=='MEASURED' else ''
    body=f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>{html.escape(title)}</title><style>
body{{font:16px system-ui;margin:2rem auto;padding:0 1rem;max-width:1200px;color:#e5eaf2;background:#101827}}
a{{color:#82bdff}}table{{width:100%;border-collapse:collapse}}th,td{{text-align:left;padding:.6rem;border-bottom:1px solid #344155}}
pre{{white-space:pre-wrap;background:#192638;padding:1rem}}input{{padding:.6rem;margin:1rem 0;width:20rem;max-width:90%}}
</style><h1>{html.escape(title)}</h1><p>{html.escape(str(data['counts']))}</p>
<p>Revision: {html.escape(data['provenance']['revision'])} · Dirty: {data['provenance']['dirty']}</p>
<p><a href="run.json">Manifest</a> · <a href="summary.md">Summary</a> · <a href="junit.xml">JUnit</a></p>
<h2>Builds</h2><table><thead><tr><th>Mode</th><th>Status</th><th>Cache</th><th>Evidence</th></tr></thead><tbody>{''.join(build_rows)}</tbody></table>
<h2>Tests</h2><label>Filter results <input id="filter" placeholder="Test, mode, or status"></label>
<table><thead><tr><th>Test</th><th>Mode</th><th>Seed</th><th>Status</th><th>Cycles</th><th>Seconds</th><th>Evidence</th></tr></thead><tbody id="results">{''.join(rows)}</tbody></table>
<h2>Coverage and scope</h2>{coverage_links}<pre>{html.escape(chr(10).join(lines[lines.index('## Coverage')+1:]))}</pre>
<script>document.querySelector('#filter').addEventListener('input', e => {{const q=e.target.value.toLowerCase();document.querySelectorAll('#results tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q));}});</script></html>'''
    (directory/'health.html').write_text(body)
