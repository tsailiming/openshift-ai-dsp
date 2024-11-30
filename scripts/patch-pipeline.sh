#!/bin/sh

set -e

NAMESPACE=$1
REPO_NAME=$2
MODEL_REGISTRY_NAME=$3
GITEA_ROUTE=$(oc get gitea gitea  -n gitea -o jsonpath="{.status.giteaRoute}")
DATASTORE_URL=${GITEA_ROUTE}/opentlc-mgr/$REPO_NAME/raw/branch/main/src/fraud-detection/card_transdata.csv
MODEL_REGISTRY_ENDOIINT=$(oc get modelregistry "${MODEL_REGISTRY_NAME}" -n rhoai-model-registries -o jsonpath='{.status.hosts}' | jq -r '.[] | select(. | test("rest"))')

echo "DATASTORE_URL: ${DATASTORE_URL}"
echo "MODEL_REGISTRY_ENDOIINT: ${MODEL_REGISTRY_ENDOIINT}"

oc project ${NAMESPACE}

oc patch pipeline fraud-detection -n ${NAMESPACE} --type=json -p="[
  {
    \"op\": \"replace\",
    \"path\": \"/spec/params/0/default\",
    \"value\": \"${DATASTORE_URL}\"
  },
  {
    \"op\": \"replace\",
    \"path\": \"/spec/params/1/default\",
    \"value\": \"${MODEL_REGISTRY_ENDOIINT}\"
  }
]"
