FROM mcr.microsoft.com/playwright/python:v1.63.0-noble@sha256:72bd171a9ffc2b4b59532aaa6210e21014d07093120dc25528870c0b840da1f0
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb=2:21.1.12-1ubuntu1.8 openbox=3.6.1-12build5 xdotool=1:3.20160805.1-5build1 \
    && rm -rf /var/lib/apt/lists/*
RUN python -m pip install --no-cache-dir playwright==1.63.0 mss==10.2.0 Pillow==12.3.0
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin racky \
    && mkdir -p /opt/racky /data/profile /data/workspace/downloads \
    && chown -R racky:racky /opt/racky /data
COPY --chown=racky:racky engine.py server.py desktop_browser.py public_http.py capture.py /opt/racky/
USER racky
WORKDIR /opt/racky
ENV PYTHONUNBUFFERED=1
EXPOSE 8765
HEALTHCHECK --interval=15s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/ready', timeout=2)" || exit 1
CMD ["python", "server.py"]
