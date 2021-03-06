#!/bin/bash

#
# https://kxr.me/2019/08/17/openshift-4-upi-install-libvirt-kvm/
#


#
# https://getfedora.org/en/coreos/download?tab=metal_virtualized&stream=stable
#

set -x

BASE=$(dirname $(realpath "${BASH_SOURCE[0]}"))
WEB_PORT=8080
HOST_IP=192.168.122.1
ignition_url=http://${HOST_IP}:${WEB_PORT}
cluster_name="openshift"
base_domain="local"
VCPUS="4"
RAM_MB="8196"
DISK_GB="20"
DISK_GB_WORKER="30"
install_dir=$BASE/install_dir
WORKERS="0"
MASTERS="3"
ssh_opts="-l core -i $BASE/files/node -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export PATH=${PATH}:$BASE/bin
export KUBECONFIG=${install_dir}/auth/kubeconfig
disk_type="raw"
DESTROY="no"

# Process Arguments
while [[ $# -gt 0 ]] ; do
  case $1 in
      -m|--masters)
      MASTERS="$2"
      shift
      shift
      ;;
      -w|--workers)
      WORKERS="$2"
      shift
      shift
      ;;
      -r|--ram)
      RAM_MB="$2"
      shift
      shift
      ;;
      -d|--disk)
      DISK_GB="$2"
      shift
      shift
      ;;
      --destroy)
      DESTROY="yes"
      shift
      ;;
      *)
      shift
      ;;
  esac
done

if ! $(swapon | grep -q swapfile) ; then
  echo "Enable swap";
#  exit 0
fi

setup_fcos() {
  fcos_ver="35.20220131.3.0"
  fedora_base="fedora-coreos"
  # okd_version="4.7.0-0.okd-2021-03-07-090821"
  # okd_version="4.6.0-0.okd-2021-02-14-205305"
  # okd_version="4.6.0-0.okd-2021-01-23-132511"
  # okd_version="4.7.0-0.okd-2021-08-07-063045"
  okd_version="4.9.0-0.okd-2022-02-12-140851"
  image_base="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${fcos_ver}/x86_64"
  image_url=${image_base}/fedora-coreos-${fcos_ver}-metal.x86_64.raw.xz
  rootfs_url=${image_base}/fedora-coreos-${fcos_ver}-live-rootfs.x86_64.img
  initramfs_url=${image_base}/fedora-coreos-${fcos_ver}-live-initramfs.x86_64.img
  kernel_url=${image_base}/fedora-coreos-${fcos_ver}-live-kernel-x86_64
  downloads=$BASE/downloads/openshift-v4/dependencies/fcos/${fcos_ver}
  ocp_install_url=https://github.com/openshift/okd/releases/download/${okd_version}/openshift-install-linux-${okd_version}.tar.gz
  ocp_client_url=https://github.com/openshift/okd/releases/download/${okd_version}/openshift-client-linux-${okd_version}.tar.gz
}

setup_rhcos() {
  rhcos_ver=4.8
  ocp_client_ver=4.8.39
  rhcos_release_ver=latest

  image_base=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${rhcos_ver}/${rhcos_release_ver}
  image_url=${image_base}/rhcos-metal.x86_64.raw.gz
  kernel_url=${image_base}/rhcos-live-kernel-x86_64
  rootfs_url=${image_base}/rhcos-live-rootfs.x86_64.img
  initramfs_url=${image_base}/rhcos-live-initramfs.x86_64.img
  downloads=$BASE/downloads/openshift-v4/dependencies/rhcos/${rhcos_ver}/${rhcos_release_ver}
  downloads_utils=$BASE/downloads/${ocp_client_ver}
  ocp_client_url=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_client_ver}/openshift-client-linux.tar.gz
  ocp_install_url=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${ocp_client_ver}/openshift-install-linux.tar.gz
}

check() {
    if $(systemctl status ModemManager > /dev/null 2>&1); then
    echo "Disable ModemManager!"
    echo "systemctl disable ModemManager"
    echo "systemctl stop ModemManager"
    exit 0
  fi

  if ! $(grep -q 'intel_iommu=on' /proc/cmdline); then
    echo "Update /proc/cmdline to have, using /boot/grub/grub.cfg"
    echo "intel_iommu=on"
    exit 0
  fi

  if ! $(grep -q 'vfio-pci.ids=1c2c:1000,8086:6f0a,8086:8d31' /proc/cmdline); then
    echo "Update /proc/cmdline to have, using /boot/grub/grub.cfg"
    echo "vfio-pci.ids=1c2c:1000,8086:8d31"
    exit 0
  fi
}

start_fileserver() {
  docker rm -f $(docker ps -a -q) > /dev/null 2>&1
  cp $downloads/*.img ${install_dir}
  docker run -d --name static-file-server --rm  -v ${install_dir}:/web -p ${WEB_PORT}:${WEB_PORT} -u $(id -u):$(id -g) docker.io/halverneus/static-file-server:latest
  sleep 1
  curl ${HOST_IP}:8080/master.ign -s > /dev/null
}

cleanup() {

  if [ ! -e $downloads ] ; then
    mkdir -p $downloads
  fi

  if [ ! -e $downloads_utils ] ; then
    mkdir -p $downloads_utils
  fi

  [ ! -e $downloads/image.img ] && wget ${image_url} -O $downloads/image.img
  [ ! -e $downloads/rootfs.img ] && wget ${rootfs_url} -O $downloads/rootfs.img
  [ ! -e $downloads/kernel.img ] && wget ${kernel_url} -O $downloads/kernel.img
  [ ! -e $downloads/initramfs.img ] && wget ${initramfs_url} -O $downloads/initramfs.img
  [ ! -e $downloads_utils/install.tar.gz ] && wget $ocp_install_url -O $downloads_utils/install.tar.gz
  [ ! -e $downloads_utils/client.tar.gz ] && wget $ocp_client_url -O $downloads_utils/client.tar.gz
  [ ! -e $BASE/bin ] && mkdir -p $BASE/bin

  rm $BASE/bin/*
  tar xvf $downloads_utils/install.tar.gz -C $BASE/bin/
  tar xvf $downloads_utils/client.tar.gz -C $BASE/bin/
  chmod +x  $BASE/bin/*

  if [ -e .openshift_install.log ] ; then
    rm .openshift_install*
  fi

  [ -e ${install_dir} ] && rm -rf ${install_dir}
  mkdir -p ${install_dir}

cat <<EOF > ${install_dir}/install-config.yaml
apiVersion: v1
baseDomain: ${base_domain}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: ${WORKERS}
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${MASTERS}
metadata:
  name: ${cluster_name}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
fips: false
pullSecret: '$(cat ${BASE}/files/pull-secret.json)'
sshKey: '$(cat ${BASE}/files/node.pub)'
EOF

  openshift-install create manifests --dir=${install_dir}
  if [ "$WORKERS" = "0" ] ; then
    sed -i 's/mastersSchedulable: false/mastersSchedulable: false/g' ${install_dir}/manifests/cluster-scheduler-02-config.yml
    sed -i 's/worker1 worker1.openshift.local/master1 master1.openshift.local/g' $BASE/files/lb.fcc
    sed -i 's/worker2 worker2.openshift.local/master2 master2.openshift.local/g' $BASE/files/lb.fcc
    sed -i 's/worker3 worker3.openshift.local/master3 master3.openshift.local/g' $BASE/files/lb.fcc
  else
    sed -i 's/mastersSchedulable: true/mastersSchedulable: false/g' ${install_dir}/manifests/cluster-scheduler-02-config.yml
  fi

  if [ "$WORKERS" = "2" ] ; then
    sed -i '/worker3 worker3.openshift.local/d' $BASE/files/lb.fcc
  fi

  # Can't get to work, for now...
	# cp $BASE/files/machineconfig/*.yaml $install_dir/openshift/

  openshift-install create ignition-configs --dir=${install_dir}

  docker run -i --rm quay.io/coreos/fcct -p -s <$BASE/files/lb.fcc > ${install_dir}/lb.ign

  # The current version of fcct produces ignition 3.2.0 where RHCOS ignition can only handle 3.1.0
  sed -i "s/\"version\": \"3.2.0\"/\"version\": \"3.1.0\"/g" ${install_dir}/lb.ign

  while $(virsh list --state-running --state-paused | grep -q -e running -e paused ); do
    virsh destroy $(virsh list --state-running --state-paused --name | head -n1)
  done

  while [ ! -z "$(virsh list --all --name)" ] ; do
    virsh undefine $(virsh list --all --name | head -n1) --remove-all-storage
  done

  while [ ! -z "$(ls ${BASE}/*.$disk_type)" ] ; do
    rm -f $(ls ${BASE}/*.$disk_type | head -n1)
  done

  if $(virsh net-list | grep -q default); then
    virsh net-destroy default
    virsh net-undefine default
  fi

  virsh net-define --file ${BASE}/files/default.xml
  virsh net-start default
}

create_vm() {
  local hostname=$1
  local disk=${BASE}/${hostname}.$disk_type

  if [ $hostname = "worker1" ] || [ $hostname = "worker2" ] ; then
    qemu-img create -f $disk_type ${disk} ${DISK_GB_WORKER}G
  else
    qemu-img create -f $disk_type ${disk} ${DISK_GB}G
  fi

  chmod a+wr ${disk}

  device="$(lspci -d 1c2c:1000 | awk '{ print $1 }')"
  lspci_args=""
  if [ $hostname = "worker1" ] ; then
    if [ ! -z "$device" ] ; then
      lspci_args="--hostdev $device"
    fi
  fi

  # https://github.com/andre-richter/vfio-pci-bind/blob/master/25-vfio-pci-bind.rules
  # Check for STS2 card, and enable passthrough for USB and Columbiaville
  if [ $hostname = "worker2" ] ; then
      for arg in $(lspci -d 8086:1591 | awk '{ print $1 }') ; do
        lspci_args=" $lspci_args --hostdev $arg,address.domain=0,address.bus=0x2,address.slot=0x0,address.function=$(echo $arg | cut -d . -f 2),address.type='pci'"
      done
  fi

  virt-install --connect="qemu:///system" --name="${1}" --vcpus="${VCPUS}" --memory="${2}" \
          --virt-type kvm \
          --machine q35 \
          --accelerate \
          --hvm $lspci_args \
          --os-variant rhl9 \
          --network network=default,mac="$(virsh net-dumpxml default | grep $hostname | grep mac | sed "s/ name=.*//g" | sed -n "s/.*mac='\(.*\)'/\1/p")" \
          --graphics=none \
          --noautoconsole \
          --noreboot \
          --disk=${disk} \
          --install kernel=$downloads/kernel.img,initrd=$downloads/initramfs.img \
          --extra-args "rd.neednet=1 coreos.inst.install_dev=/dev/sda coreos.inst=yes console=ttyS0 coreos.live.rootfs_url=http://${HOST_IP}:8080/rootfs.img coreos.inst.insecure coreos.inst.ignition_url=${ignition_url}/${3} coreos.inst.image_url=http://${HOST_IP}:8080/image.img"
}

if ! $(grep -v '#' /etc/resolv.conf | head -n 1 | grep -q "nameserver 192.168.122.1"); then
  echo "Please add nameserver 192.168.122.1 as first line in /etc/resolv.conf"
  exit 0
fi

check
setup_rhcos
cleanup

if [ $DESTROY = "yes" ] ; then
  exit 0
fi

start_fileserver
create_vm "lb" "6000" "lb.ign"
create_vm "bootstrap" "8000" "bootstrap.ign"

for i in $(seq 1 $MASTERS) ; do
    create_vm "master$i" "${RAM_MB}" "master.ign"
done

for i in $(seq 1 $WORKERS) ; do
    create_vm "worker$i" "${RAM_MB}" "worker.ign"
done

while [ ! -z "$(virsh list --state-running --name)" ] ; do
  echo "waiting"
  sleep 5;
done

virsh start "lb"
while ! $(nc -v -z -w 1 lb.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for lb"
  sleep 30
done

for i in $(seq 1 $MASTERS) ; do
    virsh start "master$i"
done

virsh start "bootstrap"
while ! $(nc -v -z -w 1 lb.openshift.local 6443 > /dev/null 2>&1); do
  echo "Waiting for bootstrap"
  sleep 30
done

for i in $(seq 1 $WORKERS) ; do
    virsh start "worker$i"
done

while ! $(nc -v -z -w 1 master1.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for master1"
  sleep 30
done

while ! $(ssh ${ssh_opts} bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/cco-bootstrap.done ]") ; do
  echo -n "Waiting for cco-bootstrap.done"
  sleep 30
done

openshift-install --dir=${install_dir} wait-for bootstrap-complete --log-level debug

while ! $(ssh ${ssh_opts} bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/cb-bootstrap.done ]") ; do
  echo -n "Waiting for cb-bootstrap.done"
  sleep 30
done

while ! $(ssh ${ssh_opts} bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/.bootkube.done ]") ; do
  echo -n "Waiting for .bootkube.done"
  sleep 30
done

openshift-install gather bootstrap --dir=${install_dir} --bootstrap=bootstrap.openshift.local --master=master1.openshift.local --log-level=debug

virsh destroy bootstrap
virsh undefine bootstrap --remove-all-storage

virsh destroy lb
virsh start lb
while ! $(nc -v -z -w 1 lb.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for lb"
  sleep 30
done

sleep 480

oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty oc adm certificate approve
oc get csr -o name | xargs oc adm certificate approve

if [ $WORKERS != "0" ] ; then
  while ! $(oc get nodes | grep -q worker1) ; do
    oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty oc adm certificate approve
    oc get csr -o name | xargs oc adm certificate approve
    sleep 300
  done
fi

sleep 300
oc get csr -o name | xargs oc adm certificate approve
openshift-install --dir=${install_dir} wait-for install-complete --log-level debug

# https://puiterwijk.org/posts/rhel-containers-on-non-rhel-hosts/
cd ${BASE}/files/machineconfig && ./99-registries.sh > ./99-registries.yaml && cd -

# https://cloud.redhat.com/blog/how-to-use-entitled-image-builds-to-build-drivercontainers-with-ubi-on-openshift
oc apply -f ${BASE}/files/machineconfig/0000-disable-secret-automount.yaml

cp -av $KUBECONFIG ~/.kube/

sleep 60

oc get csr -o name | xargs oc adm certificate approve
# https://docs.openshift.com/container-platform/4.8/registry/configuring-registry-operator.html
# oc apply -f files/pv.yaml

oc patch config.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"rolloutStrategy":"Recreate","replicas":1}}'
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'
oc patch config cluster -n openshift-image-registry --type merge --patch '{"spec": { "managementState": "Managed"}}'

oc apply -f ${BASE}/files/cleanup.yaml
sleep 300
# oc apply -f ${BASE}/files/nfd-operator.yaml
#sleep 120
#oc apply -f ${BASE}/files/nfd-cr.yaml
oc delete pod --field-selector=status.phase==Succeeded --all-namespaces

oc patch clusterversion/version -p '{"spec":{"channel":"candidate-4.8"}}' --type=merge

if ! $(oc describe configs.imageregistry.operator.openshift.io cluster | grep "Management State:" | grep -q Managed) ; then
    echo "Registry not enabled."
    oc patch config.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"rolloutStrategy":"Recreate","replicas":1}}'
    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'
    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'
fi

virsh attach-device --file $BASE/files/pci-$(hostname).xml worker2 --config
virsh destroy worker2
virsh start worker2

GUEST_IP=192.168.122.9
GUEST_PORT=6443
sudo iptables -I FORWARD -o virbr0 -p tcp -d $GUEST_IP --dport $GUEST_PORT -j ACCEPT
sudo iptables -t nat -I PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to $GUEST_IP:$GUEST_PORT
