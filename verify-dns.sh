#!/bin/bash


set -e
set -u

TEST=`basename $0`
D=`dirname $0`
. $D/common.sh

title "Verify DNS"

set +e
#blocking
kubectl delete -f $D/apod.yaml 2>/dev/null
set -e

kubectl label nodes node2 nodeName=node2 --overwrite
kubectl -v=6 create -f $D/apod.yaml

kubectl wait --for=condition=Ready pod/apod --timeout=30s || (echo "ERROR starting pod/node2-pod" ; exit 1)

title "ping google.com"
kubectl exec -it apod -- ping -W 5 -c 3 google.com
RV=$?
kubectl delete -f $D/apod.yaml 2>/dev/null
if [ $RV -ne 0 ] ; then
	err $TEST
	exit 1
fi

success $TEST

