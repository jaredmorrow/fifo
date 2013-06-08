#!/usr/bin/env bash
BRANCH=rel
PWD=`pwd`

function line() {
    echo "================================================================================"
}
function section() {
    echo
    echo
    echo
    echo
    line
    echo "          $1"
    line
}

line
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


section "Network Setup for the FiFo zone."
echo -n  "IP:      "
read FIFO_IP
echo -n  "Netmask: "
read FIFO_MASK
echo -n "Gateway: "
read FIFO_GW

section "Branch Selection"
echo " rel) release branch - this branch undergoos a more careful testing before"
echo "      it is released, it only merges the changes from dev every so often in"
echo "      the form of a propperly numbered release. While there is no fixed"
echo "      release cycle new releases happen around every one to two month."
echo " dev) development branch - this branch keeps track of the newest features it"
echo "      receives basic testing but there might be breaking changes intricuded."
echo "      In exchange all new features and advanced fixes land here within a"
echo "      matter of hours."
echo
echo -n "Release[dev,rel]: "
read FIFO_BRANCH
case $FIFO_BRANCH in
    "dev")
        BRANCH=dev
        ;;
    "rel")
        BRANCH=rel
        ;;
    *)
        echo "$FIFO_BRANCH is not a valid branch selection!"
        exit 1
        ;;
esac

USER_SCRIPT="/opt/local/gnu/bin/echo 'http://release.project-fifo.net/pkg/${BRANCH}/' >> /opt/local/etc/pkgin/repositories.conf;\
export PATH=/opt/local/gnu/bin:/opt/local/bin:/opt/local/sbin:/usr/bin:/usr/sbin;\
export HOME=/root;\
> /tmp/stage_1;\
/opt/local/bin/pkgin -fy up;\
> /tmp/stage_2;\
/opt/local/bin/pkgin -y install snarl;\
> /tmp/stage_3;\
/opt/local/bin/pkgin -y install sniffle;\
> /tmp/stage_4;\
/opt/local/bin/pkgin -y install howl;\
> /tmp/stage_5;\
/opt/local/bin/pkgin -y install wiggle;\
> /tmp/stage_6;\
/opt/local/bin/pkgin -y install jingles;\
> /tmp/stage_7;\
/opt/local/gnu/bin/cp /opt/local/jingles/config/nginx.conf /opt/local/etc/nginx/nginx.conf;\
> /tmp/stage_8;\
/usr/sbin/svcadm enable epmd;\
> /tmp/stage_9;\
/usr/sbin/svcadm enable wiggle;\
while ! /opt/local/wiggle/bin/wiggle ping>/dev/null; do echo -n .; done;\
> /tmp/stage_10;\
/usr/sbin/svcadm enable howl;\
while ! /opt/local/howl/bin/howl ping>/dev/null; do echo -n .; done;\
> /tmp/stage_11;\
/usr/sbin/svcadm enable sniffle;\
while ! /opt/local/sniffle/bin/sniffle ping>/dev/null; do echo -n .; done;\
> /tmp/stage_12;\
/usr/sbin/svcadm enable snarl;\
while ! /opt/local/snarl/bin/snarl ping>/dev/null; do echo -n .; done;\
> /tmp/stage_13;\
/usr/sbin/svcadm enable nginx;\
/opt/local/gnu/bin/sleep 10;\
> /tmp/stage_14;\
/opt/local/sbin/fifoadm users add admin;\
> /tmp/stage_15;\
/opt/local/sbin/fifoadm users grant admin ...;\
> /tmp/stage_16;\
/opt/local/sbin/fifoadm users passwd admin admin;\
> /tmp/stage_17;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/erl_fun.json;\
> /tmp/stage_18;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/syscalls.json;\
> /tmp/stage_19;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/zfs_read.json;\
> /tmp/stage_20;\
/opt/local/sbin/fifoadm dtrace import /opt/local/sniffle/share/dtrace/zfs_write.json;\
> /tmp/stage_21"

section  "Chunter Installation"
cd /opt
curl -O http://release.project-fifo.net/chunter/${BRANCH}/chunter-latest.gz > /dev/null
gunzip chunter-latest.gz
sh chunter-latest
cd $PWD

section  "Dataset Installation"
imgadm update
imgadm import fdea06b0-3f24-11e2-ac50-0b645575ce9d

section  "Zone Creation"
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
  "mdata_exec_timeout":0,
  "nics": [{
    "interface": "net0",
    "nic_tag": "admin",
    "ip": "${FIFO_IP}",
    "netmask": "${FIFO_MASK}",
    "gateway": "${FIFO_GW}"
  }],
  "customer_metadata": {
    "user-script":"${USER_SCRIPT}"
  },
  "metadata": {
    "user-script":"${USER_SCRIPT}"
  }
}
EOF

UUID=`vmadm list -p -o uuid`

function percent_bar() {
    sleep 1
    echo -ne '\b\\'
    sleep 1
    echo -ne '\b|'
    sleep 1
    echo -ne '\b/'
    sleep 1
    echo -ne '\b-'
}

function wait_for_file () {
    while [ ! -f /zones/$UUID/root/tmp/$1 ]
    do
        percent_bar
    done
    echo -ne '\b\b\b\b\b\b\b=> '
    echo -n ${2}% -

}

section  "Zone Setup / FiFo Installion"

echo -n '[> 00% -'
wait_for_file stage_1 05
wait_for_file stage_2 10
wait_for_file stage_3 15
wait_for_file stage_4 20
wait_for_file stage_5 25
wait_for_file stage_6 30
wait_for_file stage_7 35
wait_for_file stage_8 40
wait_for_file stage_9 45
wait_for_file stage_10 50
wait_for_file stage_11 55
wait_for_file stage_12 60
wait_for_file stage_13 65
wait_for_file stage_14 70
wait_for_file stage_15 75
wait_for_file stage_16 80
wait_for_file stage_17 85
wait_for_file stage_18 90
wait_for_file stage_19 93
wait_for_file stage_20 98
wait_for_file stage_21 100
echo -en '\b'
echo 'done.'
echo
echo
echo
echo
echo
echo
echo
line
echo "You should now be able to access your installation at:"
echo
echo "URL: https://${FIFO_IP}"
echo
echo "With the credentials:"
echo " User:     admin"
echo " Password: admin"
echo
echo "Don't be surprised if you see a warning about missing hypervisors"
echo "the autoconfiguration algorithm used can take up to two mintes"
echo "for the first round of discovery."
echo
echo "Enjoy,"
echo "the Project-FiFo team."
line
