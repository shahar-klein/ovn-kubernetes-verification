#!/bin/bash

D=`dirname $0`
. $D/common.sh
YAMLS=$D/yaml
TESTS=$D/tests

set -u
set -e

CLONE_DIR=ovn-kubernetes-build-and-test


ovn_k8s_cid=${1:?Need ovn-k8s commit-id}

cd /tmp
rm -rf $CLONE_DIR

git clone ssh://git@gitlab-master.nvidia.com:12051/sdn/ovn-kubernetes.git $CLONE_DIR
cd $CLONE_DIR
git checkout $ovn_k8s_cid

cd dist/images
./daemonset.sh --image=quay.io/sklein/ovn-kube-u:$ovn_k8s_cid --net-cidr=192.168.0.0/16 --svc-cidr=17.16.1.0/24 --gateway-mode="local" --k8s-apiserver=https://172.20.19.189:6443

cd ../yaml
set +e
kubectl delete -f ovnkube-node.yaml
kubectl delete -f ovnkube-master.yaml
kubectl delete -f ovnkube-db.yaml
kubectl delete -f ovn-setup.yaml
set -e
sleep 1

title "Create ovn-kubernetes pods"
kubectl -v=6 create -f ovn-setup.yaml
kubectl -v=6 create -f ovnkube-db.yaml
kubectl -v=6 create -f ovnkube-master.yaml
kubectl -v=6 create -f ovnkube-node.yaml

PODS=$(kubectl -n ovn-kubernetes get pods | grep -v NAME | awk '{print$1}' | xargs)
for POD in $PODS ; do
	kubectl -n ovn-kubernetes wait --for=condition=Ready pod/$POD --timeout=60s || (echo "ERROR: $POD is not up" ; exit 1)
done

#check pods running
title "Make sure ovn-kubernetes pods are up and running"
check_k8s_pod ovn-kubernetes ovnkube-node 3
check_k8s_pod ovn-kubernetes ovnkube-master 1
check_k8s_pod ovn-kubernetes ovnkube-db 1

bash $D/runtests.sh


exit 0







