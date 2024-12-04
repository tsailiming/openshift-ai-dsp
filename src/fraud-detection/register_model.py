from kfp.dsl import (
    component,
    Input,
    Output,    
    Model,
    Markdown
)

from typing import NamedTuple

@component(
    base_image="registry.access.redhat.com/ubi8/python-39",
    packages_to_install=["boto3", "model-registry==0.2.7a1"]
)
def register_model(
    model_name: str,
    git_revision: str,    
    model_path: str,
    model_version: str,
    model_registry_endpoint: str,
    model_registry_port: str,
    model_registry_is_secure: bool,
    data_connection: str,
    experiment_name: str,
    run_name: str,    
)-> NamedTuple('outputs', [('model_id', str), ('model_version_id', str)]):
    
    from model_registry import ModelRegistry, utils
    import os

    # https://model-registry.readthedocs.io/en/latest/#

    # print(f"GIT REVISION: {git_revision}")
    # print(f"MODEL_URI: {model_uri}")    
    # print(f"MODEL_REGISTRY_ENDPOINT: {model_registry_endpoint}")
    # print(f"MODEL_REGISTRY_PORT {model_registry_port}")
    # print(f"MODEL_REGISTRY_IS_SECURE {model_registry_is_secure}")

    with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'r') as token_file:
        token = token_file.read().strip()

    if model_registry_is_secure:
        model_registry_endpoint = f"https://{model_registry_endpoint}"
    else:
        model_registry_endpoint = f"http://{model_registry_endpoint}"
        
    registry = ModelRegistry(server_address = model_registry_endpoint,
                             port = model_registry_port, 
                             author = "Red Hat", 
                             user_token = token,
                             is_secure = model_registry_is_secure)


    endpoint_url=os.getenv('AWS_S3_ENDPOINT')
    region_name=os.getenv('AWS_DEFAULT_REGION') 
    bucket_name = os.getenv('DEST_BUCKET_NAME')

    model = registry.register_model(
                name = model_name,
                uri=utils.s3_uri_from(
                    endpoint=endpoint_url,
                    bucket=bucket_name,
                    region=region_name,
                    path=model_path),   
                description = "A fraud detection model",
                version = model_version,
                model_format_name="onnx",              # model format
                model_format_version="1",              # model format version
                storage_key=data_connection,
                metadata = {'git_revsion': git_revision,
                            'model_revision': model_version,
                            'experiment_name': experiment_name,
                            'run_name': run_name})

    version = registry.get_model_version(model_name, model_version)

    print(f"Registered Model: {model} with ID: {model.id}")
    print(f"Registered Model Version: {version} with ID: {version.id}")

    outputs = NamedTuple('outputs', [('model_id', str), ('model_version_id', str)])
    return outputs(model.id, version.id)
