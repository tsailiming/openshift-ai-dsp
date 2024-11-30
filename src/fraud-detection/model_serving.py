from kfp.dsl import (
    component,
    Input,
    Output,    
    Model,
    Markdown,
    OutputPath,
    Artifact
)

@component(
    base_image="registry.access.redhat.com/ubi8/python-39",
    packages_to_install=["kubernetes", "kserve==0.14.0rc0", "jinja2"]
    
)
def deploy_model(
    model_name: str,
    model_path: str,
    model_version: str,
    data_connection: str,
    isvc_file_content: str,
    sr_file_content: str
):
    from jinja2 import Template
    from kubernetes import client, config
    import yaml

    #config.load_kube_config()
    config.load_incluster_config()    
    api_instance = client.CustomObjectsApi()

    def get_current_namespace():
        namespace_file = "/var/run/secrets/kubernetes.io/serviceaccount/namespace"
        try:
            with open(namespace_file, 'r') as f:
                return f.read().strip()
        except Exception:
            raise Exception("Namespace file not found. Are you running in a Kubernetes Pod?")
        
    def resource_exists(group, version, namespace, plural, name):
        try:
            api_instance.get_namespaced_custom_object(
                group=group,
                version=version,
                namespace=namespace,
                plural=plural,
                name=name,
            )
            return True
        except client.exceptions.ApiException as e:
            if e.status == 404:
                return False
            else:
                raise

    def apply_yaml(name, group, version, plural, yaml_content):        
        resource_definition = yaml.safe_load(yaml_content)
        
        if resource_exists(group = group,
                        version = version,
                        namespace = get_current_namespace(),
                        plural = plural,
                        name = name):
            api_instance.patch_namespaced_custom_object(
                group = group,
                version = version,
                plural = plural,
                namespace = get_current_namespace(),
                name = name, 
                body=resource_definition
            )
        else:
            api_instance.create_namespaced_custom_object(
                group=group,
                version=version,
                plural = plural,
                namespace = get_current_namespace(),
                body=resource_definition
            )
    
    context = {
        "model_name": model_name,
        "model_version": model_version,
        "model_path": model_path,
        "storage_key": data_connection
    }
        
    # print(f"ISVC_FILE:\n{Template(isvc_file_content).render(context)}")
    # print(f"sr_file:\n{Template(isvc_file_content).render(context)}")

    apply_yaml(name = context['model_name'],
            group = 'serving.kserve.io',
            version = 'v1alpha1', 
            plural = 'servingruntimes',           
            yaml_content= Template(sr_file_content).render(context))

    apply_yaml(name = context['model_name'],
            group = 'serving.kserve.io',
            version= 'v1beta1',
            plural = 'inferenceservices',
            yaml_content = Template(isvc_file_content).render(context))