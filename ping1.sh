#!/bin/bash

set -e
set -u

TEST=`basename $0`
D=`dirname $0`
. $D/common.sh

title "ping 1"

set +e
#blocking
kubectl delete -f $D/ping1.yaml 2>/dev/null
set -e

kubectl label nodes node2 nodeName=node2 --overwrite
kubectl label nodes node3 nodeName=node3 --overwrite
kubectl -v=6 create -f $D/1.yaml

kubectl wait --for=condition=Ready pod/node2-pod --timeout=10s || (echo "ERROR starting pod/node2-pod" ; exit 1)
kubectl wait --for=condition=Ready pod/node3-pod --timeout=10s || (echo "ERROR starting pod/node3-pod" ; exit 1)

IP_NODE2=$(kubectl get pod node2-pod --template={{.status.podIP}})
kubectl exec -it node3-pod -- ping -W 2 -c 2 $IP_NODE2
RV=$?
if [ $RV -ne 0 ] ; then
	err $TEST
	exit 1
fi

success $TEST

