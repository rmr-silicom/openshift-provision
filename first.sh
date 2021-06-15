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
HOST_IP=$(hostname -A | awk '{print $1}')
ignition_url=http://${HOST_IP}:${WEB_PORT}
cluster_name="openshift"
base_domain="local"
VCPUS="4"
RAM_MB="8196"
DISK_GB="20"
# openshift_ver="4.7.0-0.okd-2021-03-07-090821"
openshift_ver="4.6.0-0.okd-2021-02-14-205305"
# openshift_ver="4.6.0-0.okd-2021-01-23-132511"
install_dir=$BASE/install_dir
WORKERS="0"
MASTERS="3"
ssh_opts="-i $BASE/files/node -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
INSTALLER=$BASE/bin/openshift-install
OC=$BASE/bin/oc
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
  exit 0
fi

setup_fcos() {
  fcos_ver="33.20210217.3.0"
  fedora_base="fedora-coreos"
  image_base="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${fcos_ver}/x86_64"
  image_url=${image_base}/fedora-coreos-${fcos_ver}-metal.x86_64.raw.xz
  rootfs_url=${image_base}/fedora-coreos-${fcos_ver}-live-rootfs.x86_64.img
  initramfs_url=${image_base}/fedora-coreos-${fcos_ver}-live-initramfs.x86_64.img
  kernel_url=${image_base}/fedora-coreos-${fcos_ver}-live-kernel-x86_64
  downloads=$BASE/downloads/openshift-v4/dependencies/fcos/${fcos_ver}
  ocp_install_url=https://github.com/openshift/okd/releases/download/${openshift_ver}/openshift-install-linux-${openshift_ver}.tar.gz
  ocp_client_url=https://github.com/openshift/okd/releases/download/${openshift_ver}/openshift-client-linux-${openshift_ver}.tar.gz
}

setup_rhcos() {
  rhcos_ver=4.6
  rhcos_release_ver=latest
  image_base=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${rhcos_ver}/${rhcos_release_ver}
  image_url=${image_base}/rhcos-metal.x86_64.raw.gz
  kernel_url=${image_base}/rhcos-live-kernel-x86_64
  rootfs_url=${image_base}/rhcos-live-rootfs.x86_64.img
  initramfs_url=${image_base}/rhcos-live-initramfs.x86_64.img
  downloads=$BASE/downloads/openshift-v4/dependencies/rhcos/${rhcos_ver}/${rhcos_release_ver}
  ocp_client_url=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.6.23/openshift-client-linux.tar.gz
  ocp_install_url=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.6.23/openshift-install-linux.tar.gz
}

start_fileserver() {
  if $(docker ps | grep "static-file-server" > /dev/null 2>&1) ; then
      docker rm -f static-file-server
  fi

  cp $downloads/*.img ${install_dir}
  docker run -d --name static-file-server --rm  -v ${install_dir}:/web -p ${WEB_PORT}:${WEB_PORT} -u $(id -u):$(id -g) halverneus/static-file-server:latest
  sleep 1
  curl ${HOST_IP}:8080/master.ign -s > /dev/null
}

cleanup() {

  if [ ! -e $downloads ] ; then
    mkdir -p $downloads
  fi

  [ ! -e $downloads/image.img ] && wget ${image_url} -O $downloads/image.img
  [ ! -e $downloads/rootfs.img ] && wget ${rootfs_url} -O $downloads/rootfs.img
  [ ! -e $downloads/kernel.img ] && wget ${kernel_url} -O $downloads/kernel.img
  [ ! -e $downloads/initramfs.img ] && wget ${initramfs_url} -O $downloads/initramfs.img
  [ ! -e $downloads/install.tar.gz ] && wget $ocp_install_url -O $downloads/install.tar.gz
  [ ! -e $downloads/client.tar.gz ] && wget $ocp_client_url -O $downloads/client.tar.gz
  [ ! -e $BASE/bin ] && mkdir -p $BASE/bin

  rm $BASE/bin/*
  tar xvf $downloads/install.tar.gz -C $BASE/bin/
  tar xvf $downloads/client.tar.gz -C $BASE/bin/
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

  $INSTALLER create manifests --dir=${install_dir}
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

  $INSTALLER create ignition-configs --dir=${install_dir}

  podman run --pull=always -i --rm quay.io/coreos/fcct -p -s <$BASE/files/lb.fcc > ${install_dir}/lb.ign
	# podman run --rm -ti --volume $(pwd):/srv:z quay.io/ryan_raasch/filetranspiler:latest -i /srv/files/baseconfig.yaml -f /srv/fakeroot --format=yaml --dereference-symlinks | sed 's/^/     /' >> $(pwd)/$(OUTPUT_YAML)

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

  qemu-img create -f $disk_type ${disk} ${DISK_GB}G
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
  device="$(lsusb -d 0424:2660)"
  if [ ! -z "$device" ] && [ $hostname = "worker2" ] ; then
    lspci_args=" --hostdev 0424:2660 "
    lspci_args=" $lspci_args --hostdev 1546:01a9 "
    lspci_args=" $lspci_args --hostdev 1374:0001 "
    for arg in $(lspci -d 8086:1591 | awk '{ print $1 }') ; do
      lspci_args=" $lspci_args --hostdev $arg,address.function=$(echo $arg | cut -d . -f 2),address.type='pci'"
    done
#    addr="$(basename $(dirname $(realpath /sys/bus/pci/devices/$(lspci -D -d 8086:1591 | head -n1 | awk '{print $1}'))))"
#    lspci_args=" $lspci_args --controller $addr,type=pci,address.type=pci,address.multifunction='on',model='pcie-root-port',index='10'"
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

while ! $(nc -v -z -w 1 master$MASTERS.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for master$MASTERS"
  sleep 30
done
date

while ! $(ssh ${ssh_opts} core@bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/cco-bootstrap.done ]") ; do
  echo -n "Waiting for cco-bootstrap.done"
  sleep 30
done
date

$INSTALLER --dir=${install_dir} wait-for bootstrap-complete --log-level debug

while ! $(ssh ${ssh_opts} core@bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/cb-bootstrap.done ]") ; do
  echo -n "Waiting for cb-bootstrap.done"
  sleep 30
done
date

while ! $(ssh ${ssh_opts} core@bootstrap.${cluster_name}.${base_domain} "[ -e /opt/openshift/.bootkube.done ]") ; do
  echo -n "Waiting for .bootkube.done"
  sleep 30
done
date

$INSTALLER gather bootstrap --dir=${install_dir}

virsh destroy bootstrap
virsh undefine bootstrap --remove-all-storage

virsh destroy lb
sed -i '/bootstrap/d' $BASE/lb.fcc
virsh start "lb"
while ! $(nc -v -z -w 1 lb.openshift.local 22 > /dev/null 2>&1); do
  echo "Waiting for lb"
  sleep 30
done

sleep 480

$OC get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty $OC adm certificate approve
$OC get csr -o name | xargs oc adm certificate approve

while ! $(oc get nodes | grep -q worker1) ; do
  $OC get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty $OC adm certificate approve
  $OC get csr -o name | xargs oc adm certificate approve
  sleep 300
done

$INSTALLER --dir=${install_dir} wait-for install-complete --log-level debug


# $OC apply -f ${BASE}/files/silicom-registry.yaml

cp -av $KUBECONFIG ~/.kube/

sleep 60

$OC get csr -o name | xargs oc adm certificate approve

# $OC apply -f ${BASE}/files/nfd-daemonset.yaml
