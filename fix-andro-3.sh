#!/usr/bin/env bash
# fix-andro-3.sh — corrige ShotActivity (new File com 2 args) e TelegramService (variáveis locais)
set -euo pipefail

BACKUP=".fix-backup-3-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

python3 - "$BACKUP" <<'PYEOF'
import os, re, sys, shutil, glob

BACKUP = sys.argv[1]
ERRORS = []

def find(name):
    r = glob.glob(os.path.join('**', name), recursive=True)
    return [p for p in r if '.fix-backup' not in p]

def backup(p):
    rel = os.path.relpath(p)
    dst = os.path.join(BACKUP, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(p, dst)

def read(p):  return open(p, encoding='utf-8', errors='replace').read()
def write(p, s): open(p, 'w', encoding='utf-8').write(s)

# ============================================================================
# A) ShotActivity.java — cobre TODOS os formatos conhecidos
# ============================================================================
print("\n[A] ShotActivity.java")
for sa in find('ShotActivity.java'):
    s = read(sa); orig = s

    # 1. Formato exato relatado: new File("/sdcard/Download", ...
    s = re.sub(
        r'new\s+File\s*\(\s*"/sdcard/Download/?"\s*,',
        'new File(getExternalFilesDir(null),',
        s,
    )

    # 2. Formato: new File("/sdcard/Download/algumacoisa")
    s = re.sub(
        r'new\s+File\s*\(\s*"/sdcard/Download/([^"]+)"\s*\)',
        r'new File(getExternalFilesDir(null), "\1")',
        s,
    )

    # 3. Formato: new File("/sdcard/Download") (sem conteúdo)
    s = re.sub(
        r'new\s+File\s*\(\s*"/sdcard/Download/?"\s*\)',
        'getExternalFilesDir(null)',
        s,
    )

    # 4. Qualquer string literal solta restante
    s = re.sub(
        r'"\s*/sdcard/Download/?"',
        '(getExternalFilesDir(null).getAbsolutePath() + "/")',
        s,
    )

    # 5. Environment public dir (fallback)
    s = s.replace(
        'Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)',
        'getExternalFilesDir(null)',
    )

    if s != orig:
        backup(sa); write(sa, s)
        print(f"    \033[0;32m✓\033[0m {sa}")
    else:
        print(f"    \033[1;33m·\033[0m {sa} (sem mudança)")

    # Confirma resíduo
    left = [l for l in read(sa).splitlines() if '/sdcard/Download' in l]
    if left:
        print("    \033[0;31m!\033[0m resíduo:")
        for l in left: print(f"      {l.strip()}")

# ============================================================================
# B) TelegramService.java — remove código morto + fix real
# ============================================================================
print("\n[B] TelegramService.java")
for ts in find('TelegramService.java'):
    s = read(ts); orig = s

    # 1. Remove o método configOk morto adicionado pelo script anterior.
    #    Restrito ao corpo conhecido (sem chaves internas) para não afetar outros métodos.
    s = re.sub(
        r'\n\s*private\s+boolean\s+configOk\s*\(\s*\)\s*\{\s*return[^}]*\}\s*\n',
        '\n', s,
    )

    # 2. Fix da checagem — captura os nomes reais das variáveis (token, chatId, etc.)
    def fix_both(m):
        v1, v2 = m.group(1), m.group(2)
        return (
            f'if ({v1} == null || {v1}.isEmpty() || "TOKEN_FALLBACK".equals({v1})\n'
            f'                || {v2} == null || {v2}.isEmpty() || "CHAT_FALLBACK".equals({v2})) {{'
        )
    s = re.sub(
        r'if\s*\(\s*"TOKEN_FALLBACK"\.equals\(\s*(\w+)\s*\)\s*\|\|\s*'
        r'"CHAT_FALLBACK"\.equals\(\s*(\w+)\s*\)\s*\)\s*\{',
        fix_both, s,
    )

    # 3. Casos em que só um dos dois aparece
    s = re.sub(
        r'if\s*\(\s*"TOKEN_FALLBACK"\.equals\(\s*(\w+)\s*\)\s*\)\s*\{',
        r'if (\1 == null || \1.isEmpty() || "TOKEN_FALLBACK".equals(\1)) {',
        s,
    )
    s = re.sub(
        r'if\s*\(\s*"CHAT_FALLBACK"\.equals\(\s*(\w+)\s*\)\s*\)\s*\{',
        r'if (\1 == null || \1.isEmpty() || "CHAT_FALLBACK".equals(\1)) {',
        s,
    )

    # 4. Se por algum motivo ainda houver chamada a configOk(), remove
    s = re.sub(r'\n[^\n]*configOk\(\)[^\n]*', '', s)

    if s != orig:
        backup(ts); write(ts, s)
        print(f"    \033[0;32m✓\033[0m {ts}")
    else:
        print(f"    \033[1;33m·\033[0m {ts} (sem mudança)")

    # Verificações pós-patch
    if 'configOk' in read(ts):
        ERRORS.append(f"configOk ainda em {ts}")
        print("    \033[0;31m!\033[0m configOk ainda presente — revisar manualmente")
    if re.search(r'if\s*\(\s*"TOKEN_FALLBACK"\.equals\(\w+\)\s*\|\|', read(ts)):
        ERRORS.append(f"checagem frágil ainda em {ts}")
        print("    \033[0;31m!\033[0m checagem frágil ainda presente")

print("\n" + "="*60)
if ERRORS:
    print("\033[0;31m[!] resíduos:\033[0m")
    for e in ERRORS: print(f"    - {e}")
else:
    print("\033[0;32m[✓] tudo corrigido\033[0m")
PYEOF

echo
echo "[+] Backup: $BACKUP"
git --no-pager diff --stat 2>/dev/null || true
echo
echo "[i] Verifique com:"
echo "    grep -rn '/sdcard/Download' --include='*.java' ."
echo "    grep -n 'TOKEN_FALLBACK' \$(find . -name TelegramService.java)"
echo "    grep -n 'configOk' \$(find . -name TelegramService.java)  # deve retornar vazio"
