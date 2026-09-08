import concurrent.futures,hashlib,json,re,urllib.request
from pathlib import Path
import argparse
parser=argparse.ArgumentParser(description="Collect exact source inputs for the installed Alpine image")
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--image',type=Path,default=Path(__file__).resolve().parents[2]/'ios-app/Runtime/AlpineRootfs')
args=parser.parse_args()
ROOT=args.output
PACKAGES=[]
for record in (args.image/'data/lib/apk/db/installed').read_text().split('\n\n'):
 fields=dict(line.split(':',1) for line in record.splitlines() if ':' in line)
 if 'P' in fields:PACKAGES.append({key:fields[key] for key in ['P','V','L','o','c']})
if not PACKAGES:raise ValueError('Missing installed packages')
ROOT.mkdir(parents=True,exist_ok=True)
def fetch(url):
 req=urllib.request.Request(url,headers={'User-Agent':'BlackGod-source-release/1.2.0'})
 with urllib.request.urlopen(req,timeout=60) as r: return r.read()
def origin(item):
 name,commit=item
 dest=ROOT/'recipes'/name;dest.mkdir(parents=True,exist_ok=True)
 def folder(path,local):
  listing=json.loads(fetch(f'https://api.github.com/repos/alpinelinux/aports/contents/{path}?ref={commit}'))
  for f in listing:
   if f['type']=='file':
    local.mkdir(parents=True,exist_ok=True);(local/f['name']).write_bytes(fetch(f['download_url']))
   elif f['type']=='dir':folder(f['path'],local/f['name'])
   else:raise ValueError('Unsupported recipe object '+f['type'])
 
 if not (dest/'.complete').exists():
  folder('main/'+name,dest)
  (dest/'.complete').write_text(commit)
 recipe=(dest/'APKBUILD').read_text()
 checks=re.findall(r'^([0-9a-f]{128})\s+([^\s]+)\s*$',recipe,re.M)
 if not checks and not (name == 'alpine-base' and 'source=' not in recipe): raise ValueError('No SHA512 source manifest: '+name)
 files=[]
 for checksum,filename in checks:
  if Path(filename).name!=filename:raise ValueError('Unexpected source filename')
  local=dest/filename;url=None
  if not local.exists():
   local=ROOT/'distfiles'/filename;local.parent.mkdir(exist_ok=True)
   url='https://distfiles.alpinelinux.org/distfiles/v3.22/'+filename
   if not local.exists():local.write_bytes(fetch(url))
  if hashlib.sha512(local.read_bytes()).hexdigest()!=checksum:raise ValueError('Checksum mismatch '+str(local))
  files.append({'file':str(local.relative_to(ROOT)),'sha512':checksum,'url':url})
 print(name+': '+str(len(files))+' checksums verified',flush=True)
 return {'origin':name,'aports_commit':commit,'sources':files}
origins=sorted(set((x['o'],x['c']) for x in PACKAGES))
results=[];errors=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 futures={pool.submit(origin,x):x for x in origins}
 for f in concurrent.futures.as_completed(futures):
  try:results.append(f.result())
  except Exception as e:errors.append({'origin':futures[f][0],'error':str(e)});print(errors[-1],flush=True)
(ROOT/'manifest.json').write_text(json.dumps({'packages':PACKAGES,'origins':sorted(results,key=lambda x:x['origin']),'errors':errors},indent=2))
if errors:raise SystemExit(1)
