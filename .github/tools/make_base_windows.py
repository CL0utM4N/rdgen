"""Builds .github/workflows/base-windows.yml from generator-windows.yml.

Run after changing generator-windows.yml:
    python .github/tools/make_base_windows.py

The base workflow builds one Windows client per RustDesk release that the
Client Builder then brands per customer on the server in seconds."""
import re

import os

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'workflows')
src = open(os.path.join(root, 'generator-windows.yml'), encoding='utf-8').read()

head, rest = src.split('\njobs:\n', 1)
build_start = rest.index('  build-for-windows-flutter:')
cleanup_start = rest.index('\n  cleanup:')
pre_jobs = rest[:build_start]
build = rest[build_start:cleanup_start]
cleanup = rest[cleanup_start:]

steps_at = build.index('    steps:\n') + len('    steps:\n')
build_head, steps_text = build[:steps_at], build[steps_at:]
# split into steps: each starts with "      - "
parts = re.split(r'(?m)^(?=      - )', steps_text)
steps = [p for p in parts if p.strip()]


def name_of(step):
    m = re.match(r'      - name: (.*)', step)
    return m.group(1).strip() if m else step.split('\n')[0].strip()


drop = {
    'Set rdgen value', 'Install ImageMagick on Windows', 'removeNewVersionNotif', 'change appname to custom',
    'fix install commands if appname has a space', 'magick stuff', 'ui.rs icon',
    'replace flutter icons', 'icon stuff', 'logo stuff', 'Create custom.txt file',
    'Add MSBuild to PATH', 'Build msi', 'zip exe and msi', 'sign exe and msi',
    'unzip exe and msi', 'rename rustdesk.exe to filename.exe',
    'rename rustdesk.msi to filename.msi', 'send file to rdgen server', 'send file to api server',
}

trust_key = '''      - name: Checkout the Comtech patches
        uses: actions/checkout@v4
        with:
          path: .comtech
          sparse-checkout: |
            .github/patches
            comtech_console

      - name: Comtech changes
        shell: bash
        run: |
          # signed settings only, updates from our server, and an installer
          # the Client Builder can brand; see .github/patches/comtech_patch.py
          python3 .comtech/.github/patches/comtech_patch.py --key "$settingsPubKey" --updates --packer --console --check-button

      - name: Remove the set up server tip
        continue-on-error: true
        shell: pwsh
        run: |
          Invoke-WebRequest -Uri https://raw.githubusercontent.com/bryangerlach/rdgen/refs/heads/master/.github/patches/removeSetupServerTip.diff -OutFile removeSetupServerTip.diff
          git apply removeSetupServerTip.diff

'''

build_base = '''      - name: Build the packer and its files
        shell: bash
        run: |
          sed -i '/dpiAware/d' res/manifest.xml
          pushd ./libs/portable
          pip3 install -r requirements.txt
          python3 ./generate.py -f ../../rustdesk/ -o . -e "../../rustdesk/rustdesk.exe"
          popd
          mkdir -p ./BaseOutput
          cp ./target/release/rustdesk-portable-packer.exe ./BaseOutput/stub.exe
          cp ./libs/portable/data.bin ./BaseOutput/data.bin
          ls -l ./BaseOutput

      - name: Send the base client to the Client Builder
        uses: nick-fields/retry@v3
        with:
          timeout_minutes: 20
          max_attempts: 3
          retry_wait_seconds: 30
          shell: bash
          command: |
            curl -fsS -X POST -H "Authorization: Bearer ${{ env.token }}" \\
              -F "uuid=${{ env.uuid }}" -F "version=${{ env.VERSION }}" \\
              -F "stub=@./BaseOutput/stub.exe" -F "data=@./BaseOutput/data.bin" \\
              "${{ env.genurl }}/base/upload"

'''

out = []
for st in steps:
    n = name_of(st)
    if n in drop:
        continue
    if n == 'allow custom.txt':
        out.append(trust_key)
        continue
    if n == 'Build self-extracted executable':
        out.append(build_base)
        continue
    out.append(st)

names = [name_of(s) for s in out]
for required in ['Build rustdesk', 'set server, serverPort, key, and apiserver', 'Comtech - upload session recordings to the API']:
    assert required in names, required

head = head.replace('name: Custom Windows Client Generator\nrun-name: Custom Windows Client Generator',
                    'name: Comtech Windows Base Client\nrun-name: Comtech Windows Base Client ${{ inputs.version }}')
head = head.replace("  STATUS_URL: \"${{ secrets.GENURL }}/updategh\"\n", '')
build_head = build_head.replace('name: Build Windows', 'name: Build Windows base client').replace('needs: [build-RustDeskTempTopMostWindow, generate-bridge, setup]', 'needs: [build-RustDeskTempTopMostWindow, generate-bridge, setup, check-patches]')

check_job = """  check-patches:
    name: Check the Comtech changes still apply
    runs-on: windows-2022
    steps:
      - name: Checkout RustDesk
        uses: actions/checkout@v4
        with:
          repository: rustdesk/rustdesk
          ref: ${{ inputs.version == 'master' && 'master' || format('refs/tags/{0}', inputs.version) }}
      - name: Checkout the Comtech patches
        uses: actions/checkout@v4
        with:
          path: .comtech
          sparse-checkout: |
            .github/patches
            comtech_console
      - name: Check the Comtech changes apply
        shell: bash
        run: python3 .comtech/.github/patches/comtech_patch.py --check --updates --packer --console --check-button
      - name: Compile check the packer
        shell: bash
        run: |
          python3 .comtech/.github/patches/comtech_patch.py --key check --packer
          # checked as its own workspace; RustDesk's needs every submodule
          cd libs/portable
          echo >> Cargo.toml
          echo "[workspace]" >> Cargo.toml
          echo "timestamp = 0" > app_metadata.toml
          cargo check --release
"""
result = ('# Comtech fork: builds the Windows base client for one RustDesk release.\n'
          '# Dispatched by the Client Builder (CL0utM4N/rustdesk-api), which then makes\n'
          '# each customer\'s installer from it in seconds. See docs in the API repo.\n'
          + head + '\njobs:\n' + check_job + '\n' + pre_jobs + build_head + ''.join(out) + cleanup.rstrip('\n').replace('# Comtech fork: dispatched by the Client Builder in CL0utM4N/rustdesk-api', '').rstrip() + '\n')
open(os.path.join(root, 'base-windows.yml'), 'w', encoding='utf-8', newline='\n').write(result)
print('\n'.join(names))
