# Fraud Detection Demo

This is an iteration of the Fraud Detection demo committed [here](https://rh-aiservices-bu.github.io/fraud-detection/fraud-detection-workshop/index.html), 
and [here](https://github.com/rhoai-mlops/jukebox/tree/9c724ca124d18911c34dcbb5c17e99a61db404b6/production). 

The Fraud Detection demo in this repo is more similar to the latter, rather than the former, except with the minor adjustments: 

* Instead of pulling data from an external posgres, training/validation data is downloaded via rest 
* Output model is not saved to Model registry
* All tasks have base images specified that pull from quay instead of Dockerhub to avoid rate limiting issues

## The Pipeline DAG Visual

<img src="img.png" alt="dag-visual" width="50%"/> 

### Run directly against a dspa via local terminal

First edit these values in [client_run.py](client_run.py)
```
NAMESPACE=<dspa_namespace>
DSPA_NAME=<dspa_name> # this is "dspa" if using rhoai
RUN_NAME=<run_name> # can be anything
```
Next, run the script
```bash
oc login --server=<cluster>
./client_run.py
```

### Build pipeline yaml to submit

```bash
./build_.yaml.py
```

Will output a yaml file to deploy directly in DSP. You can also find the yaml file here: [fraud_detection.yaml](fraud_detection.yaml)

Or build the version where caching is disabled: 

```bash
./build_yaml_no_cache.py
```

You can also find this yaml here: [fraud_detection_no_cache.yaml](fraud_detection_no_cache.yaml)
