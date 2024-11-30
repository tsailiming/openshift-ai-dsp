import os
from kfp.dsl import PipelineTask

def add_env(
        task: PipelineTask,
        key: str
    ):
         
    task.set_env_variable(
        name=key,
        value=os.environ.get(key)
    )    