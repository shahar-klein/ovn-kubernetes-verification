#!/bin/bash

PWD=`dirname $0`
. $PWD/common.sh
YAMLS=$PWD/yaml
TESTS=$PWD/tests

set -u
set -e

CLONE_DIR=cicd1

ovn_k8s_cid=${1:?Need ovn-k8s commit-id}

cd /tmp
rm -rf $CLONE_DIR

git clone https://gitlab-master.nvidia.com/sklein/my-test-ci-ovn-kubernetes.git $CLONE_DIR
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

sleep 10

#check pods running
title "Make sure ovn-kubernetes pods are up and running"
check_k8s_pod ovn-kubernetes ovnkube-node 3
check_k8s_pod ovn-kubernetes ovnkube-master 1
check_k8s_pod ovn-kubernetes ovnkube-db 1


bash $PWD/runtests.sh


exit 0







