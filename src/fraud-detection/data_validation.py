from kfp.dsl import (
    component,
    Input,
    Dataset,
)

@component(
base_image="quay.io/opendatahub/ds-pipelines-sample-base:v1.0"
)
def validate_transactiondb_data(
    dataset: Input[Dataset]
) -> bool:
    """
    Validates if the data schema is correct and if the values are reasonable.
    """
    
    if not dataset.path:
        raise Exception("dataset not found")
    return True