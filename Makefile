BASE:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
SHELL=/bin/sh
NAMESPACE=dsp-demo-creditcard-fraud
GIT_REPO_NAME=fraud-detection-pipeline
MODEL_REGISTRY_NAME=creditfraud-pipeline-model-registry
MARIADB_NAME=mariadb-creditfraud-pipeline
UPSTREAM_REPO=https://github.com/tsailiming/openshift-ai-dsp.git

.PHONY: setup-dsp-demo
setup-dsp-demo: preflight-check setup-namespace deploy-seaweedfs deploy-gitea deploy-dspa deploy-model-registry deploy-tekton 

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
	-oc delete project $(NAMESPACE)

.PHONY: setup-namespace
setup-namespace:
	-oc new-project $(NAMESPACE)
	@oc label namespace $(NAMESPACE) \
		maistra.io/member-of=istio-system \
		modelmesh-enabled=false \
		opendatahub.io/dashboard=true

.PHONY: setup-odh-tec
setup-odh-tec:
	@oc apply -f $(BASE)/yaml/odh-tec.yaml -n $(NAMESPACE)
	
	@ODH_ROUTE=$$(oc get route odh-tec -n $(NAMESPACE) -o jsonpath='{.spec.host}') && \
	echo "S3 Browser: $${ODH_ROUTE}"

.PHONY: teardown-tekton
teardown-tekton:
	-@oc delete -f ${BASE}/yaml/tekton/pipeline.yaml -n $(NAMESPACE)

.PHONY: deploy-tekton
deploy-tekton: deploy-model-registry
	@if oc get crd pipelines.tekton.dev >/dev/null 2>&1; then \
		echo "Tekton is already installed. Skipping Tekton installation."; \
	else \
		echo "Tekton is not installed. Installing..."; \
		oc apply -f $(BASE)/yaml/tekton/tekton-sub.yaml; \
	fi

	@until oc get crd pipelines.tekton.dev>/dev/null 2>&1; do \
    	echo "Wait until CRD pipelines.tekton.dev is ready..."; \
		sleep 10; \
	done
	
	@oc apply -f ${BASE}/yaml/tekton/pipeline.yaml -n $(NAMESPACE)
	
	@$(BASE)/scripts/patch-pipeline.sh $(NAMESPACE) $(GIT_REPO_NAME) $(MODEL_REGISTRY_NAME)

.PHONY: deploy-gitea
deploy-gitea:
	@oc apply -k https://github.com/rhpds/gitea-operator/OLMDeploy

	@until oc get crd gitea.pfe.rhpds.com>/dev/null 2>&1; do \
    	echo "Wait until CRD gitea.pfe.rhpds.com is ready..."; \
		sleep 10; \
	done

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
teardown-all: teardown-kserve teardown-model-registry teardown-tekton teardown-seaweedfs teardown-dspa teardown-namespace
	
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

	oc apply -f $(BASE)/yaml/model-registry/rb.yaml
	
	@echo "Model registry is ready"

.PHONY: teardown-dspa
teardown-dspa:
	-oc delete DataSciencePipelinesApplication dspa -n $(NAMESPACE)
	-oc delete -f $(BASE)/yaml/dspa/dspa-edit-rb.yaml -n $(NAMESPACE)

.PHONY: deploy-dspa
deploy-dspa:
	@oc apply -f $(BASE)/yaml/dspa/dspa-edit-rb.yaml -n $(NAMESPACE)

	@NAMESPACE=$(NAMESPACE) \
		envsubst < $(BASE)/yaml/dspa/dspa.yaml.tmpl | oc apply -n $(NAMESPACE) -f -
	
.PHONY: teardown-seaweedfs
teardown-seaweedfs:
	-helm uninstall seaweedfs-dsp -n $(NAMESPACE)
	-oc delete pvc -l app.kubernetes.io/name=seaweedfs-dsp -n $(NAMESPACE) 2>/dev/null || true
	-oc delete secret aws-connection-my-storage -n $(NAMESPACE) 2>/dev/null || true
	-oc delete secret aws-connection-pipeline-artifacts -n $(NAMESPACE) 2>/dev/null || true

.PHONY: deploy-seaweedfs
deploy-seaweedfs: teardown-seaweedfs
	@helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm || true
	@helm repo update seaweedfs

	@helm install seaweedfs-dsp seaweedfs/seaweedfs \
		-n $(NAMESPACE) \
		-f $(BASE)/yaml/infra/seaweedfs-values.yaml

	@echo "Waiting for SeaweedFS S3 gateway to be ready..."
	@until oc get deployment seaweedfs-dsp-s3 -n $(NAMESPACE) -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '1'; do \
		echo "Waiting for SeaweedFS S3 deployment..."; \
		sleep 10; \
	done
	@echo "SeaweedFS S3 gateway is ready."

	@AWS_ACCESS_KEY_ID=$$(oc get secret seaweedfs-dsp-s3-secret -n $(NAMESPACE) -o jsonpath='{.data.admin_access_key_id}' | base64 -d) \
	AWS_SECRET_ACCESS_KEY=$$(oc get secret seaweedfs-dsp-s3-secret -n $(NAMESPACE) -o jsonpath='{.data.admin_secret_access_key}' | base64 -d) \
	AWS_S3_ENDPOINT=seaweedfs-dsp-s3.$(NAMESPACE).svc.cluster.local \
	AWS_S3_PORT=8333 \
		envsubst < $(BASE)/yaml/infra/data-connection.yaml.tmpl | oc apply -n $(NAMESPACE) -f -

	@echo "SeaweedFS S3 endpoint: http://seaweedfs-dsp-s3.$(NAMESPACE).svc.cluster.local:8333"

.PHONY: run-pipeline
run-pipeline:
	@$(BASE)/scripts/run-pipeline.sh $(NAMESPACE) $(GIT_REPO_NAME)
