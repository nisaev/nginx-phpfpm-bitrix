#!/bin/bash

#Функция вывода цветного текста через print
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

#функция проверяет и отключает SELINUX
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


#запускаем функцию отключения selinux
disable_selinux	

#считываем название домена в переменную DDOMAIN
read -p "Enter Domain Name (example: domain.ru): " DDOMAIN

#считываем пароль два раза - сравниваем. Если пустой - то генерируем рандомный
while true; do
    read  -s -p "Enter password for MYSQL root(empty will random generate): " MYSQLROOTPASSWORD

    if [[ $MYSQLROOTPASSWORD == "" ]]; then
        MYSQLROOTPASSWORD=`tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c14`
        echo
        break
    fi
    echo
    read  -s -p "Confirm password for MYSQL root: " password2
    echo
    [ "$MYSQLROOTPASSWORD" = "$password2" ] && break
    print "Mysql root password and confirmation password do not match. Try again" 1
done

#записываем пароль mysql в файл
cat > /root/mysql.pass << EOF
$MYSQLROOTPASSWORD
EOF


#Запрашиваем необходимость HTTPS
read  -p "Install and activate free HTTPS with Let's Encrypt? (y/n):" DDHTTPS


#устанавливаем необходимые пакеты
yum -y install mc nano net-tools wget epel-release
yum -y update
yum -y install yum-utils
rpm -Uhv http://rpms.remirepo.net/enterprise/remi-release-7.rpm

#подключаем репозиторий с последней стабильной версией nginx и устанавливаем nginx
rm -f /etc/yum.repos.d/nginx.repo
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/nginx.repo -P /etc/yum.repos.d/
yum -y install nginx
systemctl start nginx
systemctl enable nginx
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --reload

#подключаем репозиторий с php 7.2 и устанавливаем
yum-config-manager --enable remi-php72
yum -y install php72
yum -y install php-fpm php-cli php-mysql php-gd php-ldap php-odbc php-pdo php-pecl-memcache php-pear php-xml php-xmlrpc php-mbstring php-snmp php-soap php-zip php-opcache
yum -y install msmtp

#устанавливаем fail2ban 
yum -y install fail2ban-firewalld
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/jail.local -P /etc/fail2ban/
systemctl start fail2ban.service
systemctl enable fail2ban.service

#загружаем конфиг с дополнениями к php.ini
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/customphp.ini -P /etc/php.d/

#меняем настройки php-fpm
old_run="listen = 127.0.0.1:9000"
new_run=';listen = 127.0.0.1:9000\nlisten = \/var\/run\/php-fpm\/php-fpm.sock\nlisten.owner = nginx\nlisten.group = nginx\nlisten.mode = 0660'
sed -i "s/$old_run/$new_run/" /etc/php-fpm.d/www.conf
old_run="user = apache"
new_run="user = nginx"
sed -i "s/$old_run/$new_run/" /etc/php-fpm.d/www.conf
old_run="group = apache"
new_run="group = nginx"
sed -i "s/$old_run/$new_run/" /etc/php-fpm.d/www.conf

#стартуем php-fpm и добавляем в автозагрузку
systemctl start php-fpm
systemctl enable php-fpm

#устанавливаем mariadb 
rm -f /etc/yum.repos.d/mariadb.repo
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/mariadb.repo -P /etc/yum.repos.d/
yum -y install mariadb-server mariadb

#скачиваем и запускаем скрипт автонастройки opcache и mariadb в зависимости от кол-ва ОЗУ на сервере
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/bvat.sh -P /root/
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/bvat.tpl -P /root/
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/bvat.csv -P /root/
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/opcache.tpl -P /root/
sh /root/bvat.sh
systemctl start mariadb
systemctl enable mariadb


#создаем папку домена и скачиванием в нее скрипты битрикса, меняем их имена, и фиксим в них названия файлов
mkdir /var/www/$DDOMAIN
bxsname=`tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c10`
wget http://www.1c-bitrix.ru/download/scripts/bitrixsetup.php -O /var/www/$DDOMAIN/install-$bxsname.php
sed -i "s/$bx_host = 'www.1c-bitrix.ru';/$bx_host = 'localhost';/" /var/www/$DDOMAIN/install-$bxsname.php
wget http://www.1c-bitrix.ru/download/scripts/restore.php -O /var/www/$DDOMAIN/restore-$bxsname.php
sed -i "s/restore.php/restore-$bxsname.php/" /var/www/$DDOMAIN/restore-$bxsname.php
sed -i "s/$bx_host = 'www.1c-bitrix.ru';/$bx_host = 'localhost';/" /var/www/$DDOMAIN/restore-$bxsname.php

#назначаем права папкам
chown -R nginx:nginx /var/www/$DDOMAIN
chown -R nginx:nginx /var/lib/php/
chown -R nginx:nginx /var/www/

#правим hosts для нормальной работы сокетов
wget https://raw.githubusercontent.com/nisaev/nginx-phpfpm-bitrix/master/nginx-domain.conf -O /etc/nginx/conf.d/$DDOMAIN.conf
sed -i "s/domain.ru/$DDOMAIN/" /etc/nginx/conf.d/$DDOMAIN.conf
sed -i "s/127.0.0.1   localhost/127.0.0.1   localhost   $DDOMAIN/" /etc/hosts

#делаем настройки mysql, назначем рут пароль. Перед "y" пустая строка - не убирать!!
mysql_secure_installation <<EOF

y
$MYSQLROOTPASSWORD
$MYSQLROOTPASSWORD
y
y
y
y
EOF

#перезагружаем службы
service nginx restart
service mariadb restart
service php-fpm restart

#устанавливаем certbot и настраиваем https
if [[ ! $DDHTTPS =~ ^[Nn]$ ]]; then
yum -y install certbot python-certbot-nginx
clear

print "Let's Encrypt config manager:" 4
certbot --nginx
crontab -l > mycron.tmp
echo "15 3 * * 6 certbot renew && service nginx restart" >> mycron.tmp
crontab mycron.tmp
rm -f mycron.tmp
fi
    

print "====================================================================" 4
print "\nInstallation Complete!!" 3
print "\nUse http://$DDOMAIN/install-$bxsname.php to install Bitrix" 3
print "Use http://$DDOMAIN/restore-$bxsname.php to restore Bitrix from backup" 3
print "You can find mysql root password in '/root/mysql.pass'" 3
print "====================================================================" 4
