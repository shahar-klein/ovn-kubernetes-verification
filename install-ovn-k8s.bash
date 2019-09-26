#!/bin/bash

D=`dirname $0`
. $D/common.sh
YAMLS=$D/yaml
TESTS=$D/tests

set -u
set -e



CLONE_DIR=/tmp/go/src/github.com/ovn-org
GIT_CLONE=ovn-kubernetes



ovn_k8s_cid=${1:?Need ovn-k8s commit-id}
mode=${2:-nv}

rm -rf $CLONE_DIR
mkdir -p $CLONE_DIR
cd $CLONE_DIR

git clone ssh://git@gitlab-master.nvidia.com:12051/sdn/ovn-kubernetes.git $GIT_CLONE
cd $GIT_CLONE
git checkout $ovn_k8s_cid
export GOPATH=/tmp/go

cd go-controller
make install.tools
make
make check
make lint
make gofmt

cd ../dist/images

image="quay.io/nvidia/ovnkube-u:$ovn_k8s_cid"
if [ $mode = 'master' ] ; then
	image="quay.io/sklein/ovn-kube-u:$ovn_k8s_cid"
fi
./daemonset.sh --image=$image --net-cidr=192.168.0.0/16 --svc-cidr=17.16.1.0/24 --gateway-mode="shared" --k8s-apiserver=https://172.20.19.189:6443

cd ../yaml

# remove ovnkube-node ovs-daemon part as we are testing with host vased ovs
if [ $mode = 'master' ] ; then
	ovnkube_node_yaml_file="./ovnkube-node.yaml"
	start=$(grep -n "\- name: ovs-daemons" ${ovnkube_node_yaml_file} | cut -d : -f 1)
	if [[ $? != 0 ]]; then
   		echo cannot find the ovs-daemons pod
   		exit 1
	fi
	end=$(grep -n "\- name: ovn-controller" ${ovnkube_node_yaml_file} | cut -d : -f 1)
	if [[ $? != 0 ]]; then
   		echo cannot find the ovn-controller pod
   		exit 1
	fi
	cp ${ovnkube_node_yaml_file} ${ovnkube_node_yaml_file}.bak
	sed -i -e "${start},$((end-1))d" ${ovnkube_node_yaml_file} 
fi

set +e
kubectl delete -f ovnkube-node.yaml
kubectl delete -f ovnkube-master.yaml
kubectl delete -f ovnkube-db.yaml
kubectl delete -f ovn-setup.yaml
rm -rf /var/lib/openvswitch/*
set -e
sleep 5

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

set +e
kubectl delete -f ovnkube-node.yaml
kubectl delete -f ovnkube-master.yaml
kubectl delete -f ovnkube-db.yaml
kubectl delete -f ovn-setup.yaml
rm -rf /var/lib/openvswitch/*
set -e


if [ $mode != 'master' ] ; then
	#all good - copy yamls
	cd ../images
	YAMLS="k8s-yaml"
	cd /tmp
	rm -rf $YAMLS
	git clone ssh://git@gitlab-master.nvidia.com:12051/sdn/k8s-yaml.git $YAMLS
	cd -
	./daemonset.sh --image=quay.io/nvidia/ovnkube-u:$ovn_k8s_cid --net-cidr="net cidr" --svc-cidr="svc cidr" --gateway-mode="shared" --k8s-apiserver="https://K8S_apiserver_address:6443"
	./daemonset.sh --image=quay.io/nvidia/ovnkube-u:$ovn_k8s_cid --db-vip-image=quay.io/nvidia/ovndb-vip-u:$ovn_k8s_cid --net-cidr="net cidr" --svc-cidr="svc cidr" --gateway-mode="shared" --k8s-apiserver="https://K8S_apiserver_address:6443" --db-vip="VIP address"
	cp ../yaml/* /tmp/$YAMLS/ovn/ubuntu/shared/
	./daemonset.sh --image=quay.io/nvidia/ovnkube-u:$ovn_k8s_cid --net-cidr="net cidr" --svc-cidr="svc cidr" --gateway-mode="local" --k8s-apiserver="https://K8S_apiserver_address:6443"
	./daemonset.sh --image=quay.io/nvidia/ovnkube-u:$ovn_k8s_cid --db-vip-image=quay.io/nvidia/ovndb-vip-u:$ovn_k8s_cid --net-cidr="net cidr" --svc-cidr="svc cidr" --gateway-mode="local" --k8s-apiserver="https://K8S_apiserver_address:6443" --db-vip="VIP address"
	cp ../yaml/* /tmp/$YAMLS/ovn/ubuntu/local/
	cd /tmp/$YAMLS
	git add -A
	git commit -m "update the ovnkube images to the latest nv-ovn-kubernetes commit:$ovn_k8s_cid"
	#git push
fi

exit 0







