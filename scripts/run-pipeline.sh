#!/bin/sh

set -e

NAMESPACE=$1
REPO_NAME=$2
GITEA_ROUTE=$(oc get gitea gitea -n gitea -o jsonpath="{.status.giteaRoute}")
GIT_URL=$GITEA_ROUTE/opentlc-mgr/$REPO_NAME.git
GIT_REVISION=$(git ls-remote "$GIT_URL" refs/heads/main | cut -f1)

echo "GIT_URL: ${GIT_URL}"
echo "GIT_REVISION: ${GIT_REVISION}"

oc project ${NAMESPACE}

oc delete pipelinerun --all

env GIT_URL=${GIT_URL} \
    GIT_REVISION=${GIT_REVISION} \
    envsubst < yaml/tekton/pipeline-run.yaml.tmpl | oc create -n ${NAMESPACE} -f -

sleep 10
tkn pr logs -f -L