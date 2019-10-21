#!/bin/bash

set -e
set -u

TEST=`basename $0`
D=`dirname $0`
. $D/common.sh

title "Multi Tiered Application"

set +e
# cleanup an leftover pods from previous runs
kubectl delete -f $D/webFrontend.yaml 2>/dev/null
kubectl delete -f $D/dbBackend.yaml 2>/dev/null
kubectl wait pod --for=delete -l name=mysql --timeout=60s 2>/dev/null
kubectl wait pod --for=delete -l name=web --timeout=60s 2>/dev/null

set -e

kubectl -v=6 create -f  $D/dbBackend.yaml
kubectl wait pod --for=condition=Ready -l name=mysql --timeout=60s || (echo "ERROR starting MySQL pod" ; exit 1)

# sleep for all the OVN LoadBalancer rules to be setup for DB service
sleep 10
kubectl -v=6 create -f  $D/webFrontend.yaml
kubectl wait pod --for=condition=Ready -l name=web --timeout=60s || (echo "ERROR starting Web pods" ; exit 1)

title "Initialize the DB using NodePort"
NODE_IP=$(kubectl get node node2 -o jsonpath='{.status.addresses[*].address}')
NODE_PORT=$(kubectl get svc web  -o jsonpath='{.spec.ports[*].nodePort}')

result=$(curl -s http://$NODE_IP:$NODE_PORT/init)
if [[ $result =~ "DB Init done" ]] ; then
  echo "DB successfully initialized"
else
  echo "Failed to iniitialize DB"
  err ${result}
  exit 1
fi

# insert sample data into the DB
result=$(curl -s -i -H "Content-Type: application/json" -X POST -d '{"uid": "1", "user":"SDN Rocks"}' http://$NODE_IP:$NODE_PORT/users/add)
if [[ $result =~ Added ]] ; then
  echo "User SDN Rocks successfully added"
else
  echo "Failed to add user SDN Rocks"
  err ${result}
  exit 1
fi

# Retrieve the data from Node3
NODE_IP=$(kubectl get node node3 -o jsonpath='{.status.addresses[*].address}')
userName=$(curl -s  http://$NODE_IP:$NODE_PORT/users/1)
if [[ $userName =~ "SDN Rocks" ]] ; then
  echo "User SDN Rocks successfully retrieved"
else
  echo "Failed to retrieve user SDN Rocks"
  err ${userName}
  exit 1
fi

# Now use ClusterIP to do the same
CLUSTER_IP=$(kubectl get svc web -o jsonpath='{.spec.clusterIP}')
CLUSTER_PORT=$(kubectl get svc web -o jsonpath='{.spec.ports[*].port}')

# insert sample data into the DB
result=$(curl -s -i -H "Content-Type: application/json" -X POST -d '{"uid": "2", "user":"OVN Rocks"}' http://$CLUSTER_IP:$CLUSTER_PORT/users/add)
if [[ $result =~ Added ]] ; then
  echo "User OVN Rocks successfully added"
else
  echo "Failed to add user OVN Rocks"
  err ${result}
  exit 1
fi

# Retrieve the data from ClusterIP
userName=$(curl -s  http://$CLUSTER_IP:$CLUSTER_PORT/users/2)
if [[ $userName =~ "OVN Rocks" ]] ; then
  echo "User OVN Rocks successfully retrieved"
else
  echo "Failed to retrieve user OVN Rocks"
  err ${userName}
  exit 1
fi

# delete all the yaml files
kubectl -v=6 delete -f  $D/dbBackend.yaml
kubectl -v=6 delete -f  $D/webFrontend.yaml

set +e
kubectl wait pod --for=delete -l name=mysql --timeout=60s 2>/dev/null
kubectl wait pod --for=delete -l name=web --timeout=60s 2>/dev/null
set -e

success $TEST

