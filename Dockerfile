FROM python:3.13 AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.13-slim AS runtime
RUN groupadd -r agent && useradd -r -g agent -d /app -s /sbin/nologin agent
WORKDIR /app
COPY --from=builder /install /usr/local
COPY --chown=agent:agent travel_agent.py .
USER agent
ENV PORT=8080 PYTHONUNBUFFERED=1
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT}/.well-known/agent-card.json')" || exit 1
CMD ["python", "travel_agent.py"]
