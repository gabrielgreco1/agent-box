#!/usr/bin/env bash
# extract-orca-reference.sh - Implementação (F0-3). Esqueleto anterior substituído.
#
# Contrato
#   Entrada : app.asar do Orca instalado (OrcaApp 1.4.219), caminho opcional via --asar.
#   Efeitos : grava docs/rebuild/reference/orca-1.4.219/source/ e tokens/*.json; registra SHA-256 do app.asar no README.
#   Reprodutível: duas execuções geram os mesmos tokens byte a byte.
#   Saída   : exit 0 em sucesso; exit != 0 em falha (1 = versão ou CSS inesperado; 2 = ambiente/ferramenta ausente).
# Uso: scripts/extract-orca-reference.sh [--asar <caminho>] [--help]
#
# Só lê o app.asar: extrai para um diretório temporário com @electron/asar e nunca executa código do Orca.
set -euo pipefail

ORCA_VERSION="1.4.219"
ASAR_TOOL_VERSION="4.3.1"
DEFAULT_ASAR="/Applications/Orca.app/Contents/Resources/app.asar"

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

ASAR="$DEFAULT_ASAR"
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --asar)
    [ -n "${2:-}" ] || { echo "ERRO: --asar exige um caminho" >&2; exit 2; }
    ASAR="$2" ;;
  "") ;;
  *) echo "ERRO: argumento desconhecido: $1 (use --help)" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/rebuild/reference/orca-1.4.219"

[ -f "$ASAR" ] || { echo "ERRO: app.asar não encontrado em $ASAR (instale o Orca $ORCA_VERSION)" >&2; exit 2; }
command -v npx >/dev/null 2>&1 || { echo "ERRO: npx não encontrado (instale Node.js)" >&2; exit 2; }
command -v shasum >/dev/null 2>&1 || { echo "ERRO: shasum não encontrado" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/orca-reference.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

SHA="$(shasum -a 256 "$ASAR" | awk '{print $1}')"
SIZE="$(wc -c < "$ASAR" | tr -d ' ')"
DATE="$(date -u +%Y-%m-%d)"

echo "app.asar: $ASAR ($SIZE bytes, sha256 $SHA)"
npx --yes "@electron/asar@$ASAR_TOOL_VERSION" extract "$ASAR" "$TMP/app"

mkdir -p "$OUT/tokens" "$OUT/source"
python3 -I - "$TMP/app" "$OUT" "$ASAR" "$SHA" "$SIZE" "$DATE" "$ORCA_VERSION" "$ASAR_TOOL_VERSION" <<'PY'
import sys, os, re, json, glob, collections, hashlib

app, out, asar, sha, size, date, want_version, tool_version = sys.argv[1:9]


def die(msg, code=1):
    print("ERRO: " + msg, file=sys.stderr)
    sys.exit(code)


def dump(path, obj):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


pkg = json.load(open(os.path.join(app, "package.json"), encoding="utf-8"))
if pkg.get("version") != want_version:
    die(f"versão do app.asar é {pkg.get('version')}, esperado {want_version}")

# CSS do renderer com o tema: o maior arquivo em out/renderer/assets que define --background e .dark.
assets = os.path.join(app, "out", "renderer", "assets")
cands = []
for f in sorted(glob.glob(os.path.join(assets, "*.css"))):
    s = open(f, encoding="utf-8").read()
    if "--background:" in s and ":root" in s and ".dark" in s:
        cands.append((len(s), f))
if not cands:
    die("CSS com tema (:root e .dark com --background) não encontrado em out/renderer/assets")
css_path = max(cands)[1]
css_rel = os.path.relpath(css_path, app)
css = open(css_path, encoding="utf-8").read()


def parse_blocks(text):
    """Every { } block as (prelude, body, depth). Depth 0 = top level."""
    stack, res, last = [], [], 0
    for i, ch in enumerate(text):
        if ch == "{":
            stack.append((text[last:i].strip(), i + 1))
            last = i + 1
        elif ch == "}":
            prelude, start = stack.pop()
            res.append((prelude, text[start:i], len(stack)))
            last = i + 1
        elif ch == ";":
            last = i + 1
    return res


def leaf_decls(body):
    """Declarations that sit directly in a block (nested blocks skipped)."""
    items, depth, cur = [], 0, []
    for ch in body:
        if ch == "{":
            depth += 1
            cur = []
        elif ch == "}":
            depth -= 1
            cur = []
        elif depth == 0:
            if ch == ";":
                items.append("".join(cur))
                cur = []
            else:
                cur.append(ch)
    if "".join(cur).strip():
        items.append("".join(cur))
    out = []
    for it in items:
        if ":" in it:
            k, v = it.split(":", 1)
            out.append((k.strip(), v.strip()))
    return out


def norm(sel):
    return re.sub(r"\s+", "", sel)


blocks = parse_blocks(css)
light_all, dark_all = collections.defaultdict(list), collections.defaultdict(list)
seen_light = seen_dark = False
font_faces, keyframes, all_decls, preludes = [], [], [], []
for prelude, body, depth in blocks:
    preludes.append(prelude)
    if prelude.startswith("@font-face"):
        d = dict(leaf_decls(body))
        font_faces.append({
            "family": d.get("font-family", "").strip("\"'"),
            "weight": d.get("font-weight", ""),
            "style": d.get("font-style", ""),
        })
        continue
    if prelude.startswith("@keyframes"):
        keyframes.append(prelude.split(None, 1)[1].strip())
        continue
    if prelude.startswith("@"):
        continue
    decls = leaf_decls(body)
    all_decls.extend(decls)
    # Tema pode estar dentro de @layer (ex.: @layer theme { :root,:host {...} }): vale a ordem do documento, como na cascata.
    s = norm(prelude)
    if s in (":root,:host", ":root"):
        seen_light = True
        for k, v in decls:
            if k.startswith("--") and not k.startswith("--tw-"):
                light_all[k].append(v)
    elif s == ".dark":
        seen_dark = True
        for k, v in decls:
            if k.startswith("--") and not k.startswith("--tw-"):
                dark_all[k].append(v)
if not (seen_light and seen_dark):
    die("blocos de tema (:root e .dark) não encontrados no CSS")


SRGB_RE = re.compile(r"^(#|rgba?\(|hsla?\()", re.I)


def pick(values):
    """Tailwind repete cada cor com fallback (hex, color(display-p3 ...), lab(...)) em @supports.
    Vale o último valor sRGB em ordem de documento; sem sRGB, o último valor."""
    srgb = [v for v in values if SRGB_RE.match(v)]
    return srgb[-1] if srgb else values[-1]


light = {k: pick(v) for k, v in light_all.items()}
dark = {k: pick(v) for k, v in dark_all.items()}

COLOR_RE = re.compile(r"^(#|rgba?\(|hsla?\(|oklch\(|oklab\(|color-mix\(|var\(|transparent$|currentcolor$|black$|white$)", re.I)
palette = {k: v for k, v in light.items() if k.startswith("--color-") and COLOR_RE.match(v)}
light_colors = {k: v for k, v in light.items() if COLOR_RE.match(v) and not k.startswith("--color-")}
dark_colors = {k: v for k, v in dark.items() if COLOR_RE.match(v)}
dark_other = {k: v for k, v in dark.items() if not COLOR_RE.match(v)}

# ---- unidades -> px ----
def to_px(value, base_px=16.0):
    m = re.fullmatch(r"(-?(?:\d+\.?\d*|\.\d+))(px|rem|em)?", value.strip())
    if not m:
        return None
    n, unit = float(m.group(1)), m.group(2) or "px"
    px = n * base_px if unit in ("rem", "em") else n
    return round(px, 3)


def abs_px(value):
    """Só px e rem (absolutos). em/% são relativos e ficam de fora das escalas."""
    if not re.fullmatch(r"-?(?:\d+\.?\d*|\.\d+)(?:px|rem)", value.strip()):
        return None
    return to_px(value)


def sorted_unique(vals):
    return sorted(set(vals))


font_sizes = sorted_unique(p for k, v in all_decls if k == "font-size" for p in [abs_px(v)] if p is not None)
line_heights = sorted_unique(p for k, v in all_decls if k == "line-height" for p in [abs_px(v)] if p is not None)
font_weights = sorted_unique(int(v) for k, v in all_decls if k == "font-weight" and v.isdigit())
radius_px = sorted_unique(p for k, v in all_decls if k == "border-radius" for p in [abs_px(v)] if p is not None)

base_spacing = light.get("--spacing", "")
base_spacing_px = to_px(base_spacing) if base_spacing else None
if base_spacing_px is None:
    die("--spacing não encontrado no tema claro (:root)")
SPACING_PREFIX = r"(?:p|px|py|pt|pr|pb|pl|m|mx|my|mt|mr|mb|ml|gap|gap-x|gap-y|space-x|space-y)"
spacing_units = {}
spacing_prefixes = set()
for p in preludes:
    for m in re.finditer(r"\.(" + SPACING_PREFIX + r")-(\d+(?:\\?\.\d+)?)(?![\w\\])", p):
        num = float(m.group(2).replace("\\.", "."))
        spacing_units[m.group(2).replace("\\.", ".")] = round(num * base_spacing_px, 3)
        spacing_prefixes.add(m.group(1))

durations = set()
delays = set()
for k, v in all_decls:
    if k in ("transition-duration", "animation-duration", "--tw-duration"):
        for part in v.split(","):
            part = part.strip()
            m = re.fullmatch(r"(\d+\.?\d*|\.\d+)(ms|s)", part)
            if m:
                durations.add(round(float(m.group(1)) * (1000 if m.group(2) == "s" else 1), 3))
for p in preludes:
    for m in re.finditer(r"\.duration-(\d+)(?![\w\\])", p):
        durations.add(float(m.group(1)))
    for m in re.finditer(r"\.delay-(\d+)(?![\w\\])", p):
        delays.add(float(m.group(1)))
timing = sorted_unique(v for k, v in all_decls if k in ("transition-timing-function", "animation-timing-function") and not v.startswith("var("))

sources = {
    "orca_version": want_version,
    "asar_sha256": sha,
    "css_file": css_rel,
}

colors_obj = dict(sources, **{
    "_nota": "Valores crus do CSS compilado do renderer. 'dark' = bloco .dark; 'light' = :root; var() não resolvido.",
    "dark": dict(sorted(dark_colors.items())),
    "dark_other": dict(sorted(dark_other.items())),
    "light": dict(sorted(light_colors.items())),
    "palette_tailwind": dict(sorted(palette.items())),
})
typo_obj = dict(sources, **{
    "font_families": {k: v for k, v in sorted(light.items()) if k.startswith("--font-") and not k.startswith("--font-weight")},
    "font_weight_vars": {k: v for k, v in sorted(light.items()) if k.startswith("--font-weight")},
    "text_scale": {k: v for k, v in sorted(light.items()) if k.startswith("--text-") or k.startswith("--leading-") or k.startswith("--tracking-")},
    "font_faces": sorted(font_faces, key=lambda d: (d["family"], d["weight"], d["style"])),
    "font_sizes_px_used": font_sizes,
    "line_heights_px_used": line_heights,
    "font_weights_used": font_weights,
})
spacing_obj = dict(sources, **{
    "base": base_spacing,
    "base_px": base_spacing_px,
    "scale_units_px": dict(sorted(spacing_units.items(), key=lambda kv: float(kv[0]))),
    "utility_prefixes": sorted(spacing_prefixes),
    "custom_vars": {k: v for k, v in sorted(light.items()) if k.startswith("--spacing")},
})
radii_obj = dict(sources, **{
    "radius_base": light.get("--radius", ""),
    "radius_base_px": to_px(light.get("--radius", "0px")),
    "radius_vars": {k: v for k, v in sorted(light.items()) if k.startswith("--radius")},
    "border_radius_px_used": radius_px,
})
motion_obj = dict(sources, **{
    "easings": {k: v for k, v in sorted(light.items()) if k.startswith("--ease")},
    "animate_vars": {k: v for k, v in sorted(light.items()) if k.startswith("--animate")},
    "keyframes": sorted(set(keyframes)),
    "durations_ms_used": sorted(durations),
    "delays_ms_used": sorted(delays),
    "timing_functions_used": timing,
})

for name, obj in [("colors", colors_obj), ("typography", typo_obj), ("spacing", spacing_obj), ("radii", radii_obj), ("motion", motion_obj)]:
    dump(os.path.join(out, "tokens", name + ".json"), obj)

# ---- source/index.json: só índice com hash (licença MIT permite copiar trechos; decisão do dono) ----
index_files = []
for f in sorted(glob.glob(os.path.join(assets, "*.css"))):
    data = open(f, "rb").read()
    index_files.append({
        "path": os.path.relpath(f, app),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "tema_escuro": (b"--background:" in data and b".dark" in data),
    })
dump(os.path.join(out, "source", "index.json"), {
    "orca_version": want_version,
    "asar_sha256": sha,
    "files": index_files,
})

css_sha = next(x["sha256"] for x in index_files if x["path"] == css_rel)
readme = f"""# Pacote de referência visual do Orca {want_version}

Gerado por `scripts/extract-orca-reference.sh`. Não editar à mão.

| Campo | Valor |
|---|---|
| Versão do Orca | {want_version} (`package.json` dentro do `app.asar`) |
| Data da extração | {date} (UTC) |
| Caminho do `app.asar` | `{asar}` |
| Tamanho do `app.asar` | {size} bytes |
| SHA-256 do `app.asar` | `{sha}` |
| Ferramenta de extração | `@electron/asar@{tool_version}` (via `npx`) |
| CSS usado para os tokens | `{css_rel}` (sha256 `{css_sha}`) |

## Conteúdo

- `tokens/colors.json`: variáveis do tema escuro (`.dark`) e claro (`:root`), e a escala de cores do Tailwind.
- `tokens/typography.json`: famílias, `@font-face`, escala `--text-*`, tamanhos e pesos usados.
- `tokens/spacing.json`: base `--spacing` e as unidades das utilidades de padding, margin e gap.
- `tokens/radii.json`: `--radius` e os raios usados.
- `tokens/motion.json`: curvas `--ease-*`, animações, durações e atrasos usados.
- `source/index.json`: índice com tamanho e SHA-256 dos CSS do renderer. Os arquivos não são copiados.
- Pendentes de F0-3 (capturas com Gravação de Tela): `screens/`, `crops/` e `manifest.json`. Este script não os gera.

## Como recapturar os tokens

1. Instale o Orca {want_version} em `/Applications/Orca.app`.
2. Rode `scripts/extract-orca-reference.sh` (ou `scripts/extract-orca-reference.sh --asar <caminho>`).
3. O script aborta se a versão do `app.asar` não for {want_version}. Ele só lê o arquivo: nada do Orca é executado.
4. Duas execuções sobre o mesmo `app.asar` geram os mesmos JSON byte a byte. Se o SHA-256 mudar, o diff dos tokens mostra o que mudou no Orca.

Divergências entre estes tokens e `docs/rebuild/spec/02-design-system.md` estão listadas em `docs/evidence/slice0/`.
"""
with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as fh:
    fh.write(readme)

print(f"tokens gravados em {out}/tokens (CSS: {css_rel})")
PY
