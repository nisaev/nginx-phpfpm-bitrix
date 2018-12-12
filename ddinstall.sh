#!/bin/bash

print(){
    msg=$1
    notice=${2:-0}
    [[ ( $notice -eq 1 ) ]] && echo -e "${msg}"
    [[ ( $notice -eq 2 ) ]] && echo -e "\e[1;31m${msg}\e[0m"
    [[ ( $notice -eq 3 ) ]] && echo -e "\e[30;48;5;82m${msg}\e[0m"
    [[ ( $notice -eq 4 ) ]] && echo -e "\e[32m${msg}\e[0m"
   
    
}

print_e(){
    msg_e=$1
    print "$msg_e" 2
    
    exit 1
}


disable_selinux(){
sestatus_cmd=$(which sestatus 2>/dev/null)
    [[ -z $sestatus_cmd ]] && return 0

    sestatus=$($sestatus_cmd | awk -F':' '/SELinux status:/{print $2}' | sed -e "s/\s\+//g")
    seconfigs="/etc/selinux/config /etc/sysconfig/selinux"
    if [[ $sestatus != "disabled" ]]; then
        print "You must disable SElinux before installing this software." 1
        print "You need to reboot the server to disable SELinux"
        read -r -p "Do you want disable SELinux?(Y|n)" DISABLE
        [[ -z $DISABLE ]] && DISABLE=y
        [[ $(echo $DISABLE | grep -wci "y") -eq 0 ]] && print_e "Exit."
        for seconfig in $seconfigs; do
            [[ -f $seconfig ]] && \
                sed -i "s/SELINUX=\(enforcing\|permissive\)/SELINUX=disabled/" $seconfig && \
                print "Change SELinux state to disabled in $seconfig" 1
        done
        read -r -p "You need to reboot. Reboot?(Y|n)" DREBOOT
        [[ -z $DREBOOT ]] && DREBOOT=y
        [[ $(echo $DREBOOT | grep -wci "y") -eq 0 ]] && print_e "Exit."
        reboot    
        exit
    fi
}	

    print "====================================================================" 2
    print "NGINX + PHP-FPM (Bitrix Edition) for Linux installation script." 2
    print "This script MUST be run as root!" 2
    print "====================================================================" 2


disable_selinux	
read -p "Enter Domain Name (example: domain.ru): " DDOMAIN

while true; do
    read  -s -p "Enter password for MYSQL root(empty will random generate): " MYSQLROOTPASSWORD

    if [[ $MYSQLROOTPASSWORD == "" ]]; then
        MYSQLROOTPASSWORD=`tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c14`
        break
    fi
    echo
    read  -s -p "Confirm password for MYSQL root: " password2
    echo
    [ "$MYSQLROOTPASSWORD" = "$password2" ] && break
    print "Mysql root password and confirmation password do not match. Try again" 1
done


cat > /root/mysql.pass << EOF
$MYSQLROOTPASSWORD
EOF

yum -y install mc nano net-tools wget epel-release
yum -y update
yum -y install yum-utils
rpm -Uhv http://rpms.remirepo.net/enterprise/remi-release-7.rpm


yum -y install nginx
systemctl start nginx
systemctl enable nginx
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --reload


yum-config-manager --enable remi-php71
yum -y install php71
yum -y install php-fpm php-cli php-mysql php-gd php-ldap php-odbc php-pdo php-pecl-memcache php-pear php-xml php-xmlrpc php-mbstring php-snmp php-soap php-zip php-opcache



rm -f /etc/php.ini
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/php.ini -P /etc/


rm -f /etc/php-fpm.d/www.conf
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/www.conf -P /etc/php-fpm.d/




systemctl start php-fpm
systemctl enable php-fpm


rm -f /etc/yum.repos.d/mariadb.repo
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/mariadb.repo -P /etc/yum.repos.d/
yum -y install mariadb-server mariadb


rm -f /etc/my.cnf.d/server.cnf
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/bvat.sh -P /root/
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/bvat.tpl -P /root/
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/bvat.csv -P /root/

sh /root/bvat.sh
systemctl start mariadb
systemctl enable mariadb



mkdir /var/www/$DDOMAIN
bxsname=`tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c10`
wget http://www.1c-bitrix.ru/download/scripts/bitrixsetup.php -O /var/www/$DDOMAIN/install-$bxsname.php

sed -i "s/$bx_host = 'www.1c-bitrix.ru';/$bx_host = 'localhost';/" /var/www/$DDOMAIN/install-$bxsname.php

wget http://www.1c-bitrix.ru/download/scripts/restore.php -O /var/www/$DDOMAIN/restore-$bxsname.php
sed -i "s/restore.php/restore-$bxsname.php/" /var/www/$DDOMAIN/restore-$bxsname.php
sed -i "s/$bx_host = 'www.1c-bitrix.ru';/$bx_host = 'localhost';/" /var/www/$DDOMAIN/restore-$bxsname.php


chown -R nginx:nginx /var/www/$DDOMAIN
chown -R nginx:nginx /var/lib/php/
chown -R nginx:nginx /var/www/



rm -f /etc/php.d/10-opcache.ini
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/10-opcache.ini -P /etc/php.d/

wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/domain10.ru.conf -O /etc/nginx/conf.d/$DDOMAIN.conf
sed -i "s/domain.ru/$DDOMAIN/" /etc/nginx/conf.d/$DDOMAIN.conf


mysql_secure_installation <<EOF

y
$MYSQLROOTPASSWORD
$MYSQLROOTPASSWORD
y
y
y
y
EOF

service nginx restart
service mariadb restart
service php-fpm restart


print "====================================================================" 4
print "\nInstallation Complete!!" 3
print "\nUse http://$DDOMAIN/install-$bxsname.php to install Bitrix" 3
print "Use http://$DDOMAIN/restore-$bxsname.php to restore Bitrix from backup" 3
print "You can find mysql root password in '/root/mysql.pass'" 3
print "====================================================================" 4
