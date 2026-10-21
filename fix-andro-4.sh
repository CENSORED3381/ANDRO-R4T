#!/usr/bin/env bash
# fix-andro-4.sh — corrige build.yml quebrado + /sdcard/Download restantes
set -euo pipefail

BACKUP=".fix-backup-4-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

python3 - "$BACKUP" <<'PYEOF'
import os, re, sys, shutil, glob

BACKUP = sys.argv[1]
ERRORS = []

def find(name):
    return [p for p in glob.glob(os.path.join('**', name), recursive=True)
            if '.fix-backup' not in p]

def backup(p):
    rel = os.path.relpath(p)
    dst = os.path.join(BACKUP, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(p, dst)

def read(p):  return open(p, encoding='utf-8', errors='replace').read()
def write(p, s): open(p, 'w', encoding='utf-8').write(s)

# ============================================================================
# A) build.yml — desfaz a quebra de linha e adiciona exit $exit_code
# ============================================================================
print("\n[A] .github/workflows/build.yml")
for wf in find('build.yml'):
    if '.github' not in wf:
        continue
    s = read(wf); orig = s

    # A1. Corrige `./gradlew assembleDebug \ || exit 1` → `./gradlew assembleDebug \`
    s = re.sub(
        r'(\./gradlew\s+assembleDebug)\s*\\\s*\|\|\s*exit\s+1',
        r'\1 \\',
        s,
    )

    # A2. Adiciona `exit $exit_code` no fim do run block (se houver set +e + exit_code=$?)
    if 'set +e' in s and 'exit_code=$?' in s and 'exit $exit_code' not in s:
        lines = s.split('\n')
        out, in_run, run_indent, seen = [], False, 0, False
        for line in lines:
            m = re.match(r'^(\s*)run:\s*\|\s*$', line)
            if m:
                in_run, run_indent, seen = True, len(m.group(1)), False
                out.append(line)
                continue
            if in_run:
                stripped = line.rstrip()
                cur = len(line) - len(line.lstrip()) if stripped else 9999
                if stripped and cur <= run_indent:
                    if seen:
                        out.append(' ' * (run_indent + 2) + 'exit $exit_code')
                    in_run = False
                    out.append(line)
                    continue
                if 'exit_code=$?' in line:
                    seen = True
            out.append(line)
        if in_run and seen:
            out.append(' ' * (run_indent + 2) + 'exit $exit_code')
        s = '\n'.join(out)

    # A3. Diagnose é só diagnóstico — não deve bloquear o workflow
    s = re.sub(
        r'(- name:\s*Diagnose\s+Kotlin\s+dependencies\s*\n\s*continue-on-error:\s*)false',
        r'\1true',
        s,
    )

    if s != orig:
        backup(wf); write(wf, s)
        print(f"    ✓ {wf}")
    else:
        print(f"    · {wf} (sem mudança)")

    # Validação opcional de YAML
    try:
        import yaml
        yaml.safe_load(read(wf))
        print("    ✓ YAML válido")
    except ImportError:
        print("    · pyyaml ausente, pulando validação (pkg install python-pyyaml)")
    except Exception as e:
        ERRORS.append(f"YAML inválido: {e}")
        print(f"    ✗ YAML inválido: {e}")

# ============================================================================
# B) /sdcard/Download restantes — injeta helper __appDir() e substitui
# ============================================================================
HELPER = '''
    private static java.io.File __appDir() {
        try {
            Object __a = Class.forName("android.app.ActivityThread")
                    .getDeclaredMethod("currentApplication").invoke(null);
            java.io.File __d = (java.io.File) __a.getClass()
                    .getMethod("getExternalFilesDir", String.class)
                    .invoke(__a, (Object) null);
            if (__d != null) return __d;
        } catch (Throwable __t) {}
        try {
            return new java.io.File(System.getProperty("java.io.tmpdir", "/data/local/tmp"));
        } catch (Throwable __t) {
            return new java.io.File("/data/local/tmp");
        }
    }
'''

for fname in ('CmdHandler.java', 'ModMedia.java', 'TgApi.java'):
    print(f"\n[B] {fname}")
    for p in find(fname):
        s = read(p); orig = s

        # 1. new File("/sdcard/Download/" + X)
        s = re.sub(r'new\s+File\s*\(\s*"/sdcard/Download/"\s*\+\s*',
                   'new File(__appDir(), ', s)
        # 2. new File("/sdcard/Download", X)
        s = re.sub(r'new\s+File\s*\(\s*"/sdcard/Download/?"\s*,',
                   'new File(__appDir(),', s)
        # 3. new File("/sdcard/Download/foo")
        s = re.sub(r'new\s+File\s*\(\s*"/sdcard/Download/([^"]+)"\s*\)',
                   r'new File(__appDir(), "\1")', s)
        # 4. new File("/sdcard/Download")
        s = re.sub(r'new\s+File\s*\(\s*"/sdcard/Download/?"\s*\)',
                   '__appDir()', s)
        # 5. Strings de mensagem: ".../sdcard/Download/" + X
        s = re.sub(r'"([^"]*?)/sdcard/Download/"\s*\+\s*',
                   r'"\1" + ', s)
        # 6. ".../sdcard/Download/resto" (dentro de string)
        s = re.sub(r'"([^"]*?)/sdcard/Download/([^"]*)"',
                   r'"\1\2"', s)

        # Injeta helper se houve mudança e ele ainda não existe
        if s != orig and '__appDir' not in s:
            idx = s.rfind('}')
            if idx > 0:
                s = s[:idx] + HELPER + '\n' + s[idx:]

        if s != orig:
            backup(p); write(p, s)
            print(f"    ✓ {p}")
        else:
            print(f"    · {p} (sem mudança)")

        # Verifica resíduos
        for i, line in enumerate(read(p).splitlines(), 1):
            if '/sdcard/Download' in line:
                print(f"    ! linha {i}: {line.strip()}")
                ERRORS.append(f"resíduo em {p}:{i}")

print("\n" + "=" * 60)
if ERRORS:
    print("\033[0;31m[!] pendências:\033[0m")
    for e in ERRORS:
        print(f"  - {e}")
else:
    print("\033[0;32m[✓] tudo corrigido\033[0m")
PYEOF

echo
echo "[+] Backup: $BACKUP"
git --no-pager diff --stat 2>/dev/null || true
