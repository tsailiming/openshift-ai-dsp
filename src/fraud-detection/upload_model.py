from kfp.dsl import (
    component,
    Input,
    Output,    
    Model,
    Markdown,
    OutputPath
)

@component(
    base_image="registry.access.redhat.com/ubi8/python-39",
    packages_to_install=["boto3"],  
)
def upload_onnx_model(
    onnx_model: Input[Model],
    model_name: str,
    model_prefix: str,
    upload_onnx_model_uri: OutputPath(str),
    upload_onnx_model_path: OutputPath(str),
    model_version: OutputPath(str)    
):
    import os
    import boto3
    from urllib.parse import urlsplit
    import json
    import io

    # For debugging
    # for key, value in os.environ.items():
    #     if key.startswith("AWS"):
    #         print(f"{key}: {value}")
            
    src_uri = urlsplit(onnx_model.uri)
    src_bucket = src_uri.netloc  # Bucket name is in the netloc
    src_bucket_key = src_uri.path.lstrip('/')  # Key (file path) is in the path, remove leading slash
    
    print(f"SRC_BUCKET: {src_bucket}")
    print(f"SRC_BUCKET_KEY: {src_bucket_key}")
    
    s3_client = boto3.client(
        's3',
        endpoint_url=os.getenv('AWS_S3_ENDPOINT'),
        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
        region_name=os.getenv('AWS_DEFAULT_REGION') 
    )

    # Get destination bucket name from an environment variable
    dest_bucket = os.getenv('DEST_BUCKET_NAME', "my-storage")  
    print(f"DEST_BUCKET_NAME: {dest_bucket}")
    print(f"MODEL PREFIX KEY: {model_prefix}")
    
    # Find the highest model number
    def get_current_revision():
        response = s3_client.list_objects_v2(Bucket=dest_bucket, Prefix=model_prefix)
        if 'Contents' in response:
            numbers = [
                int(obj['Key'].split('/')[2])
                for obj in response['Contents']
                if obj['Key'].split('/')[2].isdigit()
            ]
            if numbers:
                return max(numbers)
        return 0 

    # Get the next number
    highest_revision = get_current_revision()
    next_revision = highest_revision + 1
    print(f"CURRENT HIGHEST MODEL REVISION NUMBER: {highest_revision}")
    print(f"NEXT MODEL REVISION NUMBER: {next_revision}")
    
    # Define the source object for copying
    copy_source = {
        'Bucket': src_bucket,
        'Key': src_bucket_key
    }
        
    dest_bucket_key = f"{model_prefix}/{next_revision}/model.onnx"  
    print(f"COPY_SOURCE: {copy_source}")
    print(f"DEST_BUCKET_NAME: {dest_bucket}")
    print(f"DEST_BUCKET_KEY: {dest_bucket_key}")

    # Copy object to the destination bucket and key
    s3_client.copy(copy_source, dest_bucket, dest_bucket_key)
    
    # Needed this to pin the model version down, otherwise
    # every restart of the pod can use the latest version from
    # /mnt/model when storage-init pulls down again from S3
    model_config = {
        "model_config_list": [
            {
                "config": {
                    "name": model_name,
                    "base_path": "/mnt/models",
                    "target_device": "AUTO",
                    "model_version_policy": {
                        "specific": {
                            "versions": [next_revision]
                        }
                    }
                }
            }
        ]
    }
    
    json_data = json.dumps(model_config, indent=4)
    file_buffer = io.BytesIO(json_data.encode('utf-8'))
    s3_client.upload_fileobj(file_buffer, dest_bucket, f"{model_prefix}/model_config.json")
        
    with open(upload_onnx_model_uri, 'w') as output_file:
        output_file.write(f"s3://{dest_bucket}/{dest_bucket_key}")
    
    with open(upload_onnx_model_path, 'w') as output_file:
        output_file.write(f"{dest_bucket_key}")

    with open(model_version, 'w') as output_file:
        output_file.write(f"{next_revision}")


