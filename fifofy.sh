#!/usr/bin/env bash
BASE_PATH="__BASE_URL__"
RELEASE="__REL__"
REDIS_DOMAIN="fifo"
COOKIE="fifo"
DATASET="f9e4be48-9466-11e1-bc41-9f993f5dff36"

error() {
  echo "[ERROR] $1." >> /var/log/fifo/fifo-install.log
  echo "[ERROR] $1."
  echo "[ERROR] I'm going to stop now, please look at /var/log/fifo/fifo-install.log for details."
  exit 1
}

download() {
    curl -sLkO "$1" >> /var/log/fifo-install.log || error "Failed to download $1"
}

install_py_pkg() {
    echo "[GRAPHIT] Installing: $1"
    tar zxf $1.tar.gz
    cd $1
    /opt/local/bin/python2.7 setup.py install  >> /var/log/fifo-install.log || error "Failed to install $1"
    cd ..
}

graphit() {
    echo "[GRAPHIT] Starting installation"
    cd /tmp
    echo "[GRAPHIT] Updating packages"
    /opt/local/bin/pkgin update >> /var/log/fifo-install.log
    echo "[GRAPHIT] Installing required packages (this will take a while!)"
    echo -n "[GRAPHIT] Installing packages"
    for pkg in python27 nodejs py27-memcached memcached py27-ZopeInterface zope3 cairo ap22-py27-python py27-django sqlite ap22-py27-wsgi py27-sqlite2 sqlite py27-twisted gcc-compiler gmake pkg-config xproto renderproto kbproto
    do
	echo -n " $pkg"
	/opt/local/bin/pkgin -y install $pkg >> /var/log/fifo-install.log || error "Failed to install package ${pgk}."
    done
    echo " done."
    export PATH="$PATH:/opt/local/bin"
    echo "[GRAPHIT] Installing statsd"
    /opt/local/bin/npm install statsd >> /var/log/fifo-install.log || error "Failed to install npm package statsd."
    
#    curl -LkO https://launchpad.net/graphite/0.9/0.9.10/+download/check-dependencies.py
    echo "[GRAPHIT] Downloadin additional packages"
    download https://launchpad.net/graphite/0.9/0.9.10/+download/graphite-web-0.9.10.tar.gz
    download https://launchpad.net/graphite/0.9/0.9.10/+download/carbon-0.9.10.tar.gz
    download https://launchpad.net/graphite/0.9/0.9.10/+download/whisper-0.9.10.tar.gz
    download http://cairographics.org/releases/py2cairo-1.10.0.tar.bz2
    download http://django-tagging.googlecode.com/files/django-tagging-0.3.1.tar.gz

    echo "[GRAPHIT] Installing: py2cairo"
    tar jxf py2cairo-1.10.0.tar.bz2 
    cd py2cairo-1.10.0
    CC=/opt/local/bin/gcc CFLAGS=-m64 LDFLAGS=-m64 /opt/local/bin/python2.7 waf configure --prefix=/opt/local  >> /var/log/fifo-install.log || error "Could not configure py2cairo."
    CC=/opt/local/bin/gcc CFLAGS=-m64 LDFLAGS=-m64 /opt/local/bin/python2.7 waf build  >> /var/log/fifo-install.log || error "Could not build py2cairo."
    CC=/opt/local/bin/gcc CFLAGS=-m64 LDFLAGS=-m64 /opt/local/bin/python2.7 waf install  >> /var/log/fifo-install.log || error "Could not install py2cairo."
    cd ..


    install_py_pkg whisper-0.9.10
    install_py_pkg django-tagging-0.3.1
    install_py_pkg graphite-web-0.9.10
    install_py_pkg carbon-0.9.10

    mkdir -p /opt/graphite/storage/log/carbon-cache

    echo "[GRAPHIT] Configuring: carbon"
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
    echo "[GRAPHIT] Configuring: web frontend"
    cd /opt/graphite/webapp/graphite
    cp local_settings.py.example local_settings.py
    cp /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi
    sed  -e 's/Listen 0.0.0.0:80/Listen 0.0.0.0:8080/' -i bak /opt/local/etc/httpd/httpd.conf
    echo "LoadModule wsgi_module lib/httpd/mod_wsgi.so" >> /opt/local/etc/httpd/httpd.conf
    echo "Include etc/httpd/httpd-vhosts.conf" >> /opt/local/etc/httpd/httpd.conf
    curl -s $BASE_PATH/$RELEASE/httpd-vhosts.conf > /opt/local/etc/httpd/httpd-vhosts.conf 
    echo "[GRAPHIT] Configuring: database"
    /opt/local/bin/python2.7 manage.py syncdb --noinput  >> /var/log/fifo-install.log
    /opt/local/bin/python2.7 manage.py createsuperuser --username=admin --email=admin@localhost.local --noinput  >> /var/log/fifo-install.log
    echo 'UPDATE auth_user SET password="sha1$4557a$674798faef13ba7192efad47fb9fc7021fbcf919" WHERE username="admin";' | sqlite3 /opt/graphite/storage/graphite.db  >> /var/log/fifo-install.log
    cd -

    /opt/local/bin/chown -R www:www /opt/graphite/

    cd /fifo
    echo "[GRAPHIT] Downloading service descriptors"
    curl -sO $BASE_PATH/$RELEASE/statsdconfig.js
    curl -sO $BASE_PATH/$RELEASE/statsd.xml
    curl -sO $BASE_PATH/$RELEASE/carbon.xml
    echo "[GRAPHIT] Enabeling services"
    svcadm enable apache >> /var/log/fifo-install.log 
    svccfg import statsd.xml >> /var/log/fifo-install.log
    svccfg import carbon.xml >> /var/log/fifo-install.log
    cd -
    echo "[GRAPHIT] one"
}

uninstall() {
    UUID=`vmadm list -p -o uuid zonename=fifo`
    vmadm delete $UUID
    svcadm disable chunter
    svcadm disable epmd
    svccfg delete chunter
    svccfg delete epmd
    /opt/chunter/bin/chunter stop
    rm -rf /opt/chunter
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

subs() {
    echo "[SUBS $FILE] replacing placeholders."
    sed -e "s;_OWN_IP_;$OWN_IP;" -i bak $FILE
    sed -e "s;_FIFOCOOKIE_;$COOKIE;" -i bak $FILE
    sed -e "s;_STATSD_IP_;$STATSD_IP;" -i bak $FILE
    sed -e "s;_REDIS_URL_;redis://$REDIS_IP;" -i bak $FILE
    sed -e "s;_REDIS_DOMAIN_;$REDIS_DOMAIN;" -i bak $FILE
}

install_chunter() {
    echo "[COMPONENT: $COMPONENT] Starting installation"
    if [ `zonename` != "global" ]
    then
	echo "chunter can only be installed in the global zone!"
	exit 1
    fi
    mkdir -p /var/log/fifo/$COMPONENT >> /var/log/fifo-install.log
    mkdir -p /opt >> /var/log/fifo-install.log
    cd /opt >> /var/log/fifo-install.log
    echo "[COMPONENT: $COMPONENT] Downloading."
    download $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2
    tar jxvf $COMPONENT.tar.bz2 >> /var/log/fifo-install.log
    echo "[COMPONENT: $COMPONENT] Cleanup."
    rm $COMPONENT.tar.bz2 >> /var/log/fifo-install.log 
    echo "[COMPONENT: $COMPONENT] Configuring."
    FILE=$COMPONENT/releases/*/vm.args
    subs
    FILE=$COMPONENT/releases/*/sys.config
    subs
    echo "[COMPONENT: $COMPONENT] Adding Service."
    mkdir -p /opt/custom/smf/

    cp /opt/$COMPONENT/epmd.xml /opt/custom/smf/
    svccfg import /opt/custom/smf/epmd.xml >> /var/log/fifo-install.log || error "Could not activate epmd."
    cp /opt/$COMPONENT/$COMPONENT.xml /opt/custom/smf/
    svccfg import /opt/custom/smf/$COMPONENT.xml >> /var/log/fifo-install.log || error "Could not activate chunter."
    cd -
    echo "[COMPONENT: $COMPONENT] Done."
}


install_service() {
    echo "[COMPONENT: $COMPONENT] Starting installation"
    if [ `zonename` == "global" ]
    then
	echo "$COMPONENT can not be installed in the global zone!"
	#	exit 1
    fi
    mkdir -p /fifo >> /var/log/fifo-install.log 
    mkdir -p /var/log/fifo/$COMPONENT >> /var/log/fifo-install.log
    cd /fifo >> /var/log/fifo-install.log

    if [ -f $COMPONENT.tar.bz2 ] 
    then
	echo "[COMPONENT: $COMPONENT] Skipping downloading."
    else
	download $BASE_PATH/$RELEASE/$COMPONENT.tar.bz2
    fi
    tar jxvf $COMPONENT.tar.bz2 >> /var/log/fifo-install.log
    echo "[COMPONENT: $COMPONENT] Cleanup."
    rm $COMPONENT.tar.bz2 >> /var/log/fifo-install.log
    echo "[COMPONENT: $COMPONENT] Configuring."
    FILE=$COMPONENT/releases/*/vm.args
    subs
    FILE=$COMPONENT/releases/*/sys.config
    subs 
    echo "[COMPONENT: $COMPONENT] Adding Service."
    svccfg import /fifo/$COMPONENT/epmd.xml >> /var/log/fifo-install.log || error "Could not activate epmd."
    svccfg import /fifo/$COMPONENT/$COMPONENT.xml >> /var/log/fifo-install.log || error "Could not activate ${COMPONENT}."
    echo "[COMPONENT: $COMPONENT] Done."
    cd -
}

install_redis() {
    echo "[REDIS] Installing."
    if [ `zonename` == "global" ]
    then
	echo "$COMPONENT can not be installed in the global zone!"
	#	exit 1
    fi
    /opt/local/bin/pkgin update >> /var/log/fifo-install.log
    /opt/local/bin/pkgin -y install redis >> /var/log/fifo-install.log
    echo "[REDIS] Fixing SVM."
    curl -sO  $BASE_PATH/$RELEASE/redis.xml >> /var/log/fifo-install.log
    svccfg import redis.xml >> /var/log/fifo-install.log
    rm redis.xml >> /var/log/fifo-install.log
    echo "[REDIS] Enabeling."
    svcadm enable redis >> /var/log/fifo-install.log
    echo "[REDIS] Done."
}

install_zone() {
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
    echo "[ZONE] Starting Zone installation."
    echo "[ZONE] Updating datasets."
    if [ -d /zones/$DATASET ]
    then
	echo "[ZONE] Image $DATASET seems already isntalled."
    else
	$IMGADM update >> /var/log/fifo-install.log || error "Failed to update image repository."
	echo "[ZONE] Importing dataset."
	$IMGADM import $DATASET >> /var/log/fifo-install.log || error "Failed to import zone image."
    fi
    echo "[ZONE] Creating VM."
    vmadm create >> /var/log/fifo-install.log<<EOF || error "Failed to create fifo zone!"
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
    cp $0 /zones/fifo/root/root >> /var/log/fifo-install.log 
    echo "[ZONE] Waiting..."
    while [ -f /zones/fifo/root/root/zoneinit ]
    do
	sleep 5
    done
    sleep 30
    zlogin fifo $0 redis $ZONE_IP || exit "Reds installation failed exiting."
    echo "[ZONE] Prefetching services."
    mkdir -p /zones/fifo/root/fifo
    PWD=`pwd`
    cd /zones/fifo/root/fifo
    if [ -f $PWD/snarl.tar.bz2 ]
    then
	echo "[ZONE] snarl tarbal found skipping download."
	cp $PWD/snarl.tar.bz2 .
    else
	download $BASE_PATH/$RELEASE/snarl.tar.bz2
    fi

    if [ ! -f $PWD/sniffle.tar.bz2 ]
    then
	echo "[ZONE] sniffle tarbal found skipping download."
	cp $PWD/sniffle.tar.bz2 .
    else
	download $BASE_PATH/$RELEASE/sniffle.tar.bz2
    fi

    if [ -f $PWD/wiggle.tar.bz2 ]
    then
	echo "[ZONE] wiggle tarbal found skipping download."
	cp $PWD/wiggle.tar.bz2 .

    else
	download $BASE_PATH/$RELEASE/wiggle.tar.bz2
    fi
    cd -
    zlogin fifo $0 graphit || error "Graphit installation failed"
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
	all)
	    echo "Please enter the IP for your hypervisor."
	    read_ip
	    OWN_IP=$IP
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
	    STATSD_IP=$ZONE_IP
	    COMPONENT=chunter
	    install_chunter 
	    ;;
	chunter)
	    echo "Please enter the IP for your hypervisor."
	    read_ip
	    OWN_IP=$IP
	    echo "Please enter the IP for your statsd server."
	    read_ip
	    STATSD_IP=$IP
	    install_chunter
	    ;;
	graphit)
	    echo "installing graphite."
	    graphit
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
		cp -r /var/log/fifo/chunter /zones/fifo/root/var/log/fifo/* .
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
