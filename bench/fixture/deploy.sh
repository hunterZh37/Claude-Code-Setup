#!/bin/sh
# Deploys the rates service. Needs the carrier key in the environment.
set -e
if [ -z "${CARRIER_API_KEY:-}" ]; then
  echo "error: CARRIER_API_KEY is not set. Export it from the team vault, then re-run." >&2
  exit 1
fi
python3 -m pytest -q
echo "deploying rates service (dry run)"
