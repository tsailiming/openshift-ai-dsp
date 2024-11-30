#!/bin/sh

set -e

oc project dsp-demo-creditcard-fraud

oc delete pipelinerun --all

echo 1 >> README.md; git add .; git commit -a -m 'add'; git push -v
sleep 10
tkn pr logs -f -L