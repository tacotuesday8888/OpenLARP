#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/deploy-ai-service.sh --project PROJECT --region REGION --service SERVICE --ai-service-account EMAIL --functions-service-account EMAIL [--repository REPOSITORY] [--dry-run]" >&2
}

project=""
region=""
service=""
ai_service_account=""
functions_service_account=""
repository="openlarp"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="${2:-}"; shift 2 ;;
    --region) region="${2:-}"; shift 2 ;;
    --service) service="${2:-}"; shift 2 ;;
    --ai-service-account) ai_service_account="${2:-}"; shift 2 ;;
    --functions-service-account) functions_service_account="${2:-}"; shift 2 ;;
    --repository) repository="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) usage; exit 2 ;;
  esac
done

if [[ -z "$project" || -z "$region" || -z "$service" || -z "$ai_service_account" || -z "$functions_service_account" ]]; then
  usage
  exit 2
fi
if [[ ! "$project" =~ ^[a-z][a-z0-9-]{4,61}[a-z0-9]$ ]]; then
  echo "Invalid Google Cloud project ID." >&2
  exit 2
fi
if [[ ! "$region" =~ ^[a-z][a-z0-9-]{1,62}$ || ! "$service" =~ ^[a-z][a-z0-9-]{0,47}[a-z0-9]$ ]]; then
  echo "Invalid Cloud Run region or service name." >&2
  exit 2
fi
if [[ ! "$repository" =~ ^[a-z][a-z0-9._-]{0,62}$ ]]; then
  echo "Invalid Artifact Registry repository name." >&2
  exit 2
fi
for identity in "$ai_service_account" "$functions_service_account"; do
  if [[ ! "$identity" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.gserviceaccount\.com$ ]]; then
    echo "Invalid service account email." >&2
    exit 2
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
revision="$(git -C "$repo_root" rev-parse --short=12 HEAD)"
image="${region}-docker.pkg.dev/${project}/${repository}/${service}:${revision}"

run() {
  if [[ "$dry_run" == true ]]; then
    printf 'DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

if [[ "$dry_run" == false ]]; then
  command -v gcloud >/dev/null 2>&1 || { echo "gcloud is required." >&2; exit 1; }
  if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    echo "Refusing to deploy from a dirty worktree." >&2
    exit 1
  fi
fi

run gcloud artifacts repositories describe "$repository" \
  --project "$project" \
  --location "$region" \
  --format 'value(name)'
run gcloud builds submit "$repo_root" \
  --project "$project" \
  --config "$repo_root/backend/ai-service/cloudbuild.yaml" \
  --substitutions "_IMAGE=${image}"
run gcloud run deploy "$service" \
  --project "$project" \
  --region "$region" \
  --image "$image" \
  --service-account "$ai_service_account" \
  --no-allow-unauthenticated \
  --ingress all \
  --port 8080 \
  --cpu 1 \
  --memory 512Mi \
  --timeout 60 \
  --min 0 \
  --max 5 \
  --update-env-vars 'OPENLARP_ENABLE_LIVE_AI=true,OPENLARP_AI_PROVIDER=vertex-ai,OPENLARP_VERTEX_LOCATION=global'
run gcloud run services add-iam-policy-binding "$service" \
  --project "$project" \
  --region "$region" \
  --member "serviceAccount:${functions_service_account}" \
  --role roles/run.invoker

if [[ "$dry_run" == true ]]; then
  service_url="https://SERVICE_URL_FROM_CLOUD_RUN"
else
  service_url="$(gcloud run services describe "$service" --project "$project" --region "$region" --format 'value(status.url)')"
  [[ "$service_url" == https://* ]] || { echo "Cloud Run did not return a valid HTTPS service URL." >&2; exit 1; }
fi

echo "Deployment commands completed for ${service} at ${service_url}."
echo "Next: set OPENLARP_AI_SERVICE_URL on the Firebase Functions runtime to ${service_url}."
echo "Next: set OPENLARP_ENABLE_LIVE_AI=true plus explicit provider pricing and daily budget on Functions."
echo "Next: write a short-lived _serverConfig/aiRuntimePolicy document, enable one workflow, and run scripts/live-ai-smoke.sh --service-url ${service_url} --require-live."
echo "Rollback: set the runtime policy enabled=false first; then restore the prior Cloud Run revision if needed."
