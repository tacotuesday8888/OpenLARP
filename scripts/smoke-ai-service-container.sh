#!/usr/bin/env bash
set -euo pipefail

image="${1:-openlarp-ai-ci}"
if [[ ! "$image" =~ ^[A-Za-z0-9][A-Za-z0-9._:/@-]*$ ]]; then
  echo "Usage: scripts/smoke-ai-service-container.sh [SAFE_IMAGE_REFERENCE]" >&2
  exit 2
fi

command -v docker >/dev/null 2>&1 || { echo "docker is required." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }

container_name="openlarp-ai-smoke-$$"
response_file="$(mktemp -t openlarp-ai-response.XXXXXX)"

cleanup() {
  local outcome=$?
  if [[ $outcome -ne 0 ]] && docker inspect "$container_name" >/dev/null 2>&1; then
    docker logs "$container_name" >&2 || true
  fi
  docker rm --force "$container_name" >/dev/null 2>&1 || true
  rm -f "$response_file"
  exit "$outcome"
}
trap cleanup EXIT

docker run \
  --detach \
  --name "$container_name" \
  --publish 127.0.0.1::8080 \
  "$image" >/dev/null

binding="$(docker port "$container_name" 8080/tcp)"
port="${binding##*:}"
if [[ ! "$port" =~ ^[0-9]{1,5}$ ]]; then
  echo "Docker did not publish a valid local service port." >&2
  exit 1
fi
service_origin="http://127.0.0.1:${port}"

health=""
for _ in {1..40}; do
  if health="$(curl --fail --silent --show-error --max-time 2 "${service_origin}/healthz" 2>/dev/null)"; then
    break
  fi
  if [[ "$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)" != "true" ]]; then
    echo "AI service container exited before becoming healthy." >&2
    exit 1
  fi
  sleep 0.25
done
if [[ "$health" != '{"ok":true,"schemaVersion":1,"service":"openlarp-ai"}' ]]; then
  echo "AI service health response failed validation." >&2
  exit 1
fi

not_found_status="$(curl --silent --show-error --max-time 5 --output "$response_file" --write-out '%{http_code}' "${service_origin}/not-a-route")"
if [[ "$not_found_status" != "404" ]]; then
  echo "AI service accepted an unknown route." >&2
  exit 1
fi

invalid_status="$(curl --silent --show-error --max-time 5 --output "$response_file" --write-out '%{http_code}' --header 'content-type: application/json' --data '{}' "${service_origin}/v1/workflows:run")"
if [[ "$invalid_status" != "400" ]]; then
  echo "AI service accepted a malformed workflow request." >&2
  exit 1
fi

echo "PASS private AI service container startup and route smoke"
