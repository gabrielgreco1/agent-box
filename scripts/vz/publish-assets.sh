#!/usr/bin/env bash
# publish-assets.sh - IMPRIME os comandos para publicar os arquivos do runtime sem Docker. Não executa nenhum deles.
#
# Contrato
#   Entrada : <OUT>/vz-manifest.json e os arquivos ao lado dele (scripts/vz/fetch-kernel.sh + scripts/vz/build-image.sh).
#             Env: RACKY_VZ_OUT (padrão build/vz-assets), RACKY_VZ_REPO (padrão OWNER/racky-assets), RACKY_VZ_TAG (padrão vz-<versão do manifesto>).
#   Saída   : na tela, os comandos `gh release create` / `gh release upload` (kernel, vminit, imagem, config e fonte do kernel) e como
#             atualizar runtime/vz-manifest.json com as URLs e os sha256 reais; e a alternativa por ghcr (`crane`/`oras`) para as imagens.
#   Efeitos : NENHUM. Publicar é decisão do dono: confira os arquivos, o repositório de destino e a licença (o kernel é GPL-2.0:
#             publique vmlinux.config e KERNEL-SOURCE.txt junto) e rode os comandos você mesmo.
# Uso: scripts/vz/publish-assets.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${RACKY_VZ_OUT:-$ROOT/build/vz-assets}"
REPO="${RACKY_VZ_REPO:-OWNER/racky-assets}"
case "${1:-}" in -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
[ -f "$OUT/vz-manifest.json" ] || { echo "faltam os assets em $OUT: rode scripts/vz/fetch-kernel.sh e scripts/vz/build-image.sh" >&2; exit 1; }
VERSION="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$OUT/vz-manifest.json")"
TAG="${RACKY_VZ_TAG:-vz-$VERSION}"

cat <<EOF
# ---------------------------------------------------------------------------------------------------------
# NADA DISTO FOI EXECUTADO. Leia, ajuste o repositório (RACKY_VZ_REPO) e rode por sua conta.
# Arquivos em: $OUT
# ---------------------------------------------------------------------------------------------------------

# 1. Release do GitHub com os arquivos (o app baixa por URL + sha256; o repositório pode ser público):
gh release create "$TAG" --repo "$REPO" --title "Racky computer runtime $VERSION" \\
  --notes "Kernel (GPL-2.0, source: see KERNEL-SOURCE.txt), vminit (apple/containerization) and the racky-computer image for the built-in computer runtime." \\
  "$OUT/vmlinux" "$OUT/vmlinux.config" "$OUT/KERNEL-SOURCE.txt" "$OUT/vminit.oci.tar" "$OUT/computer.oci.tar"

# 2. URLs resultantes (as que vão para runtime/vz-manifest.json):
#    https://github.com/$REPO/releases/download/$TAG/vmlinux
#    https://github.com/$REPO/releases/download/$TAG/vminit.oci.tar
#    https://github.com/$REPO/releases/download/$TAG/computer.oci.tar

# 3. Atualizar o manifesto embutido (sha256 e tamanho vêm do manifesto local gerado por build-image.sh):
python3 -I - "$OUT/vz-manifest.json" "$ROOT/runtime/vz-manifest.json" "https://github.com/$REPO/releases/download/$TAG" <<'PY'
import json, sys
local, baked, base = sys.argv[1:4]
manifest = json.load(open(local))
for name, spec in manifest.items():
    if isinstance(spec, dict) and "url" in spec:
        spec["url"] = base + "/" + spec["url"]
json.dump(manifest, open(baked, "w"), indent=2)
open(baked, "a").write("\n")
PY
git diff runtime/vz-manifest.json   # confira; commite quando os links responderem

# 4. Opcional: espelhar as IMAGENS no GHCR (o app de hoje baixa ARQUIVOS por URL; o registro serve a quem prefira \`docker pull\`/skopeo):
#    echo "\$GITHUB_TOKEN" | skopeo login ghcr.io -u <usuario> --password-stdin     # token com write:packages
#    skopeo copy oci-archive:"$OUT/computer.oci.tar" docker://ghcr.io/$REPO/racky-computer:$VERSION
#    Consumir direto do registro exigiria trocar VZAssetStore por ImageStore.pull (ver docs/rebuild/vz-runtime.md, "O que falta").

# 5. Depois de publicar: abra o app num Mac limpo (sem RACKY_VZ_MANIFEST), reserve um computador e confira
#    "Downloading the computer runtime (X of Y MB)…" na linha do computador.
EOF
