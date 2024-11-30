#!/bin/sh

set -e

oc project dsp-demo-creditcard-fraud

tkn pr delete --all -f

echo 1 >> README.md; git add .; git commit -a -m 'add'; git push -v
sleep 10
tkn pr logs -f -L