# OpenShift Install

The OpenShift installer `openshift-install` makes it easy to get a cluster
running on the public cloud or your local infrastructure.

To learn more about installing OpenShift, visit [docs.openshift.com](https://docs.openshift.com)
and select the version of OpenShift you are using.

## Installing the tools

After extracting this archive, you can move the `openshift-install` binary
to a location on your PATH such as `/usr/local/bin`, or keep it in a temporary
directory and reference it via `./openshift-install`.

## License

OpenShift is licensed under the Apache Public License 2.0. The source code for this
program is [located on github](https://github.com/openshift/installer).



https://github.com/openshift/installer/blob/master/docs/user/metal/install_ipi.md

# Openshift get the ClusterOperator types/status (co)
oc get co
oc get ClusterOperators
oc get clusteroperators -w

# Describe the console cluster operator.
oc describe co console

# Get the pods in the ClusterOperator console operator
oc get pods -n openshift-console-operator

oc -n openshift-console get rs

oc get csr -A -o name | xargs oc adm certificate approve

# You need to make sure that the route from the command below points to the correct load balancer:
oc get routes -n openshift-authentication
# Then, check the URL with nslookup or with dig if it goes to the right destination with correct DNS

# AuthenticationOperator pod may be stuck. Delete it, it will be recreated immediately.
oc get pods -n openshift-authentication-operator
oc delete pod authentication-operator-<your_hash> -n openshift-authentication-operator

oc -n openshift-monitoring describe pod/prometheus-k8s-1

# Miscellaneous
oc get routes -n openshift-console

# When all done
INFO Install complete!
INFO Run 'export KUBECONFIG=<your working directory>/auth/kubeconfig' to manage the cluster with 'oc', the OpenShift CLI.
INFO The cluster is ready when 'oc login -u kubeadmin -p <provided>' succeeds (wait a few minutes).
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.demo1.openshift4-beta-abcorp.com
INFO Login to the console with user: kubeadmin, password: <provided>


# Run the NFD daemonset
oc adm policy add-scc-to-user privileged -z default -n efk

# Web console, which is the console clusteroperator
curl -v https://console-openshift-console.apps.openshift.local --insecure

# https://wiki.libvirt.org/page/Networking#NAT_forwarding_.28aka_.22virtual_networks.22.29
iptables -I FORWARD -o virbr0 -p tcp -d 192.168.122.9 --dport 443 -j ACCEPT
iptables -t nat -I PREROUTING -p tcp --dport 443 -j DNAT --to 192.168.122.9:443

# For support
https://docs.openshift.com/container-platform/4.1/support/gathering-cluster-data.html
https://openshift.tips/registries/

# Tools
```
kopeo copy docker://alpine:latest oci:alpine:latest
ls alpine
```
```
umoci unpack --image alpine:latest alpine-bundle
ls alpine-bundle
```

```
oc adm upgrade

oc debug node/master1
```