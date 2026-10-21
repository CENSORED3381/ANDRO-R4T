#!/usr/bin/env bash
set -euo pipefail
WF=".github/workflows/build.yml"
[ -f "$WF" ] || { echo "ERRO: $WF não encontrado"; exit 1; }

BK=".fix-backup-exit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"; cp "$WF" "$BK/build.yml"
echo "[+] Backup: $BK/build.yml"

python3 - "$WF" <<'PYEOF'
import sys, re

wf = sys.argv[1]
lines = open(wf, encoding='utf-8').read().split('\n')
orig = list(lines)

# 1) Encontrar o bloco "Build Debug APK"
name_idx = next((i for i, l in enumerate(lines)
                 if re.search(r'name:\s*Build Debug APK', l)), None)
if name_idx is None:
    print("  ✗ step 'Build Debug APK' nao encontrado"); sys.exit(1)

# 2) Encontrar o "run: |" deste step
run_idx = next((i for i in range(name_idx, len(lines))
                if re.match(r'^\s*run:\s*\|\s*$', lines[i])), None)
if run_idx is None:
    print("  ✗ 'run: |' nao encontrado"); sys.exit(1)

run_indent = len(lines[run_idx]) - len(lines[run_idx].lstrip())

# 3) Fim do bloco run = próxima linha com indent <= run_indent
run_end = len(lines)
for i in range(run_idx + 1, len(lines)):
    s = lines[i].rstrip()
    if s and (len(lines[i]) - len(lines[i].lstrip())) <= run_indent:
        run_end = i
        break

# 4) Localizar a linha do gradle e sua linha de redirecionamento (fim)
gradle_idx = None
for i in range(run_idx + 1, run_end):
    if './gradlew assembleDebug' in lines[i]:
        # Pula até a linha que não termina em \
        j = i
        while j < run_end - 1 and lines[j].rstrip().endswith('\\'):
            j += 1
        gradle_idx = j
        break

if gradle_idx is None:
    print("  ✗ linha 'gradlew assembleDebug' nao encontrada no step"); sys.exit(1)

content_indent = ' ' * (run_indent + 2)

# 5) Adicionar 'exit_code=$?' após o gradle (se já não houver)
block_after = '\n'.join(lines[gradle_idx + 1:gradle_idx + 3])
if 'exit_code=' not in block_after:
    lines.insert(gradle_idx + 1, content_indent + 'exit_code=$?')
    run_end += 1
    print("  ✓ 'exit_code=$?' adicionado apos o gradle")
else:
    print("  · 'exit_code=$?' ja presente")

# 6) Remover 'set -e' solto antes do fim (opcional mas limpa o fluxo)
# Só remove se for a ÚLTIMA linha não-vazia antes do fim do bloco
for i in range(run_end - 1, run_idx, -1):
    if lines[i].strip() == 'set -e':
        del lines[i]
        run_end -= 1
        print("  ✓ 'set -e' redundante removido")
        break
    if lines[i].strip():
        break

# 7) Adicionar 'exit $exit_code' antes do fim do bloco (se não houver)
block_text = '\n'.join(lines[run_idx:run_end])
if 'exit $exit_code' not in block_text:
    # Remover linhas vazias no fim
    while run_end > run_idx + 1 and not lines[run_end - 1].strip():
        run_end -= 1
    lines.insert(run_end, content_indent + 'exit $exit_code')
    print("  ✓ 'exit $exit_code' adicionado no fim do bloco")
else:
    print("  · 'exit $exit_code' ja presente")

# 8) Gravar
if lines != orig:
    open(wf, 'w', encoding='utf-8').write('\n'.join(lines))
    print("  ✓ arquivo salvo")
else:
    print("  · nenhuma alteracao (ja estava correto)")

# 9) Mostrar o bloco final
print("\n[i] Bloco final do step 'Build Debug APK':")
for i, l in enumerate(lines, 1):
    if re.search(r'name:\s*Build Debug APK', l):
        for j in range(i - 1, min(i + 30, len(lines))):
            print(f"  {j+1:>3}: {lines[j]}")
        break
PYEOF

echo
echo "[i] Validando YAML..."
python3 -c "import yaml; yaml.safe_load(open('$WF')); print('  ✓ YAML OK')" 2>/dev/null || echo "  (pyyaml ausente)"
