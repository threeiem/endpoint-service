#! /bin/bash
#  upgrade CircleCI builtin gcloud tools, and set it up
#
# The following ENV vars must be set before calling this script:
#
#   GCLOUD_EMAIL           # user-id for circle to authenticate to google cloud
#   GCLOUD_KEY             # base64 encoded key
#   CLUSTER_ID             # (DEPRECATED) this will set the cluster to connect to (when not used it connects to all of them)
#   CLUSTER_DEFAULT        # sets default cluster (if using CLUSTER_ID then this is set to the specified cluster)

set -eou pipefail

parent_dir="$(cd "$(dirname "$0")" && pwd)"
"${parent_dir}/install-pants.sh"

gcloud=$(command -v gcloud)
kubectl=$(command -v kubectl)
pants=$(command -v pants)

PROJECTS=("pantheon-internal" "pantheon-sandbox" "pantheon-dmz" "pantheon-build" "pantheon-cos-provision")
CLUSTER_DEFAULT=${CLUSTER_DEFAULT:-"general-01"}
CLUSTER_ID=${CLUSTER_ID:-}
GCLOUD_EMAIL=${GCLOUD_EMAIL:-}
GCLOUD_KEY=${GCLOUD_KEY:-}

if [[ -z "$GCLOUD_EMAIL" ]]; then
  echo "GCLOUD_EMAIL is required"
  exit 1
fi

if [[ -z "$GCLOUD_KEY" ]]; then
  echo "GCLOUD_KEY is required"
  exit 1
fi

echo "$GCLOUD_KEY" | base64 --decode > gcloud.json
$gcloud auth activate-service-account "$GCLOUD_EMAIL" --key-file gcloud.json

sshkey="$HOME/.ssh/google_compute_engine"
if [[ ! -f "$sshkey" ]] ; then
  ssh-keygen -f "$sshkey" -N ""
fi

if [[ -n "$CLUSTER_ID" ]] ; then
	CLUSTER_DEFAULT="$CLUSTER_ID"
fi

for PROJ in "${PROJECTS[@]}"; do
  echo "Fetching credentails for project $PROJ"
  $pants gke pull-creds --project "$PROJ"

  DEFAULT_CLUSTER_DATA=$(gcloud container clusters list --format json --project "$PROJ" | jq --arg cluster "$CLUSTER_DEFAULT" -r '.[] | select(.name==$cluster)')

  if [[ -n "$DEFAULT_CLUSTER_DATA" ]]; then
    # this means that DEFAULT_CLUSTER is in this project and its information is in $CLUSTER_DATA
    DEFAULT_CLUSTER_PROJECT=$PROJ
    DEFAULT_CLUSTER_ZONE=$(jq -r .zone <<< "$DEFAULT_CLUSTER_DATA")
    DEFAULT_CLUSTER_LONG_NAME=gke_"$PROJ"_"$DEFAULT_CLUSTER_ZONE"_"$CLUSTER_DEFAULT"
  fi
done

ALL_CLUSTERS=$($kubectl config get-clusters | grep -v NAME)

echo "Clusters: ${ALL_CLUSTERS[*]}"
echo "Default Cluster: $CLUSTER_DEFAULT"

echo "Setting Primary Project"
$gcloud config set project "$DEFAULT_CLUSTER_PROJECT"

echo "Setting Primary Zone"
$gcloud config set compute/zone "$DEFAULT_CLUSTER_ZONE"

echo "Setting Primary Cluster"
$gcloud config set container/cluster "$CLUSTER_DEFAULT"
$kubectl config use-context "$DEFAULT_CLUSTER_LONG_NAME"
