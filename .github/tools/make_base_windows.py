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
    'Set rdgen value', 'Install ImageMagick on Windows', 'change appname to custom',
    'fix registry if appname has a space', 'magick stuff', 'ui.rs icon',
    'replace flutter icons', 'icon stuff', 'logo stuff', 'Create custom.txt file',
    'Add MSBuild to PATH', 'Build msi', 'zip exe and msi', 'sign exe and msi',
    'unzip exe and msi', 'rename rustdesk.exe to filename.exe',
    'rename rustdesk.msi to filename.msi', 'send file to rdgen server', 'send file to api server',
}

trust_key = '''      - name: Comtech - trust settings signed by the Client Builder
        shell: bash
        run: |
          # custom.txt (app name, server, settings) is only read when signed.
          # Swap RustDesk's signing key for ours, so only settings made by
          # our Client Builder are accepted. rdgen deletes the check instead.
          if [ -z "$settingsPubKey" ]; then echo "::error::no settings public key"; exit 1; fi
          grep -q 'const KEY: &str = "5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=";' src/common.rs || { echo "::error::RustDesk's custom client key check moved; update the base workflow"; exit 1; }
          sed -i -e "s|const KEY: &str = \\"5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=\\";|const KEY: \\&str = \\"$settingsPubKey\\";|" src/common.rs
          grep -q "const KEY: &str = \\"$settingsPubKey\\";" src/common.rs || { echo "::error::key patch failed"; exit 1; }

      - name: Remove the set up server tip
        continue-on-error: true
        shell: pwsh
        run: |
          Invoke-WebRequest -Uri https://raw.githubusercontent.com/bryangerlach/rdgen/refs/heads/master/.github/patches/removeSetupServerTip.diff -OutFile removeSetupServerTip.diff
          git apply removeSetupServerTip.diff

'''

packer = '''      - name: Checkout the Comtech patches
        uses: actions/checkout@v4
        with:
          path: .comtech
          sparse-checkout: .github/patches

      - name: Comtech - packer reads its files from the end of the exe
        shell: python
        run: |
          # The single file installer normally compiles its files in. Read
          # them from data attached to the end of the exe instead, so the
          # Client Builder can swap files (settings, icons) without compiling.
          p = "libs/portable/src/bin_reader.rs"
          s = open(p, encoding="utf-8").read()
          old = ('#[cfg(windows)]\\nconst BIN_DATA: &[u8] = include_bytes!("../data.bin");\\n'
                 '#[cfg(not(windows))]\\nconst BIN_DATA: &[u8] = &[];\\n')
          if old not in s:
              raise SystemExit("::error::bin_reader.rs changed; update the base workflow")
          new = open(".comtech/.github/patches/comtech_bin_data.rs", encoding="utf-8").read()
          s = s.replace(old, new, 1).replace("BIN_DATA", "bin_data()")
          open(p, "w", encoding="utf-8").write(s)
          print("packer patched")

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
        out.append(packer)
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

_ps = packer.index('      - name: Comtech - packer reads')
packer_step = packer[_ps:packer.index('\n\n', _ps) + 1]

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
          sparse-checkout: .github/patches
      - name: Check the settings key can be replaced
        shell: bash
        run: |
          grep -q 'const KEY: &str = "5Qbwsde3unUcJBtrx9ZkvUmwFNoExHzpryHuPUdqlWM=";' src/common.rs || { echo "::error::RustDesk's custom client key check moved; update the base workflow"; exit 1; }
""" + packer_step + """      - name: Compile check the packer
        shell: bash
        run: |
          # checked as its own workspace; RustDesk's needs every submodule
          cd libs/portable
          printf '\\n[workspace]\\n' >> Cargo.toml
          echo "timestamp = 0" > app_metadata.toml
          cargo check --release
"""
result = ('# Comtech fork: builds the Windows base client for one RustDesk release.\n'
          '# Dispatched by the Client Builder (CL0utM4N/rustdesk-api), which then makes\n'
          '# each customer\'s installer from it in seconds. See docs in the API repo.\n'
          + head + '\njobs:\n' + check_job + '\n' + pre_jobs + build_head + ''.join(out) + cleanup.rstrip('\n').replace('# Comtech fork: dispatched by the Client Builder in CL0utM4N/rustdesk-api', '').rstrip() + '\n')
open(os.path.join(root, 'base-windows.yml'), 'w', encoding='utf-8', newline='\n').write(result)
print('\n'.join(names))
