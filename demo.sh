#!/bin/bash
# Arranca SafeLink contra el backend REAL, sin mocks.
#   ./demo.sh          → deja todo listo y la app corriendo en el teléfono
#
# Importante: build DEBUG a propósito. En release la app rechaza http:// y se
# vuelve al modo simulado SIN avisar (lib/datos/url_api.dart). Para una demo por
# adb reverse, que va por http, tiene que ser debug.
set -e
export PATH="$HOME/.local/node/bin:/Applications/Postgres.app/Contents/Versions/latest/bin:$HOME/Library/Android/sdk/platform-tools:$PATH"
cd "$(dirname "$0")"

echo "1/4 · Postgres"
pg_isready -q -p 5432 || { echo "   ✗ Postgres no responde: abre Postgres.app y dale a Start"; exit 1; }
echo "   ✓ corriendo"

echo "2/4 · API"
if curl -s --max-time 3 http://127.0.0.1:3000/health | grep -q '"ok"'; then
  echo "   ✓ ya estaba arriba"
else
  (cd backend && nohup npm run dev > /tmp/safelink-api.log 2>&1 &)
  for i in $(seq 1 30); do
    sleep 1
    curl -s --max-time 2 http://127.0.0.1:3000/health | grep -q '"ok"' && break
  done
  curl -s --max-time 3 http://127.0.0.1:3000/health | grep -q '"ok"' \
    && echo "   ✓ levantada (log en /tmp/safelink-api.log)" \
    || { echo "   ✗ no arrancó; mira /tmp/safelink-api.log"; exit 1; }
fi

echo "3/4 · Teléfono"
adb devices | grep -qw device || { echo "   ✗ ninguno conectado y autorizado"; exit 1; }
adb reverse tcp:3000 tcp:3000
echo "   ✓ el teléfono ve la API en su propio 127.0.0.1:3000"

echo "4/4 · App (debug, contra el backend real)"
flutter run --debug --dart-define=API_URL=http://127.0.0.1:3000/api/v1
