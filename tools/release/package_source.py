#!/usr/bin/env python3
"""Package the iOS source snapshot and checksum-verified Alpine source inputs."""
import argparse
import gzip
import hashlib
import json
import re
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def validate_alpine(root):
    manifest = json.loads((root / 'manifest.json').read_text())
    if manifest.get('errors') or not manifest.get('packages'):
        raise ValueError('Incomplete Alpine source collection')
    expected = {(p['o'], p['c']) for p in manifest['packages']}
    actual = {(p['origin'], p['aports_commit']) for p in manifest['origins']}
    if actual != expected or len(actual) != len(manifest['origins']):
        raise ValueError('Package origins do not match collected source revisions')
    for origin in manifest['origins']:
        recipe = root / 'recipes' / origin['origin'] / 'APKBUILD'
        if not recipe.is_file():
            raise ValueError('Missing APKBUILD')
        required = {(name, digest) for digest, name in re.findall(
            r'^([0-9a-f]{128})\s+([^\s]+)\s*$', recipe.read_text(), re.M)}
        provided = {(Path(item['file']).name, item['sha512']) for item in origin['sources']}
        if required != provided:
            raise ValueError('Collected source inputs do not match APKBUILD')
        if not required and (origin['origin'], origin['aports_commit']) != (
                'alpine-base', 'ba66879782e41ce6781dc34513a4953278ba832f'):
            raise ValueError('Unexpected recipe without source checksums')
        for item in origin['sources']:
            path = root / item['file']
            if not path.resolve().is_relative_to(root.resolve()) or path.is_symlink():
                raise ValueError('Source path escapes collection')
            if hashlib.sha512(path.read_bytes()).hexdigest() != item['sha512']:
                raise ValueError('Source checksum mismatch: ' + item['file'])
    return manifest


def source_files(repo):
    files = set()
    for pattern in ['ios-app/*.swift', 'ios-app/*.entitlements']:
        files.update(repo.glob(pattern))
    files.update(repo / x for x in [
        'LICENSE', 'THIRD_PARTY.md', 'Makefile', 'ios-app/project.yml', 'docs/COGNITIVE_CONTROL.md',
        'ios-app/PrivacyInfo.xcprivacy', 'ios-app/AppStore/PRIVACY_POLICY.md',
        'ios-app/AppStore/SUBMIT_GUIDE.md', 'ios-app/AppStore/OPEN_SOURCE_LICENSES.md',
    ])
    for directory in ['vendor/ish', 'ios-app/Assets.xcassets', 'ios-app/ShuyuRuntime',
                      'ios-app/zh-Hans.lproj', 'ios-app/en.lproj',
                      'tools/runtime', 'tools/shuyu', 'tools/release',
                      'tests/ios', 'tests/ui', 'shuyu']:
        for p in (repo / directory).rglob('*'):
            parts = p.relative_to(repo).parts
            if any(x in {'.git', '__pycache__', 'node_modules'} for x in parts):
                continue
            if p.is_file() and p.name != '.DS_Store' and p.suffix not in {'.pyc', '.log'}:
                files.add(p)
    files.update(p for p in (repo / 'ios-app/Runtime').iterdir()
                 if p.is_file() and (p.suffix in {'.m', '.h', '.md'} or p.name.startswith('LICENSE')))
    for p in files:
        if not p.is_file() or p.is_symlink() or not p.resolve().is_relative_to(repo.resolve()):
            raise ValueError('Missing or unsafe source path: ' + str(p))
    return sorted(files)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--alpine-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    alpine = validate_alpine(args.alpine_dir)
    installed = []
    for record in (ROOT / 'ios-app/Runtime/AlpineRootfs/data/lib/apk/db/installed').read_text().split('\n\n'):
        fields = dict(line.split(':', 1) for line in record.splitlines() if ':' in line)
        if 'P' in fields: installed.append({key: fields[key] for key in ['P', 'V', 'L', 'o', 'c']})
    if sorted(installed, key=lambda p: p['P']) != sorted(alpine['packages'], key=lambda p: p['P']):
        raise ValueError('Source packages do not match the bundled runtime')
    entries = [(p, 'Black-God/' + str(p.relative_to(ROOT))) for p in source_files(ROOT)]
    for p in sorted(args.alpine_dir.rglob('*')):
        if p.is_symlink():
            raise ValueError('Symlink in source collection')
        if p.is_file():
            entries.append((p, 'Black-God/third-party-sources/alpine/' + str(p.relative_to(args.alpine_dir))))
    files = [{'path': name, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'size': p.stat().st_size}
             for p, name in entries]
    project = (ROOT / 'ios-app/project.yml').read_text()
    version = re.search(r'MARKETING_VERSION: \"?([0-9.]+)', project).group(1)
    build = re.search(r'CURRENT_PROJECT_VERSION: \"?([0-9]+)', project).group(1)
    manifest = {'version': version, 'build': build, 'files': files,
                'alpinePackages': len(alpine['packages']), 'alpineOrigins': len(alpine['origins']),
                'note': 'Source snapshot plus verified source inputs; public hosting and distribution review remain separate.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', mtime=0, filename='') as gz:
        with tarfile.open(fileobj=gz, mode='w|') as archive:
            for p, name in entries:
                info = archive.gettarinfo(str(p), arcname=name)
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                with p.open('rb') as content:
                    archive.addfile(info, content)
    with tarfile.open(args.output) as archive:
        members = archive.getmembers()
        if len(members) != len(files):
            raise ValueError('Archive member mismatch')
        for item in files:
            data = archive.extractfile(item['path']).read()
            if hashlib.sha256(data).hexdigest() != item['sha256']:
                raise ValueError('Archive validation failed')
    manifest['archiveSha256'] = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2))
    print(json.dumps({k: v for k, v in manifest.items() if k != 'files'}, indent=2))
    print('Verified archive files:', len(files))


if __name__ == '__main__':
    main()
