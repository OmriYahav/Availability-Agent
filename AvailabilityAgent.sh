#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

HOSTS_FILE="${HOSTS_FILE:-./hosts}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-5}"
PING_COUNT="${PING_COUNT:-1}"
PING_TIMEOUT_SECONDS="${PING_TIMEOUT_SECONDS:-2}"
PING_RETRIES="${PING_RETRIES:-3}"
INFLUX_URL="${INFLUX_URL:-http://influxdb:8086}"
INFLUX_DB="${INFLUX_DB:-hosts_metrics}"
INFLUX_MEASUREMENT="${INFLUX_MEASUREMENT:-availability_test}"

running=true

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

on_signal() {
  log "Received shutdown signal, stopping agent loop..."
  running=false
}

trap on_signal SIGINT SIGTERM

require_binary() {
  local binary="$1"
  if ! command -v "$binary" >/dev/null 2>&1; then
    log "ERROR: Required binary '$binary' is not installed or not in PATH."
    exit 1
  fi
}

validate_env() {
  local required=(INFLUX_URL INFLUX_DB)
  for name in "${required[@]}"; do
    if [[ -z "${!name:-}" ]]; then
      log "ERROR: Environment variable $name must be set."
      exit 1
    fi
  done

  if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || (( INTERVAL_SECONDS < 1 )); then
    log "ERROR: INTERVAL_SECONDS must be an integer >= 1."
    exit 1
  fi

  if ! [[ "$PING_COUNT" =~ ^[0-9]+$ ]] || (( PING_COUNT < 1 )); then
    log "ERROR: PING_COUNT must be an integer >= 1."
    exit 1
  fi

  if ! [[ "$PING_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( PING_TIMEOUT_SECONDS < 1 )); then
    log "ERROR: PING_TIMEOUT_SECONDS must be an integer >= 1."
    exit 1
  fi

  if ! [[ "$PING_RETRIES" =~ ^[0-9]+$ ]] || (( PING_RETRIES < 1 )); then
    log "ERROR: PING_RETRIES must be an integer >= 1."
    exit 1
  fi
}

curl_auth_args=()
if [[ -n "${INFLUX_USER:-}" || -n "${INFLUX_PASS:-}" ]]; then
  curl_auth_args=(-u "${INFLUX_USER:-}:${INFLUX_PASS:-}")
fi

wait_for_influx() {
  local max_attempts="${INFLUX_READY_MAX_ATTEMPTS:-30}"
  local delay_seconds="${INFLUX_READY_DELAY_SECONDS:-2}"
  local ping_url="${INFLUX_URL%/}/ping"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if curl -fsS "${curl_auth_args[@]}" "$ping_url" >/dev/null 2>&1; then
      log "InfluxDB is ready at $INFLUX_URL"
      return 0
    fi
    log "Waiting for InfluxDB readiness (attempt $attempt/$max_attempts)..."
    sleep "$delay_seconds"
  done

  log "ERROR: InfluxDB did not become ready in time at $INFLUX_URL"
  exit 1
}

parse_latency_ms() {
  local ping_output="$1"
  awk 'match($0, /time=([0-9]+(\.[0-9]+)?)/, m) { print m[1]; exit }' <<<"$ping_output"
}

check_host() {
  local host="$1"
  local attempt output latency

  for ((attempt = 1; attempt <= PING_RETRIES; attempt++)); do
    if output="$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT_SECONDS" "$host" 2>/dev/null)"; then
      latency="$(parse_latency_ms "$output")"
      if [[ -n "$latency" ]]; then
        echo "1|$latency"
        return 0
      fi
    fi

    if (( attempt < PING_RETRIES )); then
      sleep 1
    fi
  done

  echo "0|0"
}

write_metric() {
  local host="$1"
  local is_up="$2"
  local latency_ms="$3"
  local escaped_host
  local timestamp
  local url="${INFLUX_URL%/}/write?db=${INFLUX_DB}"

  escaped_host="${host//,/\\,}"
  escaped_host="${escaped_host// /\\ }"
  timestamp="$(date +%s%N)"

  local line="${INFLUX_MEASUREMENT},host=${escaped_host} status=${is_up}i,latency_ms=${latency_ms} ${timestamp}"

  curl -fsS "${curl_auth_args[@]}" -X POST "$url" --data-binary "$line" >/dev/null
}

main() {
  require_binary ping
  require_binary curl
  validate_env

  if [[ ! -f "$HOSTS_FILE" ]]; then
    log "ERROR: Hosts file '$HOSTS_FILE' does not exist."
    exit 1
  fi

  wait_for_influx
  log "Monitoring hosts from $HOSTS_FILE every ${INTERVAL_SECONDS}s"

  while [[ "$running" == true ]]; do
    while IFS= read -r host || [[ -n "$host" ]]; do
      host="${host%%#*}"
      host="${host%$'\r'}"
      host="${host##+([[:space:]])}"
      host="${host%%+([[:space:]])}"
      [[ -z "$host" ]] && continue

      local result status latency
      result="$(check_host "$host")"
      status="${result%%|*}"
      latency="${result##*|}"

      if write_metric "$host" "$status" "$latency"; then
        log "host=$host status=$status latency_ms=$latency"
      else
        log "WARN: Failed to write metrics for host '$host'"
      fi
    done <"$HOSTS_FILE"

    sleep "$INTERVAL_SECONDS"
  done

  log "Agent stopped."
}

# Enable extended globbing for whitespace trimming
shopt -s extglob
main "$@"
