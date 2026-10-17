#!/bin/bash
# Renderiza todos os prototipos em HEADLESS, 60 fps, sem motion blur -> docs/evidence/motion/<momento>/
# uso: design/motion/prototypes/render_all.sh   (requer ffmpeg e playwright para python)
set -e
cd "$(dirname "$0")"
EV=../../../docs/evidence/motion
r() { # momento variante rm
  local m=$1 v=$2 rm=$3 n="$2"
  if [ "$rm" = 1 ]; then n="$2-rm"; fi
  mkdir -p $EV/$m
  python3 render.py $m/index.html --query "v=$v&rm=$rm" --out $EV/$m/$n.mp4 --slow $EV/$m/$n-slow4x.mp4
}
for v in A B C; do r M-101-dialog $v 0; r M-501-launch $v 0; done
r M-101-dialog A 1; r M-501-launch A 1
for v in A B; do r M-108-panel $v 0; done
r M-108-panel A 1
r M-109-settings A 0
r M-109-settings A 1
