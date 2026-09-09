#!/usr/bin/env python3
"""Create the pinned runtime image; APK verifies repository signatures offline."""
import hashlib,json,shutil,sqlite3,struct,subprocess,urllib.request,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'.runtime-build'
lock=json.loads((ROOT/'tools/runtime/image-lock.json').read_text())
fingerprint=hashlib.sha256((ROOT/'tools/runtime/image-lock.json').read_bytes()).hexdigest()
output=ROOT/'ios-app/Runtime/AlpineRootfs'
marker=output/'image-info.json'
if marker.exists() and json.loads(marker.read_text()).get('lockSha256')==fingerprint:
    print('Pinned runtime image already prepared');raise SystemExit(0)
def download(item):
    path=BUILD/item['file']
    if not path.exists():
        temporary=path.with_suffix(path.suffix+'.download')
        try:
            with urllib.request.urlopen(item['url'],timeout=60) as r:temporary.write_bytes(r.read())
            if hashlib.sha256(temporary.read_bytes()).hexdigest()!=item['sha256']:raise ValueError('Downloaded checksum mismatch')
            temporary.replace(path)
        finally:temporary.unlink(missing_ok=True)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:raise ValueError('Cached checksum mismatch: '+path.name)
    return path
base=download(lock['archive']); packages=[download(p) for p in lock['packages']]
staging=BUILD/('image-'+uuid.uuid4().hex)
backup=BUILD/('previous-image-'+uuid.uuid4().hex)
try:
    subprocess.run([BUILD/'host/tools/fakefsify',base,staging],check=True)
    db=sqlite3.connect(staging/'meta.db')
    for p in packages:
        shutil.copy2(p,staging/'data/tmp'/p.name)
        row=db.execute('INSERT INTO stats(stat) VALUES(?)',(struct.pack('<IIII',0o100644,0,0,0),))
        db.execute('INSERT INTO paths(path,inode) VALUES(?,?)',(('/tmp/'+p.name).encode(),row.lastrowid))
    db.commit();db.close()
    ish=BUILD/'host/ish'
    subprocess.run([ish,'-f',staging,'/sbin/apk','add','--no-network',*['/tmp/'+p.name for p in packages]],check=True,timeout=120)
    subprocess.run([ish,'-f',staging,'/bin/sh','-c','rm -f /tmp/*.apk; rm -rf /var/cache/apk/*'],check=True,timeout=30)
    # Close the host guest completely before distributing its SQLite image.
    db=sqlite3.connect(staging/'meta.db');db.execute('PRAGMA wal_checkpoint(TRUNCATE)');db.close()
    info={k:lock[k] for k in ['id','alpineVersion','branch']};info['lockSha256']=fingerprint
    (staging/'image-info.json').write_text(json.dumps(info,indent=2)+'\n')
    if output.exists():output.rename(backup)
    try:shutil.move(staging,output)
    except Exception:
        if backup.exists():backup.rename(output)
        raise
    print('Prepared verified runtime image:',lock['id'])
finally:
    if staging.exists():shutil.rmtree(staging)
