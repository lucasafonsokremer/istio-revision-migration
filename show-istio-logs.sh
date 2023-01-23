#!/bin/bash

if [ $# -lt 1 ]; then
  echo "Usage: <istio-Revision|default>"
  echo "Example: 1-7-5"
  echo "Example: default"
  exit 1
fi
if [ $1 == "default" ]; then
  istio_rev=""
else
  istio_rev="-$1"
fi

# you cannot ask for logs for a deployment unfortunately
#kubectl logs --since=5m -f -n istio-operator $(kubectl get pods -n istio-operator -lname=istio-operator -o jsonpath='{.items[0].metadata.name}')

# so you need to specify a pod
# but these istio operator pods do not have a label selector that makes them unique among revisions
# so we need to go through the replica set, then the pod hash label
# https://stackoverflow.com/questions/52957227/kubectl-command-to-list-pods-of-a-deployment-in-kubernetes
#
DEPLOY_NAME=istio-operator${istio_rev}
echo "deployment name $DEPLOY_NAME"

RS_NAME=`kubectl describe deployment -n istio-operator $DEPLOY_NAME|grep "^NewReplicaSet"|awk '{print $2}'`; echo $RS_NAME

POD_HASH_LABEL=`kubectl get rs -n istio-operator $RS_NAME -o jsonpath="{.metadata.labels.pod-template-hash}"` ; echo $POD_HASH_LABEL

POD_NAMES=`kubectl get pods -n istio-operator -l pod-template-hash=$POD_HASH_LABEL --show-labels | tail -n +2 | awk '{print $1}'`; echo $POD_NAMES

set -x
kubectl logs --since=10m -f -n istio-operator $POD_NAMES
