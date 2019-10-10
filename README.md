# ovn-kubernetes-verification

CI/CD pipeline for ovn-kubernetes

The gitlab project is in here:
https://gitlab-master.nvidia.com/sdn/ovn-kubernetes

Triggers: push to branches **master** and  **nv-ovn-kubernetes**.
	      MR to branch  **nv-ovn-kubernetes**.

A trigger launches a jenkins job(https://ngneng.jenkins.ngn.nvidia.com/job/ovn-kubernetes-build-and-test/configure)

The job checkout and build the code then publish the image to:

nv-ovn-kubernetes: quay.io/nvidia/ovnkube…
master/MR: quay.io/sklein/ovn-kube….

Then calls this project for testing.
(https://gitlab-master.nvidia.com/sdn/ovn-kubernetes-verification)

Entry point is: install-ovn-k8s.bash
This script checkout again and:
make
make check
make lint
make gofmt

Then installs ovn-kubernetes and run tests:

The tests entry point is: 
bash runtests.sh

If the tests passes it publishes the yamls with the relevant images to: k8s-yaml.git

