#!/usr/bin/env python3
"""Renderiza uma timeline HTML (window.seek(t)) quadro a quadro com Playwright HEADLESS.

  python3 render.py <html> --query "v=A&rm=0" --out out.mp4 [--fps 60] [--slow out_slow.mp4]
  python3 render.py <html> --query "v=A" --stills 0,0.1,0.2 --out sheet.png      # contact sheet de checagem

60 fps, sem motion blur (nenhum tmix), 1440x900. Chromium headless: nenhuma janela e aberta.
Contrato da pagina: window.DUR, window.seek(t) pura, window.ready === true.
"""
import argparse, os, subprocess, sys, io
from playwright.sync_api import sync_playwright

ap = argparse.ArgumentParser()
ap.add_argument('html')
ap.add_argument('--query', default='')
ap.add_argument('--out', required=True)
ap.add_argument('--fps', type=int, default=60)
ap.add_argument('--slow', help='gera tambem versao 4x mais lenta neste caminho')
ap.add_argument('--stills', help='tempos (s) separados por virgula: gera contact sheet PNG em --out')
ap.add_argument('--cols', type=int, default=4)
a = ap.parse_args()

W, H = 1440, 900
url = 'file://' + os.path.abspath(a.html) + ('?' + a.query if a.query else '')

with sync_playwright() as p:
    b = p.chromium.launch(headless=True, args=['--force-color-profile=srgb', '--font-render-hinting=none',
                                               '--allow-file-access-from-files', '--disable-gpu-vsync'])
    pg = b.new_page(viewport={'width': W, 'height': H}, device_scale_factor=1)
    errs = []
    pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.on('console', lambda m: errs.append(m.text) if m.type == 'error' else None)
    pg.goto(url)
    pg.wait_for_function('window.ready===true', timeout=30000)
    dur = pg.evaluate('window.DUR')
    if a.stills:
        from PIL import Image, ImageDraw
        times = [float(x) for x in a.stills.split(',')]
        tw, th = W // 2, H // 2
        rows = (len(times) + a.cols - 1) // a.cols
        sheet = Image.new('RGB', (tw * a.cols, th * rows), (0, 0, 0))
        d = ImageDraw.Draw(sheet)
        for i, t in enumerate(times):
            pg.evaluate(f'seek({t})')
            im = Image.open(io.BytesIO(pg.screenshot(type='png'))).resize((tw, th), Image.LANCZOS)
            x, y = (i % a.cols) * tw, (i // a.cols) * th
            sheet.paste(im, (x, y))
            d.rectangle([x, y, x + 78, y + 16], fill=(0, 0, 0))
            d.text((x + 3, y + 2), f't={t:.3f}s', fill=(255, 220, 80))
        sheet.save(a.out)
    else:
        n = int(round(dur * a.fps))
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', str(a.fps), '-i', '-',
                               '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'slow', '-r', str(a.fps),
                               '-movflags', '+faststart', a.out], stdin=subprocess.PIPE)
        for i in range(n):
            pg.evaluate(f'seek({i / a.fps})')           # sem tmix: quadro i = estado em t = i/fps
            ff.stdin.write(pg.screenshot(type='png'))
        ff.stdin.close(); ff.wait()
        if a.slow:
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', a.out, '-filter:v', 'setpts=4*PTS', '-crf', '24', '-an', a.slow], check=True)
        print(f'{a.out}: {n} quadros @ {a.fps} fps ({dur:.2f}s)')
    b.close()
    if errs:
        print('ERROS DE PAGINA:', *errs, sep='\n  ', file=sys.stderr)
        sys.exit(1)
