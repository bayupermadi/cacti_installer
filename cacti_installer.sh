#!/bin/bash

## generate random hash for password
pswd () {
   local p1=`date | md5sum | cut -c1-16`
   echo $p1
   sleep 1
}

## install deps
yum install -y httpd httpd-devel
yum install -y php-mysql php-pear php-common php-gd php-devel php php-mbstring php-cli
yum install -y php-snmp
yum install -y net-snmp-utils net-snmp-libs net-snmp-devel
yum install -y rrdtool
yum install -y ntpdate

## install mariadb10
echo "[mariadb]" >> /etc/yum.repos.d/MariaDB.repo
echo "name = MariaDB" >> /etc/yum.repos.d/MariaDB.repo
echo "baseurl = http://yum.mariadb.org/10.1/centos7-amd64" >> /etc/yum.repos.d/MariaDB.repo
echo "gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB" >> /etc/yum.repos.d/MariaDB.repo
echo "gpgcheck=1" >> /etc/yum.repos.d/MariaDB.repo
yum install -y MariaDB-server MariaDB-client mariadb-devel

## run the service
systemctl start httpd.service
systemctl start mariadb.service
systemctl start snmpd.service
systemctl start ntpd.service

## set autostart once boot
systemctl enable httpd.service
systemctl enable mariadb.service
systemctl enable snmpd.service
systemctl enable ntpd.service

## install the cacti
yum install -y epel-release
yum install -y cacti

## set mysql password
root_pass=$(pswd)
echo "Mysql Root Password= $root_pass" >> ~/password.txt
mysqladmin -u root password $root_pass

## prepare cacti database
cacti_pass=$(pswd)
echo "Mysql Cacti Password= $cacti_pass" >> ~/password.txt
mysql -uroot --password=$root_pass -e "create database cacti"
mysql -uroot --password=$root_pass -e "GRANT ALL ON cacti.* TO cacti@localhost IDENTIFIED BY '$cacti_pass'"
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root --password=$root_pass mysql
mysql -uroot --password=$root_pass -e "GRANT SELECT ON mysql.time_zone_name TO cacti@localhost;"
mysql -uroot --password=$root_pass -e "FLUSH privileges"

## install cacti tables database
cacti_sql=`rpm -ql cacti | grep cacti.sql`
mysql -u cacti -D cacti --password=$cacti_pass < $cacti_sql

## configure cacti db connection
sed -i "s#$database_username = 'cactiuser';#$database_username = 'cacti';#g" /etc/cacti/db.php
sed -i  "s#database_password[[:space:]]\+=[[:space:]]\+'cacti'#database_password = '$cacti_pass'#g" /etc/cacti/db.php

## configure firewall
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --reload

## configure apache server
sed -i "s#Require host localhost#Require all granted#g" /etc/httpd/conf.d/cacti.conf
systemctl restart httpd.service

## configure php settings
server_zone=`timedatectl | grep "Time zone" | awk '{print $3}'`
sed -i "s#;date.timezone[[:space:]]\+=#date.timezone = $server_zone#g" /etc/php.ini
systemctl restart httpd.service

## install spine
yum install -y libtool gcc-c++ openssl-devel help2man
cd /opt/ 
curl -O https://www.cacti.net/downloads/spine/cacti-spine-1.1.36.tar.gz
tar -zxf cacti-spine-1.1.36.tar.gz
cd cacti-spine-1.1.36
aclocal
libtoolize --force 
autoheader
autoconf
automake 
./configure
make
make install

## activate cronjob for cacti
sed -i "s/#//g" /etc/cron.d/cacti

## configure selinux for cacti configuration
chcon -R -t httpd_sys_rw_content_t /usr/share/cacti/resource/script_server/
chcon -R -t httpd_sys_rw_content_t /usr/share/cacti/resource/script_queries/
chcon -R -t httpd_sys_rw_content_t /usr/share/cacti/resource/snmp_queries/


