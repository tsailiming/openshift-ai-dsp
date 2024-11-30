from kfp.dsl import (
    component,
    Output,
    Dataset,
)

@component(
    base_image="quay.io/opendatahub/ds-pipelines-sample-base:v1.0",
    packages_to_install=["psycopg2", "pandas"]
)
def fetch_transactionsdb_data(
    datastore: dict,
    dataset: Output[Dataset]
):
    """
    Fetches data from the transactionsdb datastore
    """
    import urllib.request
    print("starting download...")
    url = datastore['url']
    urllib.request.urlretrieve(url, dataset.path)
    print("done")