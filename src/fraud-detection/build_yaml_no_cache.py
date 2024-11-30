# NOT USED ANYMORE

import argparse
import kfp
from pipeline_no_cache import fraud_training_pipeline

def compile_pipeline(output_file):
    kfp.compiler.Compiler().compile(
        pipeline_func=fraud_training_pipeline,
        package_path=output_file
    )
    print(f"Pipeline compiled and saved to {output_file}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Compile Kubeflow pipeline')
    parser.add_argument('--output', type=str, default='fraud_detection_no_cache.yaml', 
                        help='Output file for the compiled pipeline')
    
    args = parser.parse_args()
    compile_pipeline(args.output)