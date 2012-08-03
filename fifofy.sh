#!/usr/bin/env bash
BASE_PATH="__BASE_URL__"
RELEASE="__REL__"
REDIS_DOMAIN="fifo"
DOMAIN="local"
COOKIE="fifo"
DATASET="8da4bc54-d77f-11e1-8f6f-cfe8e7177a23"

msg() {
    if [ "${N}" == "true" ]
    then
	echo -n "$1"
	echo -n "$1" &>> /var/log/fifo-install.log

    else
	echo "[$C] $1"
	echo "[$C] $1" &>> /var/log/fifo-install.log
    fi
}

n_msg_start() {
    N="true"
    echo -n "[$C] $1"
    echo -n "[$C] $1" &>> /var/log/fifo-install.log
}
n_msg_end() {
    N=""
    echo "$1"
    echo "$1" &>> /var/log/fifo-install.log
}


install_dnsmasq(){
    C="dnsmasq"
    msg "Starting dnsmasq installation."
    pkgin -y install dnsmasq
    cat <<EOF > /opt/local/etc/dnsmasq.conf
domain-needed
bogus-priv
strict-order
expand-hosts
domain=local
server=$ZONE_DNS

addn-hosts=/fifo/hosts

# For debugging purposes, log each DNS query as it passes through
log-queries
EOF
    
    echo <<EOF > /fifo/hosts
$HYPERVISOR_IP $HOSTNAME.local
EOF
    svcadm enable dnsmasq
    echo "nameserver 127.0.0.1" > /etc/resolv.conf
}


error() {
    msg "[ERROR] $1"
    msg "[ERROR] I'm going to stop now, please look at /var/log/fifo/fifo-install.log for details."
    exit 1
}

download() {
    curl -sLkO "$1" &>> /var/log/fifo-install.log || error "Failed to download $1"
}

install_py_pkg() {
    msg "Installing: $1"
    cd $1
    /opt/local/bin/python2.7 setup.py install  &>> /var/log/fifo-install.log || error "Failed to install $1"
    cd ..
}

install_graphit() {
    C="GRAPHIT"
    msg "Starting installation"
    cd /fifo/modules
    msg "Updating packages"
    /opt/local/bin/pkgin update &>> /var/log/fifo-install.log
    msg "Installing required packages (this will take a while!)"
    n_msg_start "Installing packages"
    for pkg in python27 nodejs-0.8.3 py27-memcached memcached py27-ZopeInterface cairo ap22-py27-python py27-django sqlite ap22-py27-wsgi py27-sqlite2 sqlite py27-twisted gcc47-4.7.0nb1 gmake pkg-config xproto renderproto kbproto
    do
	msg " $pkg"
	/opt/local/bin/pkgin -y install $pkg &>> /var/log/fifo-install.log || error "Failed to install package ${pgk}."
    done
    n_msg_end " done."
    export PATH="$PATH:/opt/local/bin"
    msg "Installing statsd"
    /opt/local/bin/npm install statsd &>> /var/log/fifo-install.log || error "Failed to install npm package statsd."
    
    msg "Installing: py2cairo"
    cd py2cairo-1.10.0
    CC=/opt/local/bin/gcc CFLAGS=-m64 LDFLAGS=-m64 /opt/local/bin/python2.7 waf configure --prefix=/opt/local  &>> /var/log/fifo-install.log || error "Could not configure py2cairo."
    CC=/opt/local/bin/gcc CFLAGS=-m64 LDFLAGS=-m64 /opt/local/bin/python2.7 waf build  &>> /var/log/fifo-install.log || error "Could not build py2cairo."
    CC=/opt/local/bin/gcc CFLAGS=-m64 LDFLAGS=-m64 /opt/local/bin/python2.7 waf install  &>> /var/log/fifo-install.log || error "Could not install py2cairo."
    cd ..

    install_py_pkg whisper-0.9.10
    install_py_pkg django-tagging-0.3.1
    install_py_pkg graphite-web-0.9.10
    install_py_pkg carbon-0.9.10

    mkdir -p /opt/graphite/storage/log/carbon-cache

    msg "Configuring: carbon"
    cd /opt/graphite/conf
    cp carbon.conf.example carbon.conf
    cp storage-schemas.conf.example storage-schemas.conf
    cat <<EOF >>storage-schemas.conf
[stats]
priority = 110
pattern = ^stats\..*
retentions = 1:1h,10:2160,60:10080,600:262974
EOF
    cd -
    msg "Configuring: web frontend"
    cd /opt/graphite/webapp/graphite
    cp local_settings.py.example local_settings.py
    cp /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi
    sed -e 's/Listen 0.0.0.0:80/Listen 0.0.0.0:8080/' -ibak /opt/local/etc/httpd/httpd.conf
    echo "LoadModule wsgi_module lib/httpd/mod_wsgi.so" >> /opt/local/etc/httpd/httpd.conf
    echo "Include etc/httpd/httpd-vhosts.conf" >> /opt/local/etc/httpd/httpd.conf
    curl -s $BASE_PATH/$RELEASE/httpd-vhosts.conf > /opt/local/etc/httpd/httpd-vhosts.conf 
    msg "Configuring: database"
    /opt/local/bin/python2.7 manage.py syncdb --noinput  &>> /var/log/fifo-install.log
    /opt/local/bin/python2.7 manage.py createsuperuser --username=admin --email=admin@localhost.local --noinput  &>> /var/log/fifo-install.log
    echo 'UPDATE auth_user SET password="sha1$4557a$674798faef13ba7192efad47fb9fc7021fbcf919" WHERE username="admin";' | sqlite3 /opt/graphite/storage/graphite.db  &>> /var/log/fifo-install.log
    cd -

    /opt/local/bin/chown -R www:www /opt/graphite/

    cd /fifo
    msg "Downloading service descriptors"
    curl -sO $BASE_PATH/$RELEASE/statsdconfig.js
    curl -sO $BASE_PATH/$RELEASE/statsd.xml
    curl -sO $BASE_PATH/$RELEASE/carbon.xml
    msg "Enabeling services"
    svcadm enable apache &>> /var/log/fifo-install.log 
    svccfg import statsd.xml &>> /var/log/fifo-install.log
    svccfg import carbon.xml &>> /var/log/fifo-install.log
    cd -
    msg "done"
}

uninstall() {
    UUID=`vmadm list -p -o uuid zonename=fifo`
    vmadm delete $UUID
    svcadm disable chunter
    svcadm disable epmd
    svccfg delete -f chunter
    svccfg delete -f epmd
    /opt/chunter/bin/chunter stop
    rm -rf /opt/chunter
    rm -rf /var/log/fifo*
    ps -afe | grep epmd | awk '{print $2}' | xargs kill
}
read_ip() {
    if [ "x${IP1}x" == "xx" ]
    then
	if [ "x${1}x" != "xx" ]
	then
	    read -p "ip($1)> " IP
	    if [ "x${IP}x" == "xx" ]
	    then
		IP=$1
	    fi
	else
	    read -p "ip> " IP
	fi
    else
	IP=$IP1
	if [ "$IP" == "-d" ]
	then
	    IP=$1
	fi
	IP1=$IP2
	IP2=$IP3
	IP3=$IP4
	IP4=$IP5
	IP5=""
    fi
    
    if echo $IP | grep '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' > /dev/null
    then
	true
    else
	echo "Invalid IP address: $IP."
	read_ip
    fi
}


read_value() {
    if [ "x${IP1}x" == "xx" ]
    then
	if [ "x${1}x" != "xx" ]
	then
	    read -p "ip($1)> " IP
	    if [ "x${IP}x" == "xx" ]
	    then
		IP=$1
	    fi
	else
	    read -p "ip> " IP
	fi
    else
	VALUE=$IP1
	if [ "$IP" == "-d" ]
	then
	    IP=$1
	fi
	IP1=$IP2
	IP2=$IP3
	IP3=$IP4
	IP4=$IP5
	IP5=""
    fi
    true
}


subs() {
    echo "[$FILE] Replacing placeholders."

    if uname -n | grep "\.${DOMAIN}\$"; then
	HOST=`uname -n`
    else
	HOST="`uname -n`.$DOMAIN"
    fi
    sed -e "s;_HOST_;$HOST;" -ibak $FILE
    sed -e "s;_OWN_IP_;$OWN_IP;" -ibak $FILE
    sed -e "s;_FIFOCOOKIE_;$COOKIE;" -ibak $FILE
    sed -e "s;_STATSD_IP_;$STATSD_IP;" -ibak $FILE
    sed -e "s;_REDIS_URL_;redis://$REDIS_IP;" -ibak $FILE
    sed -e "s;_REDIS_DOMAIN_;$REDIS_DOMAIN;" -ibak $FILE
}

install_chunter() {
    C=$COMPONENT
    msg "Starting installation."
    if [ `zonename` != "global" ]
    then
	error "Chunter can only be installed in the global zone!"
    fi
    curl $BASE_PATH/$RELEASE/versions &>> /var/log/fifo-install.log
    mkdir -p /var/log/fifo/$COMPONENT &>> /var/log/fifo-install.log
    mkdir -p /opt &>> /var/log/fifo-install.log
    cd /opt &>> /var/log/fifo-install.log
    msg "Downloading."
    download $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2
    tar jxvf $COMPONENT.tar.bz2 &>> /var/log/fifo-install.log
    msg "Cleanup."
    rm $COMPONENT.tar.bz2 &>> /var/log/fifo-install.log 
    msg "Configuring."
    FILE=$COMPONENT/releases/*/vm.args
    subs
    FILE=$COMPONENT/releases/*/sys.config
    subs
    msg "Adding Service."
    mkdir -p /opt/custom/smf/

    cp /opt/$COMPONENT/epmd.xml /opt/custom/smf/
    svccfg import /opt/custom/smf/epmd.xml &>> /var/log/fifo-install.log || error "Could not activate epmd."
    cp /opt/$COMPONENT/$COMPONENT.xml /opt/custom/smf/
    svccfg import /opt/custom/smf/$COMPONENT.xml &>> /var/log/fifo-install.log || error "Could not activate chunter."
    cd -
    msg "Adding fifo DNS server."

    echo "nameserver $ZONE_IP" > /tmp/resolv.conf    
    grep -v  "nameserver $ZONE_IP" /etc/resolv.conf  >> /tmp/resolv.conf 
    cp /tmp/resolv.conf /etc/resolv.conf
    msg "Restarting NSCD."
    /etc/init.d/nscd stop
    /etc/init.d/nscd start
    msg "Done."
}


install_service() {
    C=$COMPONENT
    msg "Starting installation"
    if [ `zonename` == "global" ]
    then
	error "$COMPONENT can not be installed in the global zone!"
    fi
    mkdir -p /fifo &>> /var/log/fifo-install.log 
    mkdir -p /var/log/fifo/$COMPONENT &>> /var/log/fifo-install.log
    cd /fifo &>> /var/log/fifo-install.log

    if [ -f $COMPONENT.tar.bz2 ] 
    then
	msg "Skipping downloading."
    else
	download $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2
    fi
    tar jxvf $COMPONENT.tar.bz2 &>> /var/log/fifo-install.log
    echo "[COMPONENT: $COMPONENT] Cleanup."
    rm $COMPONENT.tar.bz2 &>> /var/log/fifo-install.log
    echo "[COMPONENT: $COMPONENT] Configuring."
    FILE=$COMPONENT/releases/*/vm.args
    subs
    FILE=$COMPONENT/releases/*/sys.config
    subs 
    echo "[COMPONENT: $COMPONENT] Adding Service."
    svccfg import /fifo/$COMPONENT/epmd.xml &>> /var/log/fifo-install.log || error "Could not activate epmd."
    svccfg import /fifo/$COMPONENT/$COMPONENT.xml &>> /var/log/fifo-install.log || error "Could not activate ${COMPONENT}."
    msg "Done."
    cd -
}

install_redis() {
    C="REDIS"
    msg "Installing."
    if [ `zonename` == "global" ]
    then
	echo "$COMPONENT can not be installed in the global zone!"
	#	exit 1
    fi
    /opt/local/bin/pkgin update &>> /var/log/fifo-install.log
    /opt/local/bin/pkgin -y install redis &>> /var/log/fifo-install.log
    msg "Fixing SVM."
    curl -sO  $BASE_PATH/$RELEASE/redis.xml &>> /var/log/fifo-install.log
    svccfg import redis.xml &>> /var/log/fifo-install.log
    rm redis.xml &>> /var/log/fifo-install.log
    msg "Enabeling."
    svcadm enable redis &>> /var/log/fifo-install.log
    msg "Done."
}

install_zone() {
    C="ZONE"
    IMGADM=dsadm
    if [ -f /usr/sbin/imgadm ] 
    then
	IMGADM=imgadm
	if [ ! -d /var/db/imgadm ]
	then
	    # This SmartOS suffers from the migration problem
	    # The solution was provided by Nahum Shalman
	    # look at the original here: http://wiki.smartos.org/display/DOC/Migrating+from+an+earlier+release+to+the+20120614+Release
	    PWD=`pwd`
	    mkdir -p /var/db/imgadm
	    cp /var/db/dsadm/* /var/db/imgadm/
	    cd /var/db/imgadm
	    mv dscache.json imgcache.json
	    for manifest in *.dsmanifest; do mv $manifest ${manifest/dsmanifest/json}; done;
	    cd $PWD
	fi
    fi
    msg "Starting Zone installation."
    msg "Updating datasets."
    if [ -d /zones/$DATASET ]
    then
	msg "Image $DATASET seems already isntalled."
    else
	$IMGADM update &>> /var/log/fifo-install.log || error "Failed to update image repository."
	msg "Importing dataset."
	$IMGADM import $DATASET &>> /var/log/fifo-install.log || error "Failed to import zone image."
    fi
    msg "Creating VM."
    vmadm create &>> /var/log/fifo-install.log<<EOF || error "Failed to create fifo zone!"
{
  "brand": "joyent",
  "quota": 40,
  "alias": "fifo",
  "zonename": "fifo",
  "nowait": true,
  "dataset_uuid": "$DATASET",
  "max_physical_memory": 2048,
  "resolvers": [
    "$ZONE_DNS"
  ],
  "nics": [
    {
      "nic_tag": "admin",
      "ip": "$ZONE_IP",
      "netmask": "$ZONE_MASK",
      "gateway": "$ZONE_GW"
    }
  ]
}
EOF
    cp $0 /zones/fifo/root/root &>> /var/log/fifo-install.log 
    n_msg_start "Waiting for zone installation"
    while [ -f /zones/fifo/root/root/zoneconfig ]
    do
	msg "."
	sleep 5
    done
    msg "done."
    sleep 30
    zlogin fifo $0 redis $ZONE_IP || exit "Reds installation failed exiting."
    msg "Prefetching services."
    mkdir -p /zones/fifo/root/fifo
    PWD=`pwd`
    cd /zones/fifo/root/fifo
    if [ -f $PWD/snarl.tar.bz2 ]
    then
	msg "snarl tarbal found skipping download."
	cp $PWD/snarl.tar.bz2 .
    else
	download $BASE_PATH/$RELEASE/snarl.tar.bz2
    fi

    if [ -f $PWD/sniffle.tar.bz2 ]
    then
	msg "sniffle tarbal found skipping download."
	cp $PWD/sniffle.tar.bz2 .
    else
	download $BASE_PATH/$RELEASE/sniffle.tar.bz2
    fi

    if [ -f $PWD/wiggle.tar.bz2 ]
    then
	msg "wiggle tarbal found skipping download."
	cp $PWD/wiggle.tar.bz2 .

    else
	download $BASE_PATH/$RELEASE/wiggle.tar.bz2
    fi

    if [ -f $PWD/modules.tar.bz2 ]
    then
	msg "wiggle tarbal found skipping download."
	cp $PWD/modules.tar.bz2 .

    else
	download $BASE_PATH/$RELEASE/modules.tar.bz2
    fi
    tar jxf modules.tar.bz2
    cd -


    zlogin fifo $0 graphit || error "Graphit installation failed"
    zlogin fifo $0 dnsmasq $ZONE_IP $ZONE_DNS $HYPERVISOR_IP $HOSTNAME || error "DNSMasq installation failed"

    zlogin fifo $0 snarl $ZONE_IP || error "Snarl installation failed."
    zlogin fifo $0 sniffle $ZONE_IP || error "Sniffle installation failed."
    zlogin fifo $0 wiggle $ZONE_IP || error "Wiggle installation failed."

}
read_component() {
    if [ "x${COMPONENT}x" == "xx" ] 
    then
	echo
	read -p "component> " COMPONENT
    fi
    case $COMPONENT in
	wiggle|sniffle|snarl)
	    echo "Please enter the IP for your zone."
	    read_ip
	    OWN_IP=$IP
	    REDIS_IP=$IP	    
	    STATSD_IP=$IP
	    install_service
	    ;;
	redis)
	    install_redis
	    ;;
	dnsmasq)
	    echo "Please enter the IP for your zone."
	    read_ip
	    ZONE_IP=$IP
	    echo "Please enter the DNS for your zone."
	    read_ip `cat /etc/resolv.conf | grep nameserver | head -n1 | awk -e '{ print $2 }'`
	    ZONE_DNS=$IP

	    echo "Please enter the Hypervisor IP."
	    read_ip
	    HYPERVISOR_IP=$IP

	    echo "Please enter the hostname."
	    read_value
	    HOSTNAME=$VALUE

	    install_dnsmasq
	    ;;
	all)
	    HOSTNAME=`hostname`
	    echo "Please enter the IP for your hypervisor."
	    read_ip
	    OWN_IP=$IP
	    HYPERVISOR_IP=$IP
	    echo "Please enter the IP for your zone."
	    read_ip
	    ZONE_IP=$IP
	    echo "Please enter the Netmask for your zone."
	    read_ip `cat /usbkey/config | grep admin_netmask | sed -e 's/admin_netmask=//'`
	    ZONE_MASK=$IP
	    echo "Please enter the Gateway for your zone."
	    read_ip `cat /usbkey/config | grep admin_gateway | sed -e 's/admin_gateway=//'`
	    ZONE_GW=$IP
	    echo "Please enter the DNS for your zone."
	    read_ip `cat /etc/resolv.conf | grep nameserver | head -n1 | awk -e '{ print $2 }'`
	    ZONE_DNS=$IP
	    install_zone
	    COMPONENT=chunter
	    install_chunter 
	    ;;
	chunter)
	    echo "Please enter the IP for your hypervisor."
	    read_ip
	    OWN_IP=$IP
	    echo "Please enter the IP for your zone."
	    read_ip
	    ZONE_IP=$IP
	    install_chunter
	    ;;
	graphit)
	    echo "installing graphite."
	    install_graphit
	    ;;
	zone)
	    echo "Please enter the IP for your zone."
	    read_ip
	    ZONE_IP=$IP
	    echo "Please enter the Netmask for your zone."
	    read_ip `cat /usbkey/config | grep admin_netmask | sed -e 's/admin_netmask=//'`
	    ZONE_MASK=$IP
	    echo "Please enter the Gateway for your zone."
	    read_ip `cat /usbkey/config | grep admin_gateway | sed -e 's/admin_gateway=//'`
	    ZONE_GW=$IP
	    echo "Please enter the DNS for your zone."
	    read_ip `cat /etc/resolv.conf | grep nameserver | head -n1 | awk -e '{ print $2 }'`
	    ZONE_DNS=$IP
	    install_zone
	    ;;
	exit)
	    ;;
	uninstall)
	    uninstall;;
	collect)
	    (
		mkdir -p /tmp/fifo
		cd /tmp/fifo
		cp -r /var/log/fifo/chunter /zones/fifo/root/var/log/fifo/* /var/log/fifo-install.log /zones/fifo/root/var/log/fifo-install.log .
		ps -afe | grep [r]un_erl > ps.log
		cd /tmp
		gtar cjvf fifo-debug.tar.bz2 fifo
		rm -rf /tmp/fifo
	    )
	    mv /tmp/fifo-debug.tar.bz2 .
	    ;;
	*)
	    echo "Component '$COMPONENT' not supported."
	    echo "Please choose one of: wiggle, sniffle, snarl, redis, chunter, zone or type exit."
	    COMPONENT=""
	    IP1=""
	    IP2=""
	    read_component
	    ;;
	
    esac
}



COMPONENT=$1
IP1=$2
IP2=$3
IP3=$4
IP4=$5
IP5=$6
if [ "$COMPONENT" == "help" ]
then
    cat <<EOF
$0 help                                - shows this help.
$0 all <hypervisor ip> <zone ip>       - sets up the entire fifo suite.
       <netmask> <gateway> <dns> 
$0 zone <zone ip> <netmask> <gateway>  - creates the administration zone.
        <dns>
$0 chunter <hypervisor ip> <zone ip>   - sets up the chunter service.
$0 redis <hypervisor ip>               - sets up redis in the current zone.
$0 snarl <hypervisor ip>               - sets up snarl in the current zone.
$0 sniffle <hypervisor ip>             - sets up sniffle in the current zone.
$0 wiggle <hypervisor ip>              - sets up sniffle in the current zone.
$0 uninstall                           - removes the installation.
$0 collect                             - collects fifo debug data.
EOF
else
    read_component $0
fi
