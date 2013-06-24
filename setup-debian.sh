#!/bin/bash

############################################################
# core functions
############################################################

function check_install {
	if [ -z "`which "$1" 2>/dev/null`" ]
	then
		executable=$1
		shift
		while [ -n "$1" ]
		do
			DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
			apt-get clean
			print_info "$1 installed for $executable"
			shift
		done
	else
		print_warn "$2 already installed"
	fi
}

function check_remove {
	if [ -n "`which "$1" 2>/dev/null`" ]
	then
		DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge "$2"
		apt-get clean
		print_info "$2 removed"
	else
		print_warn "$2 is not installed"
	fi
}

function check_sanity {
	# Do some sanity checking.
	if [ $(/usr/bin/id -u) != "0" ]
	then
		die 'Must be run by root user'
	fi

	if [ ! -f /etc/debian_version ]
	then
		die "Distribution is not supported"
	fi
}

function die {
	echo "ERROR: $1" > /dev/null 1>&2
	exit 1
}

function get_domain_name() {
	# Getting rid of the lowest part.
	domain=${1%.*}
	lowest=`expr "$domain" : '.*\.\([a-z][a-z]*\)'`
	case "$lowest" in
	com|net|org|gov|edu|co|me|info|name)
		domain=${domain%.*}
		;;
	esac
	lowest=`expr "$domain" : '.*\.\([a-z][a-z]*\)'`
	[ -z "$lowest" ] && echo "$domain" || echo "$lowest"
}

function get_password() {
	# Check whether our local salt is present.
	SALT=/var/lib/radom_salt
	if [ ! -f "$SALT" ]
	then
		head -c 512 /dev/urandom > "$SALT"
		chmod 400 "$SALT"
	fi
	password=`(cat "$SALT"; echo $1) | md5sum | base64`
	echo ${password:0:13}
}

function print_info {
	echo -n -e '\e[1;36m'
	echo -n $1
	echo -e '\e[0m'
}

function print_warn {
	echo -n -e '\e[1;33m'
	echo -n $1
	echo -e '\e[0m'
}


############################################################
# applications
############################################################

function install_dash {
	check_install dash dash
	rm -f /bin/sh
	ln -s dash /bin/sh
}

function install_nano {
	check_install nano nano
}

function install_htop {
	check_install htop htop
}

function install_mc {
	check_install mc mc
}

function install_iotop {
	check_install iotop iotop
}

function install_iftop {
	check_install iftop iftop
	print_warn "Run IFCONFIG to find your net. device name"
	print_warn "Example usage: iftop -i venet0"
}

function install_vim {
	check_install vim vim
}

function install_dropbear {
	if [ -z "$1" ]
	then
		die "Usage: `basename $0` dropbear [ssh-port-#]"
	fi

	check_install dropbear dropbear
	check_install /usr/sbin/xinetd xinetd

	# Disable SSH
	touch /etc/ssh/sshd_not_to_be_run
	invoke-rc.d ssh stop

	# Enable dropbear to start. We are going to use xinetd as it is just
	# easier to configure and might be used for other things.
	cat > /etc/xinetd.d/dropbear <<END
service ssh
{
	socket_type  = stream
	only_from    = 0.0.0.0
	wait         = no
	user         = root
	protocol     = tcp
	server       = /usr/sbin/dropbear
	server_args  = -i
	disable      = no
	port         = $1
	type         = unlisted
}
END
	invoke-rc.d xinetd restart

	print_info "dropbear is installed and running"
}

function install_exim4 {
	check_install mail exim4
	if [ -f /etc/exim4/update-exim4.conf.conf ]
	then
		sed -i \
			"s/dc_eximconfig_configtype='local'/dc_eximconfig_configtype='internet'/" \
			/etc/exim4/update-exim4.conf.conf
		invoke-rc.d exim4 restart
	fi
}

function install_dotdeb {
	# Debian version 6.x.x
	if grep ^6. /etc/debian_version > /dev/null
	then
		echo "deb http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list
		echo "deb-src http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list
	fi

	# Debian version 7.x.x
	if grep ^7. /etc/debian_version > /dev/null
	then
		echo "deb http://packages.dotdeb.org wheezy all" >> /etc/apt/sources.list
		echo "deb-src http://packages.dotdeb.org wheezy all" >> /etc/apt/sources.list
	fi

	wget -q -O - http://www.dotdeb.org/dotdeb.gpg | apt-key add -
}

function install_syslogd {
	# We just need a simple vanilla syslogd. Also there is no need to log to
	# so many files (waste of fd). Just dump them into
	# /var/log/(cron/mail/messages)
	check_install /usr/sbin/syslogd inetutils-syslogd
	invoke-rc.d inetutils-syslogd stop

	for file in /var/log/*.log /var/log/mail.* /var/log/debug /var/log/syslog
	do
		[ -f "$file" ] && rm -f "$file"
	done
	for dir in fsck news
	do
		[ -d "/var/log/$dir" ] && rm -rf "/var/log/$dir"
	done

	cat > /etc/syslog.conf <<END
*.*;mail.none;cron.none -/var/log/messages
cron.*				  -/var/log/cron
mail.*				  -/var/log/mail
END

	[ -d /etc/logrotate.d ] || mkdir -p /etc/logrotate.d
	cat > /etc/logrotate.d/inetutils-syslogd <<END
/var/log/cron
/var/log/mail
/var/log/messages {
	rotate 4
	weekly
	missingok
	notifempty
	compress
	sharedscripts
	postrotate
		/etc/init.d/inetutils-syslogd reload >/dev/null
	endscript
}
END

	invoke-rc.d inetutils-syslogd start
}

function install_mysql {

	# Install the MySQL packages
	check_install mysqld mysql-server
	check_install mysql mysql-client

	# Install a low-end copy of the my.cnf to disable InnoDB
	invoke-rc.d mysql stop
	cat > /etc/mysql/conf.d/lowendbox.cnf <<END
# These values override values from /etc/mysql/my.cnf

[mysqld]
key_buffer = 12M
query_cache_size = 0
table_cache = 32

init_connect='SET collation_connection = utf8_unicode_ci'
init_connect='SET NAMES utf8' 
character-set-server = utf8 
collation-server = utf8_unicode_ci 
skip-character-set-client-handshake

default_storage_engine=MyISAM
skip-innodb

log-slow-queries=/var/log/mysql/slow-queries.log

[client]
default-character-set = utf8
END
	invoke-rc.d mysql start

	# Generating a new password for the root user.
	passwd=`get_password root@mysql`
	mysqladmin password "$passwd"
	cat > ~/.my.cnf <<END
[client]
user = root
password = $passwd
END
	chmod 600 ~/.my.cnf
}

function install_php {
	# PHP core
	check_install php5-fpm php5-fpm
	check_install php5-cli php5-cli

	# PHP modules
	DEBIAN_FRONTEND=noninteractive apt-get -y install php5-apc php5-suhosin php5-curl php5-gd php5-intl php5-mcrypt php-gettext php5-mysql php5-sqlite

	echo 'Using PHP-FPM to manage PHP processes'
	echo ' '

        print_info "Taking configuration backups in /root/bkps; you may keep or delete this directory"
        mkdir /root/bkps
	mv /etc/php5/conf.d/apc.ini /root/bkps/apc.ini

cat > /etc/php5/conf.d/apc.ini <<END
[APC]
extension=apc.so
apc.enabled=1
apc.shm_segments=1
apc.shm_size=32M
apc.ttl=7200
apc.user_ttl=7200
apc.num_files_hint=1024
apc.mmap_file_mask=/tmp/apc.XXXXXX
apc.max_file_size = 1M
apc.post_max_size = 1000M
apc.upload_max_filesize = 1000M
apc.enable_cli=0
apc.rfc1867=0
END

	mv /etc/php5/conf.d/suhosin.ini /root/bkps/suhosin.ini

cat > /etc/php5/conf.d/suhosin.ini <<END
; configuration for php suhosin module
extension=suhosin.so
suhosin.executor.include.whitelist="phar"
suhosin.request.max_vars = 2048
suhosin.post.max_vars = 2048
suhosin.request.max_array_index_length = 256
suhosin.post.max_array_index_length = 256
suhosin.request.max_totalname_length = 8192
suhosin.post.max_totalname_length = 8192
suhosin.sql.bailout_on_error = Off
END

	if [ -f /etc/php5/fpm/php.ini ]
		then
			sed -i \
				"s/upload_max_filesize = 2M/upload_max_filesize = 200M/" \
				/etc/php5/fpm/php.ini
			sed -i \
				"s/post_max_size = 8M/post_max_size = 200M/" \
				/etc/php5/fpm/php.ini
			sed -i \
				"s/memory_limit = 128M/memory_limit = 36M/" \
				/etc/php5/fpm/php.ini
	fi

	invoke-rc.d php5-fpm restart

}

function install_nginx {

	check_install nginx nginx

	mkdir -p /var/www

	# PHP-safe default vhost
	cat > /etc/nginx/sites-available/default_php <<END
# Creates unlimited domains for PHP sites as long as you add the
# entry to /etc/hosts and create the matching \$host folder.
server {
	listen 80 default;
	server_name _;
	root /var/www/\$host/public;
	index index.html index.htm index.php;

	# Directives to send expires headers and turn off 404 error logging.
	location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
		expires max;
		log_not_found off;
		access_log off;
	}

	location = /favicon.ico {
		log_not_found off;
		access_log off;
	}

	location = /robots.txt {
		allow all;
		log_not_found off;
		access_log off;
	}

	## Disable viewing .htaccess & .htpassword
	location ~ /\.ht {
		deny  all;
	}

	include /etc/nginx/php.conf;
}
END

	# MVC frameworks with only a single index.php entry point (nginx > 0.7.27)
	cat > /etc/nginx/php.conf <<END
# Route all requests for non-existent files to index.php
location / {
	try_files \$uri \$uri/ /index.php\$is_args\$args;
}

# Pass PHP scripts to php-fastcgi listening on port 9000
location ~ \.php$ {

	# Zero-day exploit defense.
	# http://forum.nginx.org/read.php?2,88845,page=3
	# Won't work properly (404 error) if the file is not stored on
	# this server,  which is entirely possible with php-fpm/php-fcgi.
	# Comment the 'try_files' line out if you set up php-fpm/php-fcgi
	# on another machine.  And then cross your fingers that you won't get hacked.
	try_files \$uri =404;

	include fastcgi_params;

	# Keep these parameters for compatibility with old PHP scripts using them.
	fastcgi_param PATH_INFO \$fastcgi_path_info;
	fastcgi_param PATH_TRANSLATED \$document_root\$fastcgi_path_info;
	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

	# Some default config
	fastcgi_connect_timeout        20;
	fastcgi_send_timeout          180;
	fastcgi_read_timeout          180;
	fastcgi_buffer_size          128k;
	fastcgi_buffers            4 256k;
	fastcgi_busy_buffers_size    256k;
	fastcgi_temp_file_write_size 256k;
	fastcgi_intercept_errors    on;
	fastcgi_ignore_client_abort off;
	fastcgi_pass 127.0.0.1:9000;

}
# PHP search for file Exploit:
# The PHP regex location block fires instead of the try_files block. Therefore we need
# to add "try_files \$uri =404;" to make sure that "/uploads/virusimage.jpg/hello.php"
# never executes the hidden php code inside virusimage.jpg because it can't find hello.php!
# The exploit also can be stopped by adding "cgi.fix_pathinfo = 0" in your php.ini file.
END

	# remove localhost-config
	rm -f /etc/nginx/sites-enabled/default

	echo 'Created /etc/nginx/php.conf for PHP sites'
	echo 'Created /etc/nginx/sites-available/default_php sample vhost'
	echo ' '

 if [ -f /etc/nginx/sites-available/default ]
	then
		# Made IPV6 Listener not conflict and throw errors
		sed -i \
			"s/listen \[::]:80 default_server;/listen [::]:80 default_server ipv6only=on;/" \
			/etc/nginx/sites-available/default
 fi

 if [ -f /etc/nginx/nginx.conf ]
	then
		# one worker for each CPU and max 1024 connections/worker
		cpu_count=`grep -c ^processor /proc/cpuinfo`
		sed -i \
			"s/worker_processes [0-9]*;/worker_processes $cpu_count;/" \
			/etc/nginx/nginx.conf
		sed -i \
			"s/worker_connections [0-9]*;/worker_connections 1024;/" \
			/etc/nginx/nginx.conf
		# Enable advanced compression
		sed -i \
			"s/# gzip_/gzip_/g" \
			/etc/nginx/nginx.conf
 fi

	# restart nginx
	invoke-rc.d nginx restart
}

function install_site {

	if [ -z "$1" ]
	then
		die "Usage: `basename $0` site [domain]"
	fi

	# Setup folder
	mkdir /var/www/$1
	mkdir /var/www/$1/public

	# Setup default index.html file
	cat > "/var/www/$1/public/index.html" <<END
Hello World
END

	# Setup test phpinfo.php file
	echo "<?php phpinfo(); ?>" > /var/www/$1/public/phpinfo.php
	chown www-data:www-data "/var/www/$1/public/phpinfo.php"

	# Setting up Nginx mapping
	cat > "/etc/nginx/sites-available/$1.conf" <<END
server {
	listen 80;
	server_name www.$1 $1;
	root /var/www/$1/public;
	index index.html index.htm index.php;
	client_max_body_size 32m;

	access_log  /var/www/$1/access.log;
	error_log  /var/www/$1/error.log;

	# Directives to send expires headers and turn off 404 error logging.
	location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
		expires max;
		log_not_found off;
		access_log off;
	}

	location = /favicon.ico {
		log_not_found off;
		access_log off;
	}

	location = /robots.txt {
		allow all;
		log_not_found off;
		access_log off;
	}

	## Disable viewing .htaccess & .htpassword
	location ~ /\.ht {
		deny  all;
	}

	include /etc/nginx/php.conf;
}
END
	# Create the link so nginx can find it
	ln -s /etc/nginx/sites-available/$1.conf /etc/nginx/sites-enabled/$1.conf

	# PHP/Nginx needs permission to access this
	chown www-data:www-data -R "/var/www/$1"

	invoke-rc.d nginx restart

	print_warn "New site successfully installed."
	print_warn "You may can test PHP functionality by accessing $1/phpinfo.php"
}

function install_wordpress {

	if [ -z "$1" ]
	then
		die "Usage: `basename $0` wordpress [domain]"
	fi

	# Setup folder
	mkdir /var/www/$1
	mkdir /var/www/$1/public

	# Downloading the WordPress' latest and greatest distribution.
    mkdir /tmp/wordpress.$$
    wget -O - http://wordpress.org/latest.tar.gz | \
        tar zxf - -C /tmp/wordpress.$$
    cp -a /tmp/wordpress.$$/wordpress/. "/var/www/$1/public"
    rm -rf /tmp/wordpress.$$

	# Setting up the MySQL database
    dbname=`echo $1 | tr . _`
	echo Database Name = 'echo $1 | tr . _'
    userid=`get_domain_name $1`
    # MySQL userid cannot be more than 15 characters long
    userid="${userid:0:15}"
    passwd=`get_password "$userid@mysql"`
	# Write wp.config file
    cp "/var/www/$1/public/wp-config-sample.php" "/var/www/$1/public/wp-config.php"
	salt=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
	defineString='put your unique phrase here'
	printf '%s\n' "g/$defineString/d" a "$salt" . w | ed -s /var/www/$1/public/wp-config.php
    sed -i "s/database_name_here/$dbname/; s/username_here/$userid/; s/password_here/$passwd/" \
        "/var/www/$1/public/wp-config.php"

		cat > "/var/www/$1/mysql.conf" <<END
[mysql]
user = $userid
password = $passwd
database = $dbname
END
	chmod 600 "/var/www/$1/mysql.conf"

    mysqladmin create "$dbname"
    echo "GRANT ALL PRIVILEGES ON \`$dbname\`.* TO \`$userid\`@localhost IDENTIFIED BY '$passwd';" | \
        mysql

	# Setting up Nginx mapping
	cat > "/etc/nginx/sites-available/$1.conf" <<END
server {
	listen 80;
	server_name www.$1 $1;
	root /var/www/$1/public;
	index index.php;

	access_log  /var/www/$1/access.log;
	error_log  /var/www/$1/error.log;

	# unless the request is for a valid file, send to bootstrap
	if (!-e \$request_filename)
    {
	    rewrite ^(.+)$ /index.php?q=$1 last;
    }
 
    # catch all
    error_page 404 /index.php;

    # Directives to send expires headers and turn off 404 error logging.
    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        expires max;
        log_not_found off;
        access_log off;
    }

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    ## Disable viewing .htaccess & .htpassword
    location ~ /\.ht {
        deny  all;
    }

    location / {
                # This is cool because no php is touched for static content. 
                # include the "?\$args" part so non-default permalinks doesn't break when using query string
                try_files \$uri \$uri/ /index.php?\$args;
        }

    # use fastcgi for all php files
    location ~ \.php$
    {
        try_files \$uri =404;

        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME /var/www/$1/public\$fastcgi_script_name;
        include fastcgi_params;

        # Some default config
        fastcgi_connect_timeout        20;
        fastcgi_send_timeout          180;
        fastcgi_read_timeout          180;
        fastcgi_buffer_size          128k;
        fastcgi_buffers            4 256k;
        fastcgi_busy_buffers_size    256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_intercept_errors    on;
        fastcgi_ignore_client_abort off;

    }

}


END
	# Create the link so nginx can find it
	ln -s /etc/nginx/sites-available/$1.conf /etc/nginx/sites-enabled/$1.conf

	# PHP/Nginx needs permission to access this
	chown www-data:www-data -R "/var/www/$1"

	invoke-rc.d nginx restart

	print_warn "New wordpress site successfully installed."
}

function install_mysqluser {

	if [ -z "$1" ]
	then
		die "Usage: `basename $0` mysqluser [domain]"
	fi

	if [ ! -d "/var/www/$1/" ]
	then
		echo "no site found at /var/www/$1/"
		exit
	fi

	# Setting up the MySQL database
	dbname=`echo $1 | tr . _`
	userid=`get_domain_name $1`
	# MySQL userid cannot be more than 15 characters long
	userid="${userid:0:15}"
	passwd=`get_password "$userid@mysql"`

	cat > "/var/www/$1/mysql.conf" <<END
[mysql]
user = $userid
password = $passwd
database = $dbname
END
	chmod 600 "/var/www/$1/mysql.conf"

	mysqladmin create "$dbname"
	echo "GRANT ALL PRIVILEGES ON \`$dbname\`.* TO \`$userid\`@localhost IDENTIFIED BY '$passwd';" | \
		mysql

	# We could also add these...
	#echo "DROP USER '$userid'@'localhost';" | \ mysql
	#echo "DROP DATABASE IF EXISTS  `$dbname` ;" | \ mysql

	echo 'MySQL Username: ' $userid
	echo 'MySQL Password: ' $passwd
	echo 'MySQL Database: ' $dbname
}


function install_iptables {

	check_install iptables iptables

	if [ -z "$1" ]
	then
		die "Usage: `basename $0` iptables [ssh-port-#]"
	fi

	# Create startup rules
	cat > /etc/iptables.up.rules <<END
*filter

# http://articles.slicehost.com/2010/4/30/ubuntu-lucid-setup-part-1

#  Allows all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
-A INPUT -i lo -j ACCEPT
-A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT

#  Accepts all established inbound connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

#  Allows all outbound traffic
#  You can modify this to only allow certain traffic
-A OUTPUT -j ACCEPT

# Allows HTTP and HTTPS connections from anywhere (the normal ports for websites)
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT

# UN-COMMENT THESE IF YOU USE INCOMING MAIL!

# Allows POP (and SSL-POP)
#-A INPUT -p tcp --dport 110 -j ACCEPT
#-A INPUT -p tcp --dport 995 -j ACCEPT

# SMTP (and SSMTP)
#-A INPUT -p tcp --dport 25 -j ACCEPT
#-A INPUT -p tcp --dport 465 -j ACCEPT

# IMAP (and IMAPS)
#-A INPUT -p tcp --dport 143 -j ACCEPT
#-A INPUT -p tcp --dport 993 -j ACCEPT

#  Allows SSH connections (only 3 attempts by an IP every minute, drop the rest to prevent SSH attacks)
-A INPUT -p tcp -m tcp --dport $1 -m state --state NEW -m recent --set --name DEFAULT --rsource
-A INPUT -p tcp -m tcp --dport $1 -m state --state NEW -m recent --update --seconds 60 --hitcount 3 --name DEFAULT --rsource -j DROP
-A INPUT -p tcp -m state --state NEW --dport $1 -j ACCEPT

# Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

# log iptables denied calls (Can grow log files fast!)
#-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7

# Misc

# Reject all other inbound - default deny unless explicitly allowed policy
#-A INPUT -j REJECT
#-A FORWARD -j REJECT

# It's safer to just DROP the packet
-A INPUT -j DROP
-A FORWARD -j DROP

COMMIT
END

	# Set these rules to load on startup
	cat > /etc/network/if-pre-up.d/iptables <<END
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.up.rules
END

	# Make it executable
	chmod +x /etc/network/if-pre-up.d/iptables

	# Load the rules
	iptables-restore < /etc/iptables.up.rules

	# You can flush the current rules with /sbin/iptables -F
	echo 'Created /etc/iptables.up.rules and startup script /etc/network/if-pre-up.d/iptables'
	echo 'If you make changes you can restore the rules with';
	echo '/sbin/iptables -F'
	echo 'iptables-restore < /etc/iptables.up.rules'
	echo ' '
}

function remove_unneeded {
	# Some Debian have portmap installed. We don't need that.
	check_remove /sbin/portmap portmap

	# Remove rsyslogd, which allocates ~30MB privvmpages on an OpenVZ system,
	# which might make some low-end VPS inoperatable. We will do this even
	# before running apt-get update.
	check_remove /usr/sbin/rsyslogd rsyslog

	# Other packages that are quite common in standard OpenVZ templates.
	check_remove /usr/sbin/apache2 'apache2*'
	check_remove /usr/sbin/named 'bind9*'
	check_remove /usr/sbin/smbd 'samba*'
	check_remove /usr/sbin/nscd nscd

	# Need to stop sendmail as removing the package does not seem to stop it.
	if [ -f /usr/lib/sm.bin/smtpd ]
	then
		invoke-rc.d sendmail stop
		check_remove /usr/lib/sm.bin/smtpd 'sendmail*'
	fi
}

############################################################
# Download ps_mem.py
############################################################
function install_ps_mem {
	wget http://www.pixelbeat.org/scripts/ps_mem.py -O ~/ps_mem.py
	chmod 700 ~/ps_mem.py
	print_info "ps_mem.py has been setup successfully"
	print_warn "Use ~/ps_mem.py to execute"
}

############################################################
# Update apt sources (Ubuntu only; not yet supported for debian)
############################################################
function update_apt_sources {
	eval `grep '^DISTRIB_CODENAME=' /etc/*-release 2>/dev/null`

	if [ "$DISTRIB_CODENAME" == "" ]
	then
		die "Unknown Ubuntu flavor $DISTRIB_CODENAME"
	fi

	cat > /etc/apt/sources.list <<END
## main & restricted repositories
deb http://us.archive.ubuntu.com/ubuntu/ $DISTRIB_CODENAME main restricted
deb-src http://us.archive.ubuntu.com/ubuntu/ $DISTRIB_CODENAME main restricted

deb http://security.ubuntu.com/ubuntu $DISTRIB_CODENAME-updates main restricted
deb-src http://security.ubuntu.com/ubuntu $DISTRIB_CODENAME-updates main restricted

deb http://security.ubuntu.com/ubuntu $DISTRIB_CODENAME-security main restricted
deb-src http://security.ubuntu.com/ubuntu $DISTRIB_CODENAME-security main restricted

## universe repositories - uncomment to enable
deb http://us.archive.ubuntu.com/ubuntu/ $DISTRIB_CODENAME universe
deb-src http://us.archive.ubuntu.com/ubuntu/ $DISTRIB_CODENAME universe

deb http://us.archive.ubuntu.com/ubuntu/ $DISTRIB_CODENAME-updates universe
deb-src http://us.archive.ubuntu.com/ubuntu/ $DISTRIB_CODENAME-updates universe

deb http://security.ubuntu.com/ubuntu $DISTRIB_CODENAME-security universe
deb-src http://security.ubuntu.com/ubuntu $DISTRIB_CODENAME-security universe
END

	print_info "/etc/apt/sources.list updated for "$DISTRIB_CODENAME
}

############################################################
# Install vzfree (OpenVZ containers only)
############################################################
function install_vzfree {
	print_warn "build-essential package is now being installed which will take additional diskspace"
	check_install build-essential build-essential
	cd ~
	wget http://hostingfu.com/files/vzfree/vzfree-0.1.tgz -O vzfree-0.1.tgz
	tar -vxf vzfree-0.1.tgz
	cd vzfree-0.1
	make && make install
	cd ..
	vzfree
	print_info "vzfree has been installed"
	rm -fr vzfree-0.1 vzfree-0.1.tgz
}

############################################################
# Install Webmin
############################################################
function install_webmin {
	print_warn "Make sure you have update the apt file first RUN 'bash `basename $0` apt' to update the /etc/apt/sources.list"

	print_info "Installing required packages"
	check_install perl perl
	check_install libnet-ssleay-perl libnet-ssleay-perl
	check_install openssl openssl
	check_install libauthen-pam-perl libauthen-pam-perl
	check_install libpam-runtime libpam-runtime
	check_install libio-pty-perl libio-pty-perl
	check_install libapt-pkg-perl libapt-pkg-perl
	check_install apt-show-versions apt-show-versions

	# Making sure there are no other dependancies left
	apt-get upgrade -q -y -f

	# Download and install Webmin
	print_info "Downloading Webmin"
	wget http://www.webmin.com/download/deb/webmin-current.deb -O /tmp/webmin.deb
	print_info "Installing webmin ..."
	dpkg -i /tmp/webmin.deb
	rm -fr /tmp/webmin.deb
	print_warn "Special Note: If the installation ends with an error, please run it again"
}

############################################################
# Generate SSH Key
############################################################
function gen_ssh_key {
	print_warn "Generating the ssh-key (1024 bit)"
	if [ -z "$1" ]
	then
		ssh-keygen -t dsa -b 1024 -f ~/id_rsa
		print_warn "generated ~/id_rsa"
	else
		ssh-keygen -t dsa -b 1024 -f ~/"$1"
		print_warn "generated ~/$1"
	fi
}

############################################################
# Configure MOTD at login
############################################################
function configure_motd {
	apt_clean_all
	update_upgrade
	check_install landscape-common landscape-common
	dpkg-reconfigure landscape-common
}

############################################################
# Classic Disk I/O and Network speed tests
############################################################
function runtests {
	print_info "Classic I/O test"
	print_info "dd if=/dev/zero of=iotest bs=64k count=16k conv=fdatasync && rm -fr iotest"
	dd if=/dev/zero of=iotest bs=64k count=16k conv=fdatasync && rm -fr iotest

	print_info "Network test"
	print_info "wget cachefly.cachefly.net/100mb.test -O 100mb.test && rm -fr 100mb.test"
	wget cachefly.cachefly.net/100mb.test -O 100mb.test && rm -fr 100mb.test
}

############################################################
# Print OS summary (OS, ARCH, VERSION)
############################################################
function show_os_arch_version {
	# Thanks for Mikel (http://unix.stackexchange.com/users/3169/mikel) for the code sample which was later modified a bit
	# http://unix.stackexchange.com/questions/6345/how-can-i-get-distribution-name-and-version-number-in-a-simple-shell-script
	ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')

	if [ -f /etc/lsb-release ]; then
		. /etc/lsb-release
		OS=$DISTRIB_ID
		VERSION=$DISTRIB_RELEASE
	elif [ -f /etc/debian_version ]; then
		# Work on Debian and Ubuntu alike
		OS=$(lsb_release -si)
		VERSION=$(lsb_release -sr)
	elif [ -f /etc/redhat-release ]; then
		# Add code for Red Hat and CentOS here
		OS=Redhat
		VERSION=$(uname -r)
	else
		# Pretty old OS? fallback to compatibility mode
		OS=$(uname -s)
		VERSION=$(uname -r)
	fi

	OS_SUMMARY=$OS
	OS_SUMMARY+=" "
	OS_SUMMARY+=$VERSION
	OS_SUMMARY+=" "
	OS_SUMMARY+=$ARCH
	OS_SUMMARY+="bit"

	print_info "$OS_SUMMARY"
}

############################################################
# Fix locale for OpenVZ Ubuntu templates
############################################################
function fix_locale {
	check_install multipath-tools multipath-tools
	export LANGUAGE=en_US.UTF-8
	export LANG=en_US.UTF-8
	export LC_ALL=en_US.UTF-8

	# Generate locale
	locale-gen en_US.UTF-8
	dpkg-reconfigure locales
}

function apt_clean {
	apt-get -q -y autoclean
	apt-get -q -y clean
}

function update_upgrade {
	# Run through the apt-get update/upgrade first.
	# This should be done before we try to install any package
	apt-get -q -y update
	apt-get -q -y upgrade

	# also remove the orphaned stuff
	apt-get -q -y autoremove
}

function update_timezone {
	dpkg-reconfigure tzdata
}


############################################################
# Install 3proxy (version 0.6.1, perfect proxy for LEB, supports authentication, easy config)
############################################################
function install_3proxy {

	if [ -z "$1" ]
	then
		die "Usage: `basename $0` 3proxy [http-proxy port #]"
	fi
        echo "You have chosen port $http_porty"
	# Build 3proxy
	echo "Downloading and building 3proxy"
	mkdir /tmp/proxy
	cd /tmp/proxy
	wget http://www.3proxy.ru/0.6.1/3proxy-0.6.1.tgz
	tar -xvzf 3proxy-0.6.1.tgz
	rm 3proxy-0.6.1.tgz
	cd 3proxy-0.6.1
	apt-get install build-essential
	make -f Makefile.Linux
	
	# Navigate to 3proxy Install Directory
	cd src
	mkdir /etc/3proxy/
	
	# Move 3proxy program to a non-temporary location and navigate there
	mv 3proxy /etc/3proxy/
	cd /etc/3proxy/
	
	# Create a Log File
	touch /var/log/3proxy.log
	
	# Create basic config that sets up HTTP proxy with user authentication
	touch /etc/3proxy/3proxy.cfg
	
	cat > "/etc/3proxy/3proxy.cfg" <<END
# Specify valid name servers. You can locate them on your VPS in /etc/resolv.conf
#
nserver 8.8.8.8
nserver 8.8.4.4
# Leave default cache size for DNS requests:
#
nscache 65536
# Leave default timeout as well:
#
timeouts 1 5 30 60 180 1800 15 60
# If your server has several IP-addresses, you need to provide an external one
# Alternatively, you may ignore this line
#external YOURSEVERIP
# Provide the IP-address to be listened
# If you ignore this line, proxy will listen all the server.s IP-addresses
#internal YOURSEVERIP
# Create users proxyuser1 and proxyuser2 and specify a password
#
users \$/etc/3proxy/.proxyauth
# Specify daemon as a start mode
#
daemon
# and the path to logs, and log format. Creation date will be added to a log name
log /var/log/3proxy.log
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
# Compress the logs using gzip
#
archiver gz /usr/bin/gzip %F
# store the logs for 30 days
rotate 30
# Configuring http(s) proxy
#
# enable strong authorization. To disable authentication, simply change to 'auth none'
# added authentication caching to make life easier
authcache user 60
auth strong cache
# and restrict access for ports via http(s)-proxy and deny access to local interfaces
#
deny * * 127.0.0.1,192.168.1.1
allow * * * 80-88,8080-8088 HTTP
allow * * * 443,8443 HTTPS
# run http-proxy ... without ntlm-authorization, complete anonymity and port ...
#
proxy -n -p$1 -a
# Configuring socks5-proxy
#
# enable strong authorization and authentication caching
#
# Purge the access-list of http-proxy and allow certain users
#
# set the maximum number of simultaneous connections to 32
#authcache user 60
#auth strong cache
#flush
#allow userdefined
#socks
END
	
	# Give appropriate permissions for config file
	chmod 600 /etc/3proxy/3proxy.cfg
	
	# Create external user authentication file
	touch /etc/3proxy/.proxyauth
	chmod 600 /etc/3proxy/.proxyauth 
	cat > "/etc/3proxy/.proxyauth" <<END
## addusers in this format:
## user:CL:password
## see for documenation:  http://www.3proxy.ru/howtoe.asp#USERS
END
	
	# Create initialization scripty so 3proxy starts with system
	touch /etc/init.d/3proxy
	chmod  +x /etc/init.d/3proxy
	cat > "/etc/init.d/3proxy" <<END
#!/bin/sh
#
# chkconfig: 2345 20 80
# description: 3proxy tiny proxy server
#
#
#
#

case "\$1" in
   start)
       echo Starting 3Proxy

       /etc/3proxy/3proxy /etc/3proxy/3proxy.cfg
       ;;

   stop)
       echo Stopping 3Proxy
       /usr/bin/killall 3proxy
       ;;

   restart|reload)
       echo Reloading 3Proxy
       /usr/bin/killall -s USR1 3proxy
       ;;
   *)
       echo Usage: \$0 "{start|stop|restart}"
       exit 1
esac
exit 0

END

	# Make sure 3proxy starts with system

	update-rc.d 3proxy defaults	

	# Add Iptable entry for specified port
	echo "Adding necessary Iptable entry"
	iptables -I INPUT -p tcp --dport $1 -j ACCEPT
	if [ -f /etc/iptables.up.rules ];
	then
	iptables-save < /etc/iptables.up.rules
	fi
	echo ''
	echo '3proxy successfully installed, before you can use it you must add a user and password, for proxy authentication. ' 
	echo 'This can be done using the "3proxyauth [user] [password]" it will add the user to the 3proxy auth file. '
	echo 'If you do not want authentication, edit the 3proxy config file /etc/3proxy/3proxy.cfg  and set authentication to none (auth none)'
	echo 'This will leave your http proxy open to anyone and everyone.'
	
	/etc/init.d/3proxy start
	
	echo "3proxy started"
}

function 3proxyauth {

	if [[ -z "$1" || -z "$2" ]]
	then
		die "Usage: `basename $0` 3proxyauth username password"
	fi
	
	if [ -f /etc/3proxy/.proxyauth ];
	then
	echo "$1:CL:$2" >> "/etc/3proxy/.proxyauth"
	echo "User: $1 successfully added"
	else
	echo "Please install 3proxy (through this script) first."
	fi

}
######################################################################## 
# START OF PROGRAM
########################################################################
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

check_sanity
case "$1" in
mysql)
	install_mysql
	;;
exim4)
	install_exim4
	;;
nginx)
	install_nginx
	;;
php)
	install_php
	;;
dotdeb)
	install_dotdeb
	;;
site)
	install_site $2
	;;
wordpress)
	install_wordpress $2
	;;
mysqluser)
	install_mysqluser $2
	;;
iptables)
	install_iptables $2
	;;
dropbear)
	install_dropbear $2
	;;
3proxy)
	install_3proxy $2
	;;
3proxyauth)
	3proxyauth $2 $3
	;;	
ps_mem)
	install_ps_mem
	;;
apt)
	update_apt_sources
	;;
vzfree)
	install_vzfree
	;;
webmin)
	install_webmin
	;;
sshkey)
	gen_ssh_key $2
	;;
motd)
	configure_motd
	;;
locale)
	fix_locale
	;;
test)
	runtests
	;;
info)
	show_os_arch_version
	;;
system)
	update_timezone
	remove_unneeded
	update_upgrade
	install_dash
	install_vim
	install_nano
	install_htop
	install_mc
	install_iotop
	install_iftop
	install_syslogd
	apt_clean
	;;
*)
	show_os_arch_version
	echo '  '
	echo 'Usage:' `basename $0` '[option] [argument]'
	echo 'Available options (in recomended order):'
	echo '  - dotdeb                 (install dotdeb apt source for nginx 1.2+)'
	echo '  - system                 (remove unneeded, upgrade system, install software)'
	echo '  - dropbear  [port]       (SSH server)'
	echo '  - iptables  [port]       (setup basic firewall with HTTP(S) open)'
	echo '  - mysql                  (install MySQL and set root password)'
	echo '  - nginx                  (install nginx and create sample PHP vhosts)'
	echo '  - php                    (install PHP5-FPM with APC, cURL, suhosin, etc...)'
	echo '  - exim4                  (install exim4 mail server)'
	echo '  - site      [domain.tld] (create nginx vhost and /var/www/$site/public)'
	echo '  - mysqluser [domain.tld] (create matching mysql user and database)'
	echo '  - wordpress [domain.tld] (create nginx vhost and /var/www/$wordpress/public)'
	echo '  '
	echo '... and now some extras'
	echo '  - info                   (Displays information about the OS, ARCH and VERSION)'
	echo '  - sshkey                 (Generate SSH key)'
	echo '  - apt                    (update sources.list for UBUNTU only)'
	echo '  - ps_mem                 (Download the handy python script to report memory usage)'
	echo '  - vzfree                 (Install vzfree for correct memory reporting on OpenVZ VPS)'
	echo '  - motd                   (Configures and enables the default MOTD)'
	echo '  - locale                 (Fix locales issue with OpenVZ Ubuntu templates)'
	echo '  - webmin                 (Install Webmin for VPS management)'
	echo '  - test                   (Run the classic disk IO and classic cachefly network test)'
	echo '  - 3proxy                 (Install 3proxy - Free tiny proxy server, with authentication support, HTTP, SOCKS5 and whatever you can throw at it)'
	echo '  - 3proxyauth             (add users/passwords to your proxy user authentication list)'
	echo '  '
	;;
esac
