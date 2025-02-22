BASE:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
SHELL=/bin/sh
NAMESPACE=dsp-demo-creditcard-fraud
GIT_REPO_NAME=fraud-detection-pipeline
MODEL_REGISTRY_NAME=creditfraud-pipeline-model-registry
MARIADB_NAME=mariadb-creditfraud-pipeline
UPSTREAM_REPO=https://github.com/tsailiming/openshift-ai-dsp.git

.PHONY: setup-dsp-demo
setup-dsp-demo: preflight-check setup-namespace deploy-minio deploy-dspa deploy-model-registry deploy-tekton deploy-gitea

.PHONY: preflight-check
preflight-check:
	@POD_STATUS=$$(oc get pods -n redhat-ods-applications -l app.kubernetes.io/part-of=model-registry-operator -o jsonpath='{.items[0].status.phase}'); \
	if [ "$${POD_STATUS}" != "Running" ]; then \
	    @echo "Pod for 'model-registry-operator-controller-manager' is not running! Current status: $${POD_STATUS}"; \
		@echo "Ensure model-registry is Managed in DSC. Example: "; \
		@echo "modelregistry:"; \
		@echo "  managementState: Managed"; \
		@echo "  registriesNamespace: rhoai-model-registries"; \
	    exit 1; \
	fi
	@echo "Pod for 'model-registry-operator-controller-manager' is ready!"

.PHONY: teardown-kserve
teardown-kserve:
	-oc delete inferenceservice fraud-detection -n $(NAMESPACE)
	-oc delete servingruntime fraud-detection -n $(NAMESPACE)

.PHONY: teardown-namespace
teardown-namespace:
	-oc delete -f $(BASE)/yaml/netpol-ingress.yaml -n $(NAMESPACE)
	-oc delete project $(NAMESPACE)

.PHONY: setup-namespace
setup-namespace:
	-oc new-project $(NAMESPACE)
	@oc label namespace $(NAMESPACE) \
		maistra.io/member-of=istio-system \
		modelmesh-enabled=false \
		opendatahub.io/dashboard=true
	@oc apply -f $(BASE)/yaml/netpol-ingress.yaml -n $(NAMESPACE)

.PHONY: setup-odh-tec
setup-odh-tec:
	@oc apply -f $(BASE)/yaml/odh-tec.yaml -n $(NAMESPACE)
	
	@ODH_ROUTE=$$(oc get route odh-tec -n $(NAMESPACE) -o jsonpath='{.spec.host}') && \
	echo "S3 Browser: $${ODH_ROUTE}"

.PHONY: teardown-tekton
teardown-tekton:
	-@oc delete -f ${BASE}/yaml/tekton/netpol.yaml -n $(NAMESPACE)
	-@oc delete -f ${BASE}/yaml/tekton/pipeline.yaml -n $(NAMESPACE)

.PHONY: deploy-tekton
deploy-tekton: deploy-model-registry
	@oc apply -f $(BASE)/yaml/tekton/tekton-sub.yaml
	@oc apply -f ${BASE}/yaml/tekton/netpol.yaml -n $(NAMESPACE)
	@oc apply -f ${BASE}/yaml/tekton/pipeline.yaml -n $(NAMESPACE)
	
	@$(BASE)/scripts/patch-pipeline.sh $(NAMESPACE) $(GIT_REPO_NAME) $(MODEL_REGISTRY_NAME)

.PHONY: deploy-gitea
deploy-gitea: deploy-tekton
	@oc apply -k https://github.com/rhpds/gitea-operator/OLMDeploy
	-oc new-project gitea
	@oc apply -f yaml/gitea/gitea-sever.yaml

	@echo "Wait until Gitea adminSetupComplete is true"
	@while [ "$$(oc get gitea/gitea -n gitea -o jsonpath='{.status.adminSetupComplete}')" != "true" ]; do \
		echo "Waiting for Gitea adminSetupComplete to be true..."; \
		sleep 10; \
	done
	@echo "Gitea is now ready"

	@$(BASE)/scripts/add-gitea-webhook.sh $(NAMESPACE) $(GIT_REPO_NAME) $(UPSTREAM_REPO)

.PHONY: teardown-all
teardown-all: teardown-kserve teardown-model-registry teardown-tekton teardown-minio teardown-dspa teardown-namespace
	
.PHONY: teardown-model-registry
teardown-model-registry:
	-@oc delete modelregistry.modelregistry.opendatahub.io/$(MODEL_REGISTRY_NAME) -n rhoai-model-registries
	-@oc delete deploy $(MARIADB_NAME) -n rhoai-model-registries
	-@oc delete svc $(MARIADB_NAME) -n rhoai-model-registries
	-@oc delete secret my-registry-password -n rhoai-model-registries
	-@oc delete pvc $(MARIADB_NAME)-data -n rhoai-model-registries
		
.PHONY: deploy-model-registry
deploy-model-registry: teardown-model-registry	
	@oc create secret generic my-registry-password \
  		--from-literal=MYSQL_USER=admin \
  		--from-literal=MYSQL_PASSWORD=adminpass \
  		--from-literal=MYSQL_DATABASE=mydatabase \
		-n rhoai-model-registries

	PVC_NAME=$(MARIADB_NAME)-data \
		envsubst < $(BASE)/yaml/model-registry/mariadb-pvc.yaml.tmpl | oc create -n rhoai-model-registries  -f -
	
	@oc new-app -i mariadb:10.5-el8 \
  		--name=$(MARIADB_NAME) \
  		-e MYSQL_USER=admin \
  		-e MYSQL_PASSWORD=adminpass \
  		-e MYSQL_DATABASE=sampledb \
		-n rhoai-model-registries

	oc set volumes deployment/$(MARIADB_NAME) \
	  --add \
	  --name=$(MARIADB_NAME)-data \
	  --claim-mode='ReadWriteOnce' \
	  --claim-name=$(MARIADB_NAME)-data \
	  -m /var/lib/mysql/data \
  	  -n rhoai-model-registries

	@until oc get pods -l deployment=$(MARIADB_NAME) -n rhoai-model-registries -o jsonpath="{.items[*].status.phase}" | grep "Running" > /dev/null; do \
		echo "Waiting for MariaDB to be ready..."; \
		sleep 10; \
	done	

	@MYSQL_NAME=$(MARIADB_NAME) \
	MYSQL_SECRET=my-registry-password \
	MYSQL_DATABASE=sampledb \
	MYSQL_USER=admin \
	MODEL_REGISTRY_NAME=${MODEL_REGISTRY_NAME} \
	APPS_DOMAIN=$$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')  \
		envsubst < $(BASE)/yaml/model-registry/model-registry.yaml.tmpl | oc create -n rhoai-model-registries  -f -
	
	@until oc get modelregistry.modelregistry.opendatahub.io/$(MODEL_REGISTRY_NAME) -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -q "True"; do \
		echo "Waiting for model registry to be ready..."; \
		sleep 10; \
	done

	@echo "Model registry is ready"

.PHONY: teardown-dspa
teardown-dspa:
	-oc delete DataSciencePipelinesApplication dspa -n $(NAMESPACE)
	-oc delete -f $(BASE)/yaml/dspa/dspa-edit-rb.yaml -n $(NAMESPACE)

.PHONY: deploy-dspa
deploy-dspa:
	@oc apply -f $(BASE)/yaml/dspa/dspa-edit-rb.yaml -n $(NAMESPACE)

	@AWS_S3_ENDPOINT=$$(oc get route minio -n ${NAMESPACE} -o jsonpath='{.spec.host}') \
         envsubst < $(BASE)/yaml/dspa/dspa.yaml.tmpl | oc apply -n $(NAMESPACE) -f -
	
.PHONY: teardown-minio
teardown-minio:
	-oc delete -f $(BASE)/yaml/minio/minio.yaml -n $(NAMESPACE)
	-oc delete pvc data-minio-0 -n $(NAMESPACE)

.PHONY: deploy-minio
deploy-minio: teardown-minio
	@oc apply -f $(BASE)/yaml/minio/minio.yaml -n $(NAMESPACE)

	@until oc get statefulset minio -n $(NAMESPACE) -o jsonpath='{.status.readyReplicas}' | grep -q '1'; do \
		echo "Waiting for StatefulSet minio to have 1 ready replica..."; \
		sleep 10; \
	done
	@echo "StatefulSet minio has 1 ready replica."

	-oc delete secret aws-connection-my-storage -n $(NAMESPACE)
	-oc delete secret aws-connection-pipeline-artifacts -n $(NAMESPACE)

	@AWS_ACCESS_KEY_ID=$$(oc extract secret/minio  --to=- --keys=MINIO_ROOT_USER -n $(NAMESPACE) 2>/dev/null | tr -d '\n' | base64 ) \
	AWS_SECRET_ACCESS_KEY=$$(oc extract secret/minio  --to=- --keys=MINIO_ROOT_PASSWORD -n $(NAMESPACE) 2>/dev/null | tr -d '\n' | base64) \
	AWS_S3_ENDPOINT=$$(oc get route minio -n $(NAMESPACE) -o jsonpath='{.spec.host}') \
		envsubst < $(BASE)/yaml/minio/data-connection.yaml.tmpl | oc create -n $(NAMESPACE) -f -	

	@$(BASE)/scripts/run-job.sh $(BASE)/yaml/minio/setup-s3.yaml.tmpl $(NAMESPACE) setup-s3-job aws-connection-pipeline-artifacts
	@$(BASE)/scripts/run-job.sh $(BASE)/yaml/minio/setup-s3.yaml.tmpl $(NAMESPACE) setup-s3-job aws-connection-my-storage

.PHONY: run-pipeline
run-pipeline:
	@$(BASE)/scripts/run-pipeline.sh $(NAMESPACE) $(GIT_REPO_NAME)
