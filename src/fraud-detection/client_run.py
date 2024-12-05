#!/usr/bin/env python

import os
import kfp
import argparse
import subprocess
from datetime import datetime

# Pipeline input parameters

DATASTORE_URL = os.environ.get("DATASTORE_URL", "http://gitea.gitea.svc.cluster.local:3000/opentlc-mgr/lm-fraud-detection/raw/branch/main/src/fraud-detection/card_transdata.csv")
dspa = os.environ.get('DSPA_NAME', "dspa")
run_name = os.environ.get('RUN_NAME', "run_name")
experiment_name = os.environ.get('EXPERIMENT_NAME', "fraud-training")
git_revision = os.environ.get('GIT_REVISION', '1.0')
model_prefix = os.environ.get('DEST_MODEL_PREFIX', 'models/fraud-detection-pipeline')
model_name = os.environ.get('MODEL_NAME', 'fraud-detection')
model_registry_endpoint = os.environ.get('MODEL_REGISTRY_ENDOIINT', 'my-model-registry-rest.apps.multus-test.sandbox323.opentlc.com')
model_registry_port = os.environ.get('MODEL_REGISTRY_PORT', '443')

model_registry_is_secure = os.environ.get('MODEL_REGISTRY_IS_SECURE', 'true').lower()
model_registry_is_secure = model_registry_is_secure == 'true'

enable_caching_str = os.environ.get("ENABLE_CACHING", "true").lower()
enable_caching = enable_caching_str == "true"

data_connection = os.environ.get('DATA_CONNECTION', 'aws-connection-my-storage')

with open('/var/run/secrets/kubernetes.io/serviceaccount/namespace', 'r') as namespace_file:
    namespace = namespace_file.read().strip()

with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as token_file:
    token = token_file.read().strip()

with open('src/fraud-detection/isvc.yaml.j2', 'r') as isvc_file:
    isvc_file_content = isvc_file.read().strip()

with open('src/fraud-detection/sr.yaml.j2', 'r') as sr_file:
    sr_file_content = sr_file.read().strip()

pipeline_name = "fraud-detection-training"

dt = datetime.now().strftime("%Y-%m-%d %H-%M-%S")
run_name = f"{experiment_name} {dt}"

metadata = {
    "datastore": {"url": DATASTORE_URL},
    "hyperparameters": {"epochs": 2},
    "git_revision": git_revision,
    "model_prefix":  model_prefix,
    "model_name": model_name,
    "model_registry_endpoint": model_registry_endpoint,
    "model_registry_port": model_registry_port,
    "model_registry_is_secure": model_registry_is_secure,
    "data_connection": data_connection,
    "isvc_file_content": isvc_file_content,
    "sr_file_content": sr_file_content,
    "experiment_name": experiment_name,
    "run_name": run_name
}

def get_pipeline_id_by_name(client, pipeline_name):
    pipelines = client.list_pipelines()

    if pipelines and pipelines.pipelines:
        for pipeline in pipelines.pipelines:
            if pipeline.display_name == pipeline_name:
                return pipeline
    return None

def get_first_pipeline_version(client, pipeline_id, version_name):
    response = client.list_pipeline_versions(pipeline_id=pipeline_id)
    
    if response and response.pipeline_versions:
        for version in response.pipeline_versions:
            if version.display_name == version_name:
                return version.pipeline_version_id
    return None

def create_run_from_pipeline_file(pipeline_file, client, metadata):
    # Assuming pipeline file is already compiled (YAML)
    with open(pipeline_file, 'r') as file:
        pipeline_content = file.read()

    #print(f"PIPELINE ARGUMENT: {metadata}")    
    
    pipeline = get_pipeline_id_by_name(client, pipeline_name)

    if pipeline:
        
        pipeline_version_name = f"{pipeline_name} version {dt}"

        pipeline = client.upload_pipeline_version(
            pipeline_package_path=pipeline_file,
            pipeline_version_name=pipeline_version_name,
            pipeline_id=pipeline.pipeline_id
        )

        pipeline_version_id = pipeline.pipeline_version_id
    else:      

        pipeline_version_name = pipeline_name

        pipeline = client.upload_pipeline(
            pipeline_package_path=pipeline_file,
            pipeline_name=pipeline_name
        )

        # When the first pipeline gets created, a pipeline version gets created too
        pipeline_version_id = get_first_pipeline_version(client, pipeline.pipeline_id, pipeline_version_name)
        
    experiment = client.create_experiment(name=experiment_name)

    run = client.run_pipeline(
        experiment_id=experiment.experiment_id,
        params=metadata,
        job_name=run_name,
        pipeline_id=pipeline.pipeline_id,
        version_id=pipeline_version_id
    )

    print(f"Run created using pipeline file: {pipeline_file}")
    print(f"Run created using pipeline id: {pipeline.pipeline_id}")
    print(f"Run using pipeline version name: {pipeline_version_name} id: {pipeline_version_id}")
    print(f"Pipeline submitted: {run.run_id}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Run Kubeflow pipeline from an existing YAML file')
    parser.add_argument('--pipeline-file', type=str, required=True, 
                        help='Path to the existing pipeline YAML file')
    args = parser.parse_args()

    dspa_host = f"ds-pipeline-{dspa}.{namespace}.svc.cluster.local"
    #dspa_host ='localhost'
    route = f"https://{dspa_host}:8443"

    client = kfp.Client(host=route, verify_ssl=False, existing_token=token)

    create_run_from_pipeline_file(args.pipeline_file, client, metadata)