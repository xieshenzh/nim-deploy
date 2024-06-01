#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
KSERVE_DIR="${SCRIPT_DIR}/.."

# Setup location of NIM Cache on local system
# mkdir -p /raid/nvidia-nim/cache

bash ${SCRIPT_DIR}/create-secrets.sh

# oc patch configmap config-features -n knative-serving --type merge -p '{"data":{"kubernetes.podspec-nodeselector":"enabled"}}'

for runtime in `ls -d ${KSERVE_DIR}/runtimes/*yaml`; do
  oc create -f $runtime
done

# NODE_NAME=${NODE_NAME:-"$(oc get nodes -o jsonpath='{.items[0].metadata.name}' | head -n1)"}
# sed -i "/# XXX: Update this to match your hostname/c\               - ${NODE_NAME} # XXX: Update this to match your hostname/" scripts/nvidia-nim-cache.yaml
oc create -f ${SCRIPT_DIR}/nvidia-nim-cache.yaml
