#!/bin/sh

NAMESPACE=$1
ADMIN_USER=opentlc-mgr
ADMIN_PASSWORD=$(oc get gitea gitea -n gitea -o jsonpath="{.status.adminPassword}")
GITEA_ROUTE=$(oc get gitea gitea  -n gitea -o jsonpath="{.status.giteaRoute}")
REPO_NAME=$2
WEBHOOK_URL=http://el-fraud-detection-listener.${NAMESPACE}.svc.cluster.local:8080
UPSTREAM_GIT_REPO=$3

echo "GITEA_ADMIN_PASSWORD: ${ADMIN_PASSWORD}"
echo "GITEA_ROUTE: ${GITEA_ROUTE}"
echo "UPSTREAM_GIT_REPO: ${UPSTREAM_GIT_REPO}"

REPO_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  -X GET "${GITEA_ROUTE}/api/v1/repos/${ADMIN_USER}/${REPO_NAME}" \
  -u "${ADMIN_USER}:${ADMIN_PASSWORD}")

if [ "$REPO_CHECK" -eq 200 ]; then
  echo "Repository exists. Deleting..."
  curl -X DELETE "${GITEA_ROUTE}/api/v1/repos/${ADMIN_USER}/${REPO_NAME}" \
    -u "${ADMIN_USER}:${ADMIN_PASSWORD}"
  echo "Repository deleted."
elif [ "$REPO_CHECK" -eq 404 ]; then
  echo "Repository does not exist."
else
  echo "Unexpected status code: $REPO_CHECK. Please check your inputs."
fi

curl -s -X POST "${GITEA_ROUTE}/api/v1/repos/migrate" \
  -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "{
        \"clone_addr\": \"${UPSTREAM_GIT_REPO}\",        
        \"repo_name\": \"${REPO_NAME}\",
        \"repo_owner\": \"${ADMIN_USER}\",
        \"mirror\": false,
        \"private\": false,
        \"service\": \"git\"
      }" > /dev/null

echo "Cloned repo: ${ADMIN_USER}/${REPO_NAME} from ${UPSTREAM_GIT_REPO}"

curl -s -X POST "${GITEA_ROUTE}/api/v1/repos/${ADMIN_USER}/${REPO_NAME}/hooks" \
  -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "{
        \"type\": \"gitea\",
        \"config\": {
          \"url\": \"${WEBHOOK_URL}\",
          \"content_type\": \"json\"          
        },
        \"events\": [
          \"push\"
        ],
        \"active\": true
      }" > /dev/null

echo "Created webhook to ${WEBHOOK_URL}"