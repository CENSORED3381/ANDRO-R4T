#!/usr/bin/env bash
# fix-andro-5.sh — corrige a linha malformada em .github/workflows/build.yml
set -euo pipefail

WF=".github/workflows/build.yml"
if [ ! -f "$WF" ]; then
    echo "❌ $WF não encontrado. Rode na raiz do repositório."
    exit 1
fi

BACKUP=".fix-backup-5-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
cp "$WF" "$BACKUP/build.yml"
echo "[+] Backup: $BACKUP/build.yml"
echo

python3 - "$WF" <<'PYEOF'
import sys, re

wf = sys.argv[1]
s = open(wf, encoding='utf-8').read()
orig = s

# 1) Substituições diretas (cobrem as variações exatas que vimos)
direct = [
    ('./gradlew assembleDebug \\ || exit 1', './gradlew assembleDebug \\'),
    ('./gradlew assembleDebug \\|| exit 1',  './gradlew assembleDebug \\'),
    ('./gradlew assembleDebug || exit 1',    './gradlew assembleDebug \\'),
]
for old, new in direct:
    if old in s:
        s = s.replace(old, new)
        print(f"  ✓ substituição direta aplicada")

# 2) Regex de segurança (caso haja espaçamento atípico)
before = s
s = re.sub(r'(\./gradlew\s+assembleDebug)\s*\\\s*\|\|\s*exit\s+1', r'\1 \\', s)
if s != before:
    print("  ✓ regex de segurança aplicou")

# 3) Salvar
if s != orig:
    open(wf, 'w', encoding='utf-8').write(s)
    print("  ✓ arquivo salvo")
else:
    print("  · nenhuma alteração (já está correto?)")

# 4) Diagnóstico da região gradle
print("\n[i] Estado atual da região do gradle:")
for i, line in enumerate(s.split('\n'), 1):
    if 'assembleDebug' in line or ('gradlew' in line and 'run:' not in line):
        for j in range(i, min(i + 6, len(s.split('\n')) + 1)):
            l = s.split('\n')[j - 1]
            print(f"  {j:>3}: {l}")
            if l and not l.rstrip().endswith('\\') and j > i:
                break
        break

# 5) Aviso se o step não falhará no build com erro
print()
if 'set +e' in s and 'exit $exit_code' not in s and 'exit $?' not in s:
    print("[!] AVISO: 'set +e' presente, mas sem 'exit $exit_code'.")
    print("    O step passará mesmo se o gradle falhar.")
    print("    Para corrigir, adicione ao final do bloco 'run':")
    print("        exit_code=$?")
    print("        ...
    print("        exit $exit_code")
else:
    print("[i] Nenhum aviso de exit handling.")
PYEOF

echo
echo "[i] Verificação final:"
echo "---"
sed -n '/assembleDebug/,+6p' "$WF"
echo "---"
