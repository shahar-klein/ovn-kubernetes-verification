#!/bin/bash

BLUE="\033[01;94m"
BLACK="\033[0;0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"

function check_k8s_pod() {
	set -u
	namespace=$1
	name=$2
	num=$3

	OK=`kubectl -n $namespace get pods | grep $name | grep -c Running`
	if [ $OK -ne $num ] ; then
		echo "Expected $num running $name pods, but got $OK"
		exit 1
	fi
}

function title() {
	echo -e "$BLUE* $@$BLACK"
}

function err() {
	local m=${@:-Failed}
	TEST_FAILED=1
		echo -e "${RED}ERROR: $m$BLACK"
	return 1
}

function success() {
	local m=${@:-OK}
	m="$m Passed"
	echo -e "$GREEN$m$BLACK"
}

function cmd_on() {
	local host=$1
	shift
	local cmd=$@
	print=yes
	while ! ssh -q $host -C ls >& /dev/null ; do
		if [ $print == yes ] ; then 
			echo "Seems like this Host is not ready yet....waiting..."
			print=no
		fi
		if [ -t 1 ] ; then
			echo -n "."
		fi
		sleep 0.5
	done
	echo "[$host] $cmd"
	ssh $host "$cmd"
}

function pk_cmd_on() {
	local host=$1
	shift
	local pk=$1
	shift
	local user=$1
	shift
	local cmd=$@
	print=yes
	while ! ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $pk $user@$host -C ls >& /dev/null ; do
		if [ $print == yes ] ; then 
			echo "Seems like ($host) is not ready yet....waiting..."
			print=no
		fi
		if [ -t 1 ] ; then
			echo -n "."
		fi
		sleep 0.5
	done
	sleep 2
	echo
	echo "[$host] $cmd"
	ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $pk $user@$host -C "$cmd"
}

function vm_scp() {
	local host=$1
	shift
	local pk=$1
	shift
	local from=$1
	shift
	local to=$1
	echo "[$host] $from $to"
	scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $pk $from ubuntu@$host:$to
}

ping_wait_for() {
	local chars=( \| / – \\ )
	local i=0
	IP=$1
	
	title "Waiting for $IP.."
	while ! timeout 0.3 ping -c 1 -n $IP &> /dev/null ; do
		if [ -t 1 ] ; then 
			i=$((++i%4));
			echo "         (${chars[$i]})"
			echo -e "\033[2A"
		fi
		sleep 0.3

	done
}


