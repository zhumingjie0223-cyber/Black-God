#!/usr/bin/env python3
"""Check installed runtime versions against Alpine secdb using apk's comparator.
This checks published fixed versions, not unknown vulnerabilities or exploitability.
"""
import argparse, datetime, hashlib, json, shlex, shutil, subprocess, tempfile, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def installed(image):
    records=[]
    for record in (image/'data/lib/apk/db/installed').read_text().split('\n\n'):
        fields=dict(line.split(':',1) for line in record.splitlines() if ':' in line)
        if 'P' in fields: records.append({key:fields[key] for key in ['P','V','o','c','L']})
    if not records: raise ValueError('No installed package records')
    return records

def check(image, database, ish):
    packages=installed(image)
    fixes={item['pkg']['name']:item['pkg']['secfixes'] for item in database['packages']}
    checks=[]
    for p in packages:
        for version, advisories in fixes.get(p['o'],{}).items():
            if version != '0': checks.append((p,version,advisories))
    script='\n'.join('apk version -t '+shlex.quote(p['V'])+' '+shlex.quote(v) for p,v,_ in checks)
    with tempfile.TemporaryDirectory(prefix='blackgod-security-') as temp:
        clone=Path(temp)/'image'; shutil.copytree(image,clone)
        result=subprocess.run([str(ish),'-f',str(clone),'/bin/sh','-c','set -e\n'+script],capture_output=True,text=True,check=True,timeout=90)
    comparisons=result.stdout.splitlines()
    if len(comparisons)!=len(checks) or any(x not in ['<','=','>'] for x in comparisons):raise ValueError('Incomplete apk version comparison')
    outdated=[{'package':p['P'],'installed':p['V'],'fixed':v,'advisories':a} for (p,v,a),order in zip(checks,comparisons) if order=='<']
    return {'packages':packages,'comparisons':len(checks),'outdated':outdated}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--image',type=Path,default=ROOT/'ios-app/Runtime/AlpineRootfs')
    parser.add_argument('--database',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    branch=json.loads((args.image/'image-info.json').read_text())['branch']
    url='https://secdb.alpinelinux.org/'+branch+'/main.json'
    raw=args.database.read_bytes() if args.database else urllib.request.urlopen(url,timeout=60).read()
    database=json.loads(raw)
    if database['distroversion']!=branch:raise ValueError('Wrong security database branch')
    report=check(args.image,database,ROOT/'.runtime-build/host/ish')
    report.update(databaseURL=url,databaseSHA256=hashlib.sha256(raw).hexdigest(),checkedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(f"Checked {len(report['packages'])} packages / {report['comparisons']} published fix comparisons; outdated entries: {len(report['outdated'])}")
    if report['outdated']:raise SystemExit(1)
if __name__=='__main__':main()
