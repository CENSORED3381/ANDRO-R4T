#!/usr/bin/env bash
# fix-andro-5.sh (v2) — corrige a linha malformada em .github/workflows/build.yml
set -euo pipefail

WF=".github/workflows/build.yml"
[ -f "$WF" ] || { echo "ERRO: $WF não encontrado"; exit 1; }

BK=".fix-backup-5-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
cp "$WF" "$BK/build.yml"
echo "[+] Backup: $BK/build.yml"
echo

python3 - "$WF" <<'PYEOF'
import sys

wf = sys.argv[1]
s = open(wf, encoding='utf-8').read()
orig = s

variants = [
    './gradlew assembleDebug \\ || exit 1',
    './gradlew assembleDebug \\|| exit 1',
    './gradlew assembleDebug  || exit 1',
    './gradlew assembleDebug || exit 1',
]
applied = False
for old in variants:
    if old in s:
        s = s.replace(old, './gradlew assembleDebug \\')
        print("  OK: substituicao aplicada")
        applied = True

if not applied:
    print("  . nada a mudar (linha ja correta ou formato diferente)")

if s != orig:
    open(wf, 'w', encoding='utf-8').write(s)
    print("  OK: arquivo salvo")
else:
    print("  . arquivo nao modificado")

print()
print("[i] Estado atual da regiao do gradle:")
lines = s.split('\n')
for i, line in enumerate(lines, 1):
    if 'assembleDebug' in line:
        for j in range(i, min(i + 6, len(lines) + 1)):
            print("  {:>3}: {}".format(j, lines[j-1]))
        break
PYEOF

echo
echo "[i] Verificacao final:"
grep -n 'assembleDebug' "$WF" || true
echo
if grep -qE 'assembleDebug.*\|\|.*exit' "$WF"; then
    echo "[!] ainda tem '|| exit' na mesma linha do assembleDebug"
    exit 2
fi
echo "[OK] linha corrigida"
