FROM python:3.12-alpine
WORKDIR /app
COPY beeb_sync_core.py /app/
COPY standalone/beeb_sync_server.py /app/standalone/
ENV BEEB_SYNC_PORT=8765 BEEB_SYNC_DATA=/data/beeb_sync.json
VOLUME /data
EXPOSE 8765
USER nobody
CMD ["python3", "/app/standalone/beeb_sync_server.py"]
