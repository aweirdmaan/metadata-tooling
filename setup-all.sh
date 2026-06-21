#!/usr/bin/env bash
# Bring up all three catalog POCs (OMD, DataHub, ODD) end-to-end.
# Each POC has its own setup.sh; this script runs them in order with port
# notes so you can pick which to focus on.
#
# Note: the three stacks compete for ports (9200 collides between OMD's ES
# and DataHub's OpenSearch). Run them one at a time unless you've remapped.

set -euo pipefail
cd "$(dirname "$0")"

cat <<HEAD
Three POCs, three catalogs:

  omd      OpenMetadata     UI on :8585
  datahub  DataHub          UI on :9002
  odd      Open Data Discovery   UI on :8090

Port notes:
  - OMD's elasticsearch and DataHub's opensearch both bind :9200 — only one at a time.
  - Each setup.sh is idempotent; re-running is safe.

HEAD

read -rp "Which would you like to bring up? [omd/datahub/odd/all]: " choice
case "$choice" in
  omd)     cd omd     && ./setup.sh ;;
  datahub) cd datahub && ./setup.sh ;;
  odd)     cd odd     && ./setup.sh ;;
  all)
    (cd odd     && ./setup.sh)
    (cd omd     && ./setup.sh)
    echo
    echo "Skipping DataHub — its OpenSearch will collide with OMD's ES on :9200."
    echo "Stop OMD's elasticsearch first if you want DataHub up too:"
    echo "  docker stop openmetadata_elasticsearch && cd datahub && ./setup.sh"
    ;;
  *) echo "unknown choice: $choice"; exit 1 ;;
esac
