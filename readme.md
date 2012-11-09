## Debian 6 VPS Script

Remove excess packages (apache2, sendmail, bind9, samba, nscd, etc) and install the basic components needed for a light-weight HTTP(S) web server:

 - dropbear (SSH)
 - iptables (firewall)
 - dash (replaces bash)
 - syslogd
 - MySQL (v5.1+ W/O Innodb, configured for lowend VPS)
 - PHP-FPM (v5.3+ with APC installed and configured)
 - exim4 (light mail server)
 - nginx (v1.0+ from dotdeb, configured for lowend VPS. Change worker_processes number in /etc/nginx/nginx.conf according to number of your CPUs)
 - vim, nano, mc, htop, iftop & iotop (more to come...)

Includes sample nginx config files for PHP sites. You can create a basic site shell (complete with nginx vhost) like this:

./setup-debian.sh site example.com

When running the iptables or dropbear install you must specify a SSH port. Remember, port 22 is the default. It's recomended that you change this from 22 just to save server load from attacks on that port.

## Usage (in recomended order)

### Warning! This script is self destructive, it'll overwrite previous configs during reinstallation.

	wget --no-check-certificate https://raw.github.com/Xeoncross/lowendscript/master/setup-debian.sh
	$ ./setup-debian.sh dotdeb # not required if using Ubuntu
	$ ./setup-debian.sh system
	$ ./setup-debian.sh dropbear 22  # or any other port number
	$ ./setup-debian.sh iptables
	$ ./setup-debian.sh mysql
	$ ./setup-debian.sh nginx
	$ ./setup-debian.sh php
	$ ./setup-debian.sh exim4
	$ ./setup-debian.sh site example.com
	$ ./setup-debian.sh wordpress example.com

#### ... and now time for some extras

##### Webmin

	$ ./setup-debian.sh webmin

##### vzfree

Supported only on OpenVZ only, vzfree reports correct memory usage

	$ ./setup-debian.sh vzfree

##### Classic Disk I/O and Network test

Run the classic Disk IO (dd) & Classic Network (cachefly) Test

	$ ./setup-debian.sh test

##### Neat python script to report memory usage per app

Neat python script to report memory usage per app

	$ ./setup-debian.sh ps_mem

##### sources.list updating (Ubuntu only)

Updates Ubuntu /etc/apt/sources.list to default based on whatever version you are running

	$ ./setup-debian.sh apt

##### Info on Operating System, version and Architecture

	$ ./setup-debian.sh info

##### SSH-Keys

Either you want to generate ssh-keys (id_rsa) or a custom key for something (rsync etc)
Note: argument is optional, if its left out, it will write "id_rsa" key

	$ ./setup-debian.sh sshkey [optional argument_1]
    
##### Extras

Fixing locale on some OpenVZ Ubuntu templates

	$ ./setup-debian.sh locale

Configure or reconfigure MOTD

	$ ./setup-debian.sh motd

## After installation

MySQL root is given a new password which is located in ~root/.my.cnf.
After installing the full set, ram usage reaches ~40-45Mb.
By default APC configured to use 16Mb for caching.
To reduce ram usage, you may disable APC by moving or deleting the following file - /etc/php5/conf.d/apc.ini
I recommend installing Ajenti and/or Webmin to manage your VPS.
For security reasons delete, move or password protect "new_domain/public/phpinfo.php" file, which installed automatically on each new site installation.

## Credits

- [LowEndBox admin (LEA)](https://github.com/lowendbox/lowendscript)
- [Xeoncross](https://github.com/Xeoncross/lowendscript),
- [ilevkov](https://github.com/ilevkov/lowendscript),
- [asimzeeshan](https://github.com/asimzeeshan)
- and many others!

