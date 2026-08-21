#!/usr/bin/env bash
# ============================================================================
#  solar-watchdog - sonda end-to-end pentru stack-ul solar-monitor
# ============================================================================
# De ce exista: pe 2026-08-19 un restart de firewalld a taiat traficul intre
# containere. Collector-ul era perfect sanatos (deci nu avea de ce sa alerteze),
# dar Caddy dadea 502 si aplicatia de telefon a stat pe "astept date" ~13 ore
# fara ca nimeni sa afle. Alertele din collector.py acopera invertorul; asta
# acopera *lantul complet* pana la ce vede telefonul.
#
# Verifica exact ce vede aplicatia mobila:
#   telefon -> Caddy (9443, TLS intern) -> api:8000 -> InfluxDB -> collector
# Esec = HTTP != 200, JSON invalid, sau date mai vechi de MAX_AGE_S.
#
# Instalare: vezi deploy/README-firewalld.md. Ruleaza din solar-watchdog.timer.
set -uo pipefail

PROBE_HOST="${PROBE_HOST:-vyra.go.ro}"
PROBE_PORT="${PROBE_PORT:-9443}"
PROBE_PATH="${PROBE_PATH:-/solar/latest}"
MAX_AGE_S="${MAX_AGE_S:-180}"        # datele mai vechi de atat = stack blocat
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"
ENV_FILE="${ENV_FILE:-/opt/solar-monitor/.env}"
STATE_DIR="${STATE_DIR:-/var/lib/solar-watchdog}"
STATE_FILE="$STATE_DIR/consecutive_failures"
# Re-alerta la fiecare N esecuri consecutive (timer la 15 min => 4 = o data pe ora).
REALERT_EVERY="${REALERT_EVERY:-4}"

NTFY_TOPIC="$(sed -n 's/^NTFY_TOPIC=//p' "$ENV_FILE" 2>/dev/null | head -n1)"
NTFY_TOPIC="${NTFY_TOPIC:-Alerta_6Kw}"
# Din host, nu din reteaua Docker: portul publicat de containerul ntfy.
NTFY_BASE="${NTFY_BASE:-http://127.0.0.1:8088}"

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo 0 > "$STATE_FILE"
fails="$(cat "$STATE_FILE" 2>/dev/null)"
[[ "$fails" =~ ^[0-9]+$ ]] || fails=0

push() {  # push <titlu> <prioritate> <tag> <mesaj>
  curl -fsS -m 10 \
    -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
    -d "$4" "$NTFY_BASE/$NTFY_TOPIC" >/dev/null 2>&1 \
    || echo "AVERTISMENT: push ntfy esuat ($NTFY_BASE/$NTFY_TOPIC)" >&2
}

url="https://${PROBE_HOST}:${PROBE_PORT}${PROBE_PATH}"
body="$(curl -sk -m "$CURL_TIMEOUT" \
          --resolve "${PROBE_HOST}:${PROBE_PORT}:127.0.0.1" \
          -w '\n%{http_code}' "$url" 2>/dev/null)"
code="$(printf '%s' "$body" | tail -n1)"
json="$(printf '%s' "$body" | sed '$d')"

reason=""
if [ "$code" != "200" ]; then
  reason="HTTP ${code:-fara raspuns} de la ${PROBE_PATH}"
else
  reason="$(printf '%s' "$json" | MAX_AGE_S="$MAX_AGE_S" python3 -c '
import sys, os, json, datetime

max_age = float(os.environ.get("MAX_AGE_S", "180"))
try:
    d = json.load(sys.stdin)
except Exception as exc:
    print("JSON invalid: %s" % exc)
    sys.exit(0)

ts = d.get("timestamp")
if not ts:
    print("lipseste campul timestamp")
    sys.exit(0)

try:
    age = (datetime.datetime.now(datetime.timezone.utc)
           - datetime.datetime.fromisoformat(ts)).total_seconds()
except Exception as exc:
    print("timestamp neinterpretabil (%s): %s" % (ts, exc))
    sys.exit(0)

if age > max_age:
    print("date vechi de %.0fs (prag %.0fs)" % (age, max_age))
' 2>&1)"
fi

if [ -z "$reason" ]; then
  # --- OK ---
  if [ "$fails" -gt 0 ]; then
    echo "Stack revenit la normal dupa $fails verificari esuate."
    push "Solar: revenit la normal" "default" "white_check_mark" \
         "Aplicatia primeste date din nou. ${PROBE_PATH} raspunde 200 cu date proaspete."
  fi
  echo 0 > "$STATE_FILE"
  exit 0
fi

# --- ESEC ---
fails=$((fails + 1))
echo "$fails" > "$STATE_FILE"
echo "ESEC #$fails: $reason ($url)" >&2

if [ "$fails" -eq 1 ] || [ $((fails % REALERT_EVERY)) -eq 0 ]; then
  push "Solar: aplicatia nu primeste date" "urgent" "warning,satellite" \
"Sonda end-to-end a esuat de $fails ori consecutiv.
Motiv: $reason

De verificat pe server, in ordine:
1) firewall-cmd --get-active-zones   (br-solar trebuie sa fie in zona docker)
2) docker compose ps
3) docker compose logs --tail=50 api caddy"
fi
exit 1
