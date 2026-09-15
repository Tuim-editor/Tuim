#!/usr/bin/env python3
"""Run setup in disposable homes against local release/tool fixtures, without network."""
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASH = shutil.which('bash')


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)


def archive(path, files):
    mode = 'w:xz' if path.name.endswith('.xz') else 'w:gz'
    with tarfile.open(path, mode) as tar:
        for name, value in files.items():
            info = tarfile.TarInfo(name)
            info.mode = 0o755 if value.startswith('#!') else 0o644
            data = value.encode()
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


with tempfile.TemporaryDirectory(prefix='tuim-installer-test-') as directory:
    base = Path(directory)
    fixtures = base / 'fixtures'
    fixtures.mkdir()
    mockbin = base / 'bin'
    mockbin.mkdir()
    calls = base / 'calls.log'
    nvim = '''#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then echo 'NVIM v0.12.4'; exit; fi
printf 'bootstrap:%s:%s\\n' "$NVIM_APPNAME" "$TUIM_INIT_PATH" >> "$TUIM_FIXTURE_CALLS"
test -f "$TUIM_INIT_PATH" || exit 8
[ "${TUIM_DISABLE_PLUGINS:-}" != 1 ] || exit 9
[ "${TUIM_FIXTURE_BOOT_FAIL:-0}" != 1 ] || exit 7
'''
    files = {
        'tuim-linux-x86_64/bin/tuim': '#!/bin/sh\necho "Tuim fixture"\n',
        'tuim-linux-x86_64/lib/tuim/tuim': '#!/bin/sh\necho "Tuim fixture"\n',
        'tuim-linux-x86_64/lib/tuim/nvim/bin/nvim': nvim,
        'tuim-linux-x86_64/lib/tuim/nvim/share/nvim/runtime/doc/help.txt': 'runtime',
        'tuim-linux-x86_64/lib/tuim/tuim_init.lua': '-- bundled matching init',
    }

    def make_release(contents):
        archive(fixtures / 'tuim-linux-x86_64.tar.gz', contents)
        digest = hashlib.sha256((fixtures / 'tuim-linux-x86_64.tar.gz').read_bytes()).hexdigest()
        (fixtures / 'SHA256SUMS').write_text(f'{digest}  tuim-linux-x86_64.tar.gz\n')

    make_release(files)
    (fixtures / 'release.json').write_text(json.dumps({'tag_name': 'v9.8.7'}))
    tree_sitter = '#!/bin/sh\necho "tree-sitter 0.26.1"\n'
    (fixtures / 'tree-sitter-linux-x64.gz').write_bytes(gzip.compress(tree_sitter.encode()))
    archive(fixtures / 'nvim-linux-x86_64.tar.gz', {
        'nvim-linux-x86_64/bin/nvim': nvim,
        'nvim-linux-x86_64/share/nvim/runtime/doc/help.txt': 'runtime',
    })
    zig = '''#!/usr/bin/env bash
if [ "$1" = version ]; then echo 0.16.0; exit; fi
while [ "$#" -gt 0 ]; do
 if [ "$1" = --prefix ]; then shift; prefix=$1; fi
 shift
done
mkdir -p "$prefix/bin"
printf '#!/bin/sh\\necho "source fixture"\\n' > "$prefix/bin/tuim"
chmod 755 "$prefix/bin/tuim"
'''
    archive(fixtures / 'zig.tar.xz', {'zig-fixture/zig': zig})
    digest = hashlib.sha256((fixtures / 'zig.tar.xz').read_bytes()).hexdigest()
    (fixtures / 'zig-index.json').write_text(json.dumps({'0.16.0': {'x86_64-linux': {
        'tarball': 'https://ziglang.org/download/0.16.0/zig.tar.xz', 'shasum': digest}}}))
    for filename in ('tree-sitter-linux-x64.gz', 'nvim-linux-x86_64.tar.gz'):
        digest = hashlib.sha256((fixtures / filename).read_bytes()).hexdigest()
        (fixtures / (filename + '.json')).write_text(json.dumps({'assets': [{'name': filename, 'digest': 'sha256:' + digest}]}))
    executable(mockbin / 'curl', '''#!/usr/bin/env python3
import os, pathlib, shutil, sys
args=sys.argv[1:]; url=args[-1]; target=pathlib.Path(args[args.index('-o')+1])
root=pathlib.Path(os.environ['TUIM_FIXTURES'])
with open(os.environ['TUIM_FIXTURE_CALLS'], 'a') as file: file.write(url+'\\n')
if url.endswith('/tuim/releases/latest'): name='release.json'
elif '/tree-sitter/releases/tags/' in url: name='tree-sitter-linux-x64.gz.json'
elif '/neovim/releases/tags/' in url: name='nvim-linux-x86_64.tar.gz.json'
elif url.endswith('/download/index.json'): name='zig-index.json'
elif 'raw.githubusercontent.com/Rouboufy/tuim/v9.8.7/' in url:
 target.write_text('-- matching legacy release init'); sys.exit(0)
else: name=url.rsplit('/',1)[-1]
source=root/name
if not source.is_file(): sys.exit('Unexpected network request: '+url)
shutil.copyfile(source,target)
''')
    for cmd in ('tree-sitter', 'nvim', 'zig'):
        executable(mockbin / cmd, '#!/bin/sh\nexit 1\n')
    env = os.environ.copy()
    env.update(PATH=str(mockbin) + ':' + env['PATH'], TUIM_FIXTURES=str(fixtures),
               TUIM_FIXTURE_CALLS=str(calls), TUIM_TEST_MISSING='',
               TUIM_TEST_PLATFORM='Linux', TUIM_TEST_ARCH='x86_64', TUIM_SKIP_ONBOARDING='1')

    def install(name, args=('--yes',), pipe=False, overrides=None, script=None):
        home = base / name
        home.mkdir(exist_ok=True)
        runenv = env | {'HOME': str(home)}
        for key in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            runenv[f'XDG_{key}_HOME'] = str(home / key.lower())
        runenv.update(overrides or {})
        script = script or ROOT / 'setup.sh'
        command = [BASH, '-s', '--', *args] if pipe else [BASH, str(script), *args]
        result = subprocess.run(command, input=script.read_text() if pipe else '',
                                text=True, capture_output=True, env=runenv, cwd=home,
                                start_new_session=True, timeout=30)
        return home, result

    home, result = install('piped install with spaces', pipe=True, overrides={'TUIM_DISABLE_PLUGINS': '1'})
    assert result.returncode == 0, result.stdout + result.stderr
    launcher = home / '.local/bin/tuim'
    assert launcher.is_symlink() and launcher.resolve().is_file()
    assert (home / 'data/tuim/tools/bin/tree-sitter').is_file()
    assert 'bootstrap:tuim:' in calls.read_text()
    assert '/releases/download/v9.8.7/' in calls.read_text()
    assert 'raw.githubusercontent' not in calls.read_text(), 'Bundled init should be preferred'
    assert 'Tuim installed at' in result.stdout
    settings = home / 'data/tuim/settings.json'
    settings.write_text('{"theme":"nord"}')
    _, result = install(home.name)
    assert result.returncode == 0 and settings.read_text() == '{"theme":"nord"}'

    (fixtures / 'SHA256SUMS').write_text('bad  tuim-linux-x86_64.tar.gz\n')
    _, result = install(home.name)
    assert result.returncode != 0 and 'checksum' in result.stderr
    assert launcher.resolve().is_file() and settings.read_text() == '{"theme":"nord"}'
    assert 'Tuim installed at' not in result.stdout

    make_release({k: v for k, v in files.items() if not k.endswith('lib/tuim/nvim/bin/nvim')})
    _, result = install('broken-bundle')
    assert result.returncode != 0 and 'Invalid release bundle' in result.stderr
    make_release(files)
    _, result = install('failed-bootstrap', overrides={'TUIM_FIXTURE_BOOT_FAIL': '1'})
    assert result.returncode != 0 and 'Tuim installed at' not in result.stdout
    calls.write_text('')
    _, result = install('no-plugins', args=('--no-plugins', '--yes'))
    assert result.returncode == 0, result.stderr
    assert 'bootstrap:' not in calls.read_text() and 'tree-sitter' not in calls.read_text()

    make_release({k: v for k, v in files.items() if not k.endswith('tuim_init.lua')})
    calls.write_text('')
    _, result = install('legacy-bundle')
    assert result.returncode == 0, result.stderr
    assert '/tuim/v9.8.7/src/nvim/tuim_init.lua' in calls.read_text()
    make_release(files)

    _, result = install('no-tty', args=(), overrides={'TUIM_TEST_MISSING': 'git'})
    assert result.returncode != 0 and 'Use --yes' in result.stderr

    project = base / 'source project'
    project.mkdir()
    shutil.copyfile(ROOT / 'setup.sh', project / 'setup.sh')
    (project / 'build.zig').write_text('// source fixture')
    (project / 'src/nvim').mkdir(parents=True)
    (project / 'src/nvim/tuim_init.lua').write_text('-- init')
    source_home, result = install('source-home', args=('--source', '--yes'), script=project / 'setup.sh')
    assert result.returncode == 0, result.stdout + result.stderr
    assert (source_home / 'data/tuim/tools/bin/zig').is_symlink()
    assert (source_home / 'data/tuim/tools/nvim/bin/nvim').is_file()
    source_launcher = source_home / '.local/bin/tuim'
    launched = subprocess.check_output([str(source_launcher)], text=True, env=env)
    assert 'source fixture' in launched
    assert 'PATH=.' not in source_launcher.read_text()

print('Installer passed: piped fresh install, upgrade preservation, checksum rejection, invalid bundle, bootstrap failure, no-plugins, legacy bundle, no TTY, private source toolchains')
