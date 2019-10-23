#!/bin/bash

set -x
set -e
set -u

TEST=`basename $0`
D=`dirname $0`
. $D/common.sh

title "Network Policy across pods"

# Network Policy rules for MySQL pods
# -- Mysql pods shouldn't talk to anyone
# -- Mysql pods should accept packets from Web pods at port 3306

# Network Policy rules for Web pods
# -- Web pods should be able to talk to TCP port 3306 on MySQL Pod
# -- Web pods should be able to accept packets to itself at port 5000
# -- Web pods should accept all the packets from CIDR 172.20.19.128/25 (K8s Node CIDR)
#    (this is for pinging purposes)

set +e

ns_label=$(kubectl get namespace kube-system -o jsonpath='{.metadata.labels.name}')
if [[ $ns_label != "kube-system" ]] ; then
  echo "namespace kube-system should be labeled with name=kube-system. Exiting..."
  exit 1
fi

# cleanup an leftover pods from previous runs
kubectl delete -f $D/webFrontend.yaml 2>/dev/null
kubectl delete -f $D/dbBackend.yaml 2>/dev/null
kubectl delete -f $D/busyBox.yaml 2>/dev/null
kubectl delete -f $D/networkPolicy.yaml 2>/dev/null
kubectl wait pod --for=delete -l name=mysql --timeout=60s 2>/dev/null
kubectl wait pod --for=delete -l name=web --timeout=60s 2>/dev/null
kubectl wait pod --for=delete -l name=busybox --timeout=60s 2>/dev/null

set -e

# Apply the network policy
kubectl create -f $D/networkPolicy.yaml
if [[ $? -ne 0 ]] ; then
  echo "Failed to apply the network policy yaml"
  exit 1
fi

kubectl -v=6 create -f  $D/dbBackend.yaml
kubectl wait pod --for=condition=Ready -l name=mysql --timeout=60s || (echo "ERROR starting MySQL pod" ; exit 1)

# sleep for all the OVN LoadBalancer rules to be setup for DB service
sleep 10
kubectl -v=6 create -f  $D/webFrontend.yaml
kubectl wait pod --for=condition=Ready -l name=web --timeout=60s || (echo "ERROR starting Web pods" ; exit 1)

# sleep for few seconds for the web frontend services to be implemented
sleep 10
# print all the k8s resources that we care about
kubectl get pods
kubectl get svc

title "Initialize the DB using NodePort"
NODE_IP=$(kubectl get node node2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
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
title "Insert a row into DB using NodePort"
result=$(curl -s -i -H "Content-Type: application/json" -X POST -d '{"uid": "1", "user":"SDN Rocks"}' http://$NODE_IP:$NODE_PORT/users/add)
if [[ $result =~ Added ]] ; then
  echo "User SDN Rocks successfully added"
else
  echo "Failed to add user SDN Rocks"
  err ${result}
  exit 1
fi

# Retrieve the data from Node3
title "Retrieve a row from the DB using NodePort"
NODE_IP=$(kubectl get node node3 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
userName=$(curl -s  http://$NODE_IP:$NODE_PORT/users/1)
if [[ $userName =~ "SDN Rocks" ]] ; then
  echo "User SDN Rocks successfully retrieved"
else
  echo "Failed to retrieve user SDN Rocks"
  err ${userName}
  exit 1
fi

# test negative scenarios
# bring up the busybox yaml file
kubectl -v=6 create -f  $D/busyBox.yaml
kubectl wait pod --for=condition=Ready  busybox --timeout=60s || (echo "ERROR starting pod/busybox" ; exit 1)

# again sleep here after creating the POD for this POD's IP to show up in the
# OVN ACLs and AddressSets
sleep 15


set +e
title "Non-Web pod should not able to connect to mysql DB"
dbPodIP=$(kubectl get pod mysql -o jsonpath='{.status.podIP}')
result=$(kubectl exec -it busybox -- nc -w 3 -zv ${dbPodIP} 3360 2>/dev/null)
if [[ $result =~ open ]] ; then
  echo "Failed: Busybox pod is able to connect to mysql pod."
  err ${result}
  exit 1
else
  echo "Success: Busybox pod is not able to connect to mysql pod."
  echo ${result}
fi

title "Non-web pod should be able to connect to web pod to add an user"
webPodIPs=$(kubectl get pods -l name=web -o jsonpath='{.items[*].status.podIP}')
for webPodIP in ${webPodIPs}
do
  result=$(kubectl exec -it busybox -- nc -w 3 -zv ${webPodIP} 5000 2>/dev/null)
  if [[ $result =~ open ]] ; then
    echo "Success: Busybox pod is able to connect to web pod."
    echo ${result}
  else
    echo "Failed: Busybox pod is not able to connect to web pod."
    err ${result}
    exit 1
  fi
done

title "Web-pod should be able to ping the k8s node but not 8.8.8.8"
webPodNames=$(kubectl get pods -l name=web -o jsonpath='{.items[*].metadata.name}')
for webPodName in ${webPodNames}
do
  # try pinging 8.8.8.8 and it should fail
  result=$(kubectl exec -it ${webPodName} -c python -- ping -c3 -w30 -q 8.8.8.8 2>/dev/null)
  if [[ $result =~ "100% packet loss" ]] ; then
    echo "Success: Web pod is not able to ping to 8.8.8.8."
    echo ${result}
  else
    echo "Failed: Web pod is not able to ping to 8.8.8.8."
    err ${result}
    exit 1
  fi

  # try pinging one of the nodes -- NODE_IP from previous run
  result=$(kubectl exec -it ${webPodName} -c python -- ping -c3 -w30 -q ${NODE_IP} 2>/dev/null)
  if [[ $? -ne 0 ]] ; then
    echo "Failed: Web pod is not able to ping to ${NODE_IP}."
    err ${result}
    exit 1
  elif ! [[ $result =~ "0% packet loss" ]] ; then
    echo "Failed: Web pod is not able to ping to ${NODE_IP}."
    err ${result}
    exit 1
  else
    echo "Success: Web pod is able to ping to ${NODE_IP}."
    echo ${result}
  fi
done

set -e
# delete all the yaml files
kubectl -v=6 delete -f $D/dbBackend.yaml
kubectl -v=6 delete -f $D/webFrontend.yaml
kubectl -v=6 delete -f $D/busyBox.yaml
kubectl -v=6 delete -f $D/networkPolicy.yaml

set +e
kubectl wait pod --for=delete -l name=mysql --timeout=60s 2>/dev/null
kubectl wait pod --for=delete -l name=web --timeout=60s 2>/dev/null
kubectl wait pod --for=delete -l name=busybox --timeout=60s 2>/dev/null

set -e

success $TEST

