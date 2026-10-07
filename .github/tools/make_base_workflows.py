"""Builds base-linux.yml, base-macos.yml and base-android.yml from the rdgen
generator workflows (base-windows.yml has its own script).

A base client is RustDesk built once per release with the Comtech changes
(.github/patches/comtech_patch.py); the Client Builder then brands each
customer's packages on the server in seconds. Run after changing a
generator workflow:
    python .github/tools/make_base_workflows.py
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'workflows')


def split_jobs(src):
    head, rest = src.split('\njobs:\n', 1)
    starts = [m.start() for m in re.finditer(r'(?m)^  [A-Za-z0-9_-]+:\s*$', rest)]
    jobs = []
    for i, s in enumerate(starts):
        e = starts[i + 1] if i + 1 < len(starts) else len(rest)
        block = rest[s:e]
        name = block.split(':', 1)[0].strip()
        jobs.append([name, block])
    return head, jobs


def split_steps(block):
    if '    steps:\n' not in block:
        return block, []
    at = block.index('    steps:\n') + len('    steps:\n')
    parts = [p for p in re.split(r'(?m)^(?=      - )', block[at:]) if p.strip()]
    return block[:at], parts


def step_name(step):
    m = re.match(r'      - (?:uses: \S+\n\s+)?name: (.*)', step)
    if m:
        return m.group(1).strip()
    m = re.match(r'      - uses: (\S+)', step)
    return m.group(1) if m else step.split('\n')[0].strip()


def checkout_patches():
    return '''      - name: Checkout the Comtech patches
        uses: actions/checkout@v4
        with:
          path: .comtech
          sparse-checkout: |
            .github/patches
            comtech_console

'''


def comtech_step(flags):
    return f'''      - name: Comtech changes
        shell: bash
        run: |
          # signed settings only; see .github/patches/comtech_patch.py
          python3 .comtech/.github/patches/comtech_patch.py --key "$settingsPubKey" {flags}
          wget -q https://raw.githubusercontent.com/bryangerlach/rdgen/refs/heads/master/.github/patches/removeSetupServerTip.diff
          git apply removeSetupServerTip.diff || echo "::warning::set up server tip patch did not apply"
          # the build copies this into the packages; the settings come later
          : > custom_.txt

'''


def upload_step(files):
    lines = '\n'.join(f'            [ -f "{src}" ] && args+=(-F "files=@{src};filename={name}")' for src, name in files)
    return f'''      - name: Send the base client to the Client Builder
        uses: nick-fields/retry@v3
        with:
          timeout_minutes: 20
          max_attempts: 3
          retry_wait_seconds: 30
          shell: bash
          command: |
            args=()
{lines}
            if [ ${{#args[@]}} -eq 0 ]; then echo "::error::nothing to upload"; ls -la; exit 1; fi
            curl -fsS -X POST -H "Authorization: Bearer ${{{{ env.token }}}}" -F "uuid=${{{{ env.uuid }}}}" "${{args[@]}}" "${{{{ env.genurl }}}}/base/upload"

'''


def check_job(runs_on, flags):
    return f"""  check-patches:
    name: Check the Comtech changes still apply
    runs-on: {runs_on}
    steps:
      - name: Checkout RustDesk
        uses: actions/checkout@v4
        with:
          repository: rustdesk/rustdesk
          ref: ${{{{ inputs.version == 'master' && 'master' || format('refs/tags/{{0}}', inputs.version) }}}}
      - name: Checkout the Comtech patches
        uses: actions/checkout@v4
        with:
          path: .comtech
          sparse-checkout: |
            .github/patches
            comtech_console
      - name: Check the Comtech changes apply
        shell: bash
        run: python3 .comtech/.github/patches/comtech_patch.py --check {flags}

"""


def transform(steps, drop, replace, after):
    """drop: names to remove; replace: name -> text; after: name -> text to
    add after that step"""
    out = []
    names = []
    for st in steps:
        n = step_name(st)
        names.append(n)
        if n in drop:
            continue
        if n in replace:
            out.append(replace[n])
        else:
            out.append(st)
        if n in after:
            out.append(after[n])
    for n in list(replace) + list(after):
        assert n in names, f'step "{n}" not found'
    return out


def build(src_name, dst_name, title, platform_flags, runs_on, jobs_keep, main_jobs, needs_fix):
    src = open(os.path.join(ROOT, src_name), encoding='utf-8').read()
    head, jobs = split_jobs(src)
    head = re.sub(r'(?m)^name: .*$', f'name: {title}', head, count=1)
    head = re.sub(r'(?m)^run-name: .*$', f'run-name: {title} ${{{{ inputs.version }}}}', head, count=1)
    body = [check_job(runs_on, platform_flags)]
    for name, block in jobs:
        if name not in jobs_keep:
            continue
        job_head, steps = split_steps(block)
        if name in main_jobs:
            drop, replace, after = main_jobs[name]
            steps = transform(steps, drop, replace, after)
        for old, new in needs_fix.get(name, []):
            assert old in job_head, (name, old)
            job_head = job_head.replace(old, new)
        body.append(job_head + ''.join(steps))
    result = (f'# Comtech fork: builds the {title.split()[1]} base client for one RustDesk release.\n'
              '# Generated by .github/tools/make_base_workflows.py; dispatched by the Client\n'
              '# Builder (CL0utM4N/rustdesk-api), which brands each customer\'s packages from it.\n'
              + head + '\njobs:\n' + ''.join(body).rstrip() + '\n')
    result = result.replace('# Comtech fork: dispatched by the Client Builder in CL0utM4N/rustdesk-api\n', '')
    open(os.path.join(ROOT, dst_name), 'w', encoding='utf-8', newline='\n').write(result)
    print('wrote', dst_name)


COMMON_DROP = {'Set rdgen value', 'icon stuff', 'removeNewVersionNotif', 'send file to rdgen server', 'send file to api server'}
ARCH = '${{ matrix.job.arch }}'

# --- Linux: deb, rpm (Fedora and SUSE), Arch and AppImage ---
placeholder_src = '''            ls -l "$BUNDLE/custom_.txt" || echo "WARN: custom_.txt missing from bundle ($BUNDLE)"
'''
placeholder_new = placeholder_src + '''            # Comtech: a fixed size custom.txt the Client Builder fills in the
            # .rpm packages (their file checksums are in the header)
            printf '%16384s' '' > "$BUNDLE/custom.txt"
'''
src = open(os.path.join(ROOT, 'generator-linux.yml'), encoding='utf-8').read()
_, ljobs = split_jobs(src)
build_step = [s for s in split_steps(dict(ljobs)['build-rustdesk-linux'])[1] if step_name(s) == 'Build rustdesk'][0]
assert placeholder_src in build_step, 'Linux build step changed; update the placeholder'
build(
    'generator-linux.yml', 'base-linux.yml', 'Comtech Linux Base Client', '--appimage --console --linux-updates --check-button', 'ubuntu-22.04',
    jobs_keep={'setup', 'generate-bridge-linux', 'build-rustdesk-linux', 'build-appimage', 'cleanup'},
    main_jobs={
        'build-rustdesk-linux': (COMMON_DROP, {
            'allow custom.txt': checkout_patches() + comtech_step('--appimage --console --linux-updates --check-button'),
            'Build rustdesk': build_step.replace(placeholder_src, placeholder_new),
        }, {
            'Rename archlinux package': upload_step([
                (f'./output/rustdesk-{ARCH}.deb', f'{ARCH}.deb'),
                (f'./output/rustdesk-{ARCH}.rpm', f'{ARCH}.rpm'),
                (f'./output/rustdesk-suse-{ARCH}.rpm', f'{ARCH}-suse.rpm'),
                (f'./output/rustdesk-{ARCH}.pkg.tar.zst', f'{ARCH}.pkg.tar.zst'),
            ]),
        }),
        'build-appimage': (COMMON_DROP, {}, {
            'Build AppImage': upload_step([(f'./appimage/rustdesk-{ARCH}.AppImage', f'{ARCH}.AppImage')]),
        }),
    },
    needs_fix={
        'build-rustdesk-linux': [('needs: [generate-bridge-linux, setup]', 'needs: [generate-bridge-linux, setup, check-patches]')],
        'cleanup': [('needs: [build-rustdesk-linux,build-flatpak,build-appimage,deploy]', 'needs: [build-rustdesk-linux, build-appimage]')],
    },
)

# --- macOS: RustDesk.app for Apple silicon and Intel ---
build(
    'generator-macos.yml', 'base-macos.yml', 'Comtech macOS Base Client', '--console --mac-updates --check-button', 'ubuntu-22.04',
    jobs_keep={'setup', 'generate-bridge', 'build-for-macos', 'cleanup'},
    main_jobs={
        'build-for-macos': (COMMON_DROP | {
            'Magick stuff for macOS', 'replace flutter icons', 'ui.rs', 'Embed custom config into the .app bundle',
            'Install rcodesign tool', 'icon svg handling', 'logo handling', 'Sign macOS app bundle',
            'Ad-hoc Sign macOS app bundle (Fallback)', 'Create DMG', 'Rename rustdesk'}, {
            'allow custom.txt': checkout_patches() + comtech_step('--console --mac-updates --check-button'),
        }, {
            # the server brands and signs the app, so it's sent unsigned
            'Build rustdesk': '''      - name: Pack the base app
        shell: bash
        run: |
          cd flutter/build/macos/Build/Products/Release
          app=$(ls -d *.app | head -1)
          COPYFILE_DISABLE=1 tar -czf "$GITHUB_WORKSPACE/base-app.tar.gz" "$app"
          ls -l "$GITHUB_WORKSPACE/base-app.tar.gz"

''' + upload_step([('./base-app.tar.gz', f'{ARCH}.tar.gz')]),
        }),
    },
    needs_fix={'build-for-macos': [('needs: [generate-bridge, setup]', 'needs: [generate-bridge, setup, check-patches]')]},
)

# --- Android: an APK per processor type ---
build(
    'generator-android.yml', 'base-android.yml', 'Comtech Android Base Client', '--android --console --android-updates --check-button', 'ubuntu-22.04',
    jobs_keep={'setup', 'generate-bridge-linux', 'build-rustdesk-android', 'deploy', 'cleanup'},
    main_jobs={
        'build-rustdesk-android': (COMMON_DROP | {
            'Embed custom config for Android', 'replace flutter icons', 'icons', 'Sign app APK',
            'Prefer signed APK when available'}, {
            'allow custom.txt': checkout_patches() + comtech_step('--android --console --android-updates --check-button'),
        }, {
            # the server signs it with its own key once branded
            'Build rustdesk': upload_step([(f'./signed-apk/rustdesk-{ARCH}.apk', f'{ARCH}.apk')]),
        }),
    },
    needs_fix={'build-rustdesk-android': [('needs: [generate-bridge-linux, setup]', 'needs: [generate-bridge-linux, setup, check-patches]')]},
)
