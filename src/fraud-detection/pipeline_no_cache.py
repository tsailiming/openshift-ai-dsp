# kfp imports
from kfp import dsl

# Component imports
from fetch_data import fetch_transactionsdb_data
from data_validation import validate_transactiondb_data
from data_preprocessing import preprocess_transactiondb_data
from train_model import train_fraud_model, convert_keras_to_onnx
from evaluate_model import evaluate_keras_model_performance, validate_onnx_model
from upload_model import upload_onnx_model
from register_model import register_model
from model_serving import deploy_model
from util import add_env

# Create pipeline
@dsl.pipeline(
  name='fraud-detection-training-pipeline',
  description='Trains the fraud detection model.',
)
def fraud_training_pipeline(
    datastore: dict,
    hyperparameters: dict,
    git_revision: str,
    model_prefix: str,
    model_name: str,
    model_registry_endpoint: str,
    model_registry_port: str,
    model_registry_is_secure: bool,
    data_connection: str,
    isvc_file_content: str,
    sr_file_content: str,
    experiment_name: str,
    run_name: str

):
    fetch_task = fetch_transactionsdb_data(datastore = datastore).set_caching_options(enable_caching=False)

    # Validate Data
    data_validation_task = validate_transactiondb_data(dataset = fetch_task.outputs["dataset"]).set_caching_options(enable_caching=False)

    # Pre-process Data
    pre_processing_task = preprocess_transactiondb_data(in_data = fetch_task.outputs["dataset"]).set_caching_options(enable_caching=False)

    # Train Keras model
    training_task = train_fraud_model(
        train_data = pre_processing_task.outputs["train_data"], 
        val_data = pre_processing_task.outputs["val_data"],
        scaler = pre_processing_task.outputs["scaler"],
        class_weights = pre_processing_task.outputs["class_weights"],
        hyperparameters = hyperparameters,
    ).set_caching_options(enable_caching=False)

    # Convert Keras model to ONNX
    convert_task = convert_keras_to_onnx(keras_model = training_task.outputs["trained_model"]).set_caching_options(enable_caching=False)

    # Evaluate Keras model performance
    model_evaluation_task = evaluate_keras_model_performance(
        model = training_task.outputs["trained_model"],
        test_data = pre_processing_task.outputs["test_data"],
        scaler = pre_processing_task.outputs["scaler"],
        previous_model_metrics = {"accuracy":0.85},
    ).set_caching_options(enable_caching=False)

    # Validate that the Keras -> ONNX conversion was successful
    model_validation_task = validate_onnx_model(
        keras_model = training_task.outputs["trained_model"],
        onnx_model = convert_task.outputs["onnx_model"],
        test_data = pre_processing_task.outputs["test_data"]
    ).set_caching_options(enable_caching=False)

    # Upload the model to S3 bucket
    upload_model_task = upload_onnx_model(
        onnx_model=convert_task.outputs["onnx_model"],        
        model_name = model_name,
        model_prefix=model_prefix        
    ).set_caching_options(enable_caching=False).after(model_validation_task)
      
    register_model_task = register_model(
        model_name=model_name,
        git_revision=git_revision, 
        model_version=upload_model_task.outputs["model_version"],
        model_path=model_prefix, #upload_model_task.outputs["upload_onnx_model_path"],
        model_registry_endpoint = model_registry_endpoint,
        model_registry_port = model_registry_port,
        model_registry_is_secure = model_registry_is_secure,
        data_connection=data_connection,
        experiment_name=experiment_name,
        run_name=run_name
    ).set_caching_options(enable_caching=False).after(upload_model_task)
    
    deploy_model_task = deploy_model(
        model_name=model_name, 
        model_path=model_prefix,
        data_connection=data_connection,
        isvc_file_content = isvc_file_content,
        sr_file_content = sr_file_content,
        model_id = register_model_task.outputs['model_id'],
        model_version_id = register_model_task.outputs['model_version_id']
    ).set_caching_options(enable_caching=False).after(register_model_task)

    for key in [
        'AWS_ACCESS_KEY_ID',
        'AWS_DEFAULT_REGION',
        'AWS_S3_BUCKET',
        'AWS_S3_ENDPOINT',
        'AWS_SECRET_ACCESS_KEY',
        'DEST_BUCKET_NAME',
        'DEST_MODEL_PREFIX'        
    ]:
        add_env(upload_model_task, key)
        add_env(register_model_task, key)        
    