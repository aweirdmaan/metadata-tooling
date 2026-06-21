#!/usr/bin/env bash
# Bring up all three catalog POCs (OMD, DataHub, ODD).
# Each POC has its own setup.sh; this script delegates to whichever you pick.
# All three can run concurrently — host ports are non-overlapping.

set -euo pipefail
cd "$(dirname "$0")"

cat <<HEAD
Three POCs, three catalogs:

  omd      OpenMetadata           UI on :8585  (admin@open-metadata.org / admin)
  datahub  DataHub                UI on :9002  (datahub / datahub)
  odd      Open Data Discovery    UI on :8090  (no auth)

All three coexist without port collisions. Each setup.sh is idempotent.

HEAD

read -rp "Which would you like to bring up? [omd/datahub/odd/all]: " choice
case "$choice" in
  omd)     cd omd     && ./setup.sh ;;
  datahub) cd datahub && ./setup.sh ;;
  odd)     cd odd     && ./setup.sh ;;
  all)
    (cd odd     && ./setup.sh)
    (cd omd     && ./setup.sh)
    (cd datahub && ./setup.sh)
    ;;
  *) echo "unknown choice: $choice"; exit 1 ;;
esac
