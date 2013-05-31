#!/usr/bin/env bash
BRANCH=rel
PWD=`pwd`
USER_SCRIPT="/opt/local/gnu/bin/echo 'http://release.project-fifo.net/pkg/${BRANCH}/' >> /opt/local/etc/pkgin/repositories.conf;\
/opt/local/bin/pkgin -fy up;\
/opt/local/bin/pkgin -y install snarl sniffle howl wiggle jingles;\
/opt/local/gnu/bin/cp /opt/local/jingles/config/nginx.conf /opt/local/etc/nginx/nginx.conf;\
/usr/sbin/svcadm enable epmd snarl sniffle howl wiggle nginx;\
/opt/local/gnu/bin/sleep 10;\
/opt/local/sbin/fifoadm users add admin;\
/opt/local/sbin/fifoadm users grant admin ...;\
/opt/local/sbin/fifoadm users passwd admin admin;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/erl_fun.json;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/syscalls.json;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/zfs_read.json;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/zfs_write.json
"

echo "================================================================================"
echo "Welcome to the Project FiFo express setup, this script will guide you through a "
echo "the process of setting up a first installation of Project FiFo."
echo "The script takes the following assumptions which should be true for your setup"
echo "for this to work propperly, other configurations are possible and for production"
echo "even encuranged but require more interaction and a deeper understanding of the"
echo "system."
echo
echo "Nessessary:"
echo " * Your Hypervisor has a admin network"
echo " * Your are not using special network setups (ethersubs, bounded network etc)"
echo
echo "Highly recommanded:"
echo " * a DHCP free setup."
echo " * a oficially tested version of SmartOS (chunter will complain if it is not)"
echo " * no zones with non uuid zone names (aliases are OK)"
echo
echo "Before we begin the installation we need some information:"
echo "================================================================================"

echo
echo "FiFo zone network setup"
read FIFO_IP   "IP:      "
read FIFO_MASK "Netmask: "
read FIFO_GW   "Gateway: "
echo
echo "Branch selection:"
echo " 1) development branch - this branch keeps track of the newest features it"
echo "    receives basic testing but there might be breaking changes intricuded."
echo "    In exchange all new features and advanced fixes land here within a"
echo "    matter of hours."
echo " 2) release branch - this branch undergoos a more careful testing before"
echo "    it is released, it only merges the changes from dev every so often in"
echo "    the form of a propperly numbered release. While there is no fixed"
echo "    release cycle new releases happen around every one to two month."

read FIFO_BRANCH "Release[1,2]: "
case $FIFO_BRANCH in
  "1")
    BRANCH=dev
    ;;
  "2")
    BRANCH=rel
    ;;
  *)
    echo "$FIFO_BRANCH is not a valid branch selection!"
    exit 1
  ;;
esac


imgadm update
imgadm import fdea06b0-3f24-11e2-ac50-0b645575ce9d

cat <<EOF | vmadm create
{
  "autoboot": true,
  "brand": "joyent",
  "image_uuid": "fdea06b0-3f24-11e2-ac50-0b645575ce9d",
  "max_physical_memory": 1024,
  "cpu_cap": 100,
  "alias": "fifo",
  "quota": "40",
  "resolvers": [
    "8.8.8.8",
    "8.8.4.4"
  ],
  "nics": [{
    "interface": "net0",
    "nic_tag": "admin",
    "ip": "${FIFO_IP}",
    "netmask": "${FIFO_MASK}",
    "gateway": "${FIFO_GW}"
  }],
  "metadata": {
    "user-script":"${USER_SCRIPT}"
  }
}
EOF

cd /opt
curl -O http://release.project-fifo.net/chunter/${BRANCH}/chunter-latest.gz
gunzip chunter-latest.gz
sh chunter-latest
cd $PWD
