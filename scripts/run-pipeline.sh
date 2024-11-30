#!/bin/sh

set -e

NAMESPACE=$1
REPO_NAME=$2
GITEA_ROUTE=$(oc get gitea gitea  -n gitea -o jsonpath="{.status.giteaRoute}")
GIT_URL=$GITEA_ROUTE/opentlc-mgr/$REPO_NAME.git
DATASTORE_URL=${GITEA_ROUTE}/opentlc-mgr/$REPO_NAME/raw/branch/main/src/fraud-detection/card_transdata.csv
GIT_REVISION=$(git ls-remote "$GIT_URL" refs/heads/main | cut -f1)

echo "GIT_URL: ${GIT_URL}"
echo "DATASTORE_URL: ${DATASTORE_URL}"
echo "GIT_REVISION: ${GIT_REVISION}"
echo "MODEL_REGISTRY_ENDOIINT: ${MODEL_REGISTRY_ENDOIINT}"
oc project ${NAMESPACE}

tkn pr delete --all -f

env GIT_URL=${GIT_URL} \
    DATASTORE_URL=${DATASTORE_URL} \
    GIT_REVISION=${GIT_REVISION} \
    MODEL_REGISTRY_ENDOIINT=${MODEL_REGISTRY_ENDOIINT} \
    envsubst < yaml/tekton/pipeline-run.yaml.tmpl | oc create -n ${NAMESPACE} -f -

sleep 10
tkn pr logs -f -L