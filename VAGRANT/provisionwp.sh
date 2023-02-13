#!/bin/bash

#INSTALACION DE PAQUETES DE MARIADB, NGINX Y WORDPRESS
apt-get -y update
apt-get -y install nginx mariadb-server mariadb-common php-fpm php-mysql expect php-curl php-gd php-intl php-mbstring php-soap php-xml php-xmlrpc php-zip

########### NGINX
ufw allow 'Nginx HTTP'  #Aplico ajustes al firewall

#VER SI EXISTEN LOS DIRECTORIOS Y SI NO EXISTEN, CREARLOS

DIRECTORIO=/etc/nginx/sites-available/ 
if [ ! -d "$DIRECTORIO" ]
then
    mkdir -p $DIRECTORIO
fi

DIRECTORIO=/etc/nginx/sites-enabled/
if [ ! -d "$DIRECTORIO" ]
then
   mkdir -p $DIRECTORIO
fi


cat << EOF > /etc/nginx/sites-available/wordpress
# Managed by installation script - Do not change
server {
    listen 80;
    root /var/www/wordpress;
    index index.php index.html index.htm index.nginx-debian.html;
    server_name localhost;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

FICHERO=/etc/nginx/sites-available/default
FICHERO_ENLACE=/etc/nginx/sites-enabled/default
if [ -f $FICHERO ]
then
    rm -f $FICHERO
    rm -f $FICHERO_ENLACE
fi


#CREO ENLACE
ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled 

############## MARIADB

#EJECUTO LA SECUENCIA DE SEGURIDAD DE MARIADB
mysql --user=root <<_EOF_
UPDATE mysql.user SET Password=PASSWORD('password123') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
_EOF_

##########WORDPRESS

mysql --user=root <<_EOF_
CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE
utf8_unicode_ci;
GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost' IDENTIFIED BY
'keepcoding';
FLUSH PRIVILEGES;
_EOF_


curl -O https://wordpress.org/latest.tar.gz #Descargo
tar -xvf latest.tar.gz #Descomprimo
cp -R wordpress/ /var/www/wordpress/

#ELIMINAR TAG GZ Y DESCOMPRIMIDO ANTIGUO

rm latest.tar.gz
rm -rf wordpress/


#CONFIGURAR CONEXION

cat << EOF > /var/www/wordpress/wp-config.php
<?php

define( 'DB_NAME', 'wordpress' );

define( 'DB_USER', 'wordpressuser' );

define( 'DB_PASSWORD', 'keepcoding' );

define( 'DB_HOST', 'localhost' );

define( 'DB_CHARSET', 'utf8' );

define( 'DB_COLLATE', '' );
define( 'AUTH_KEY',         'put your unique phrase here' );
define( 'SECURE_AUTH_KEY',  'put your unique phrase here' );
define( 'LOGGED_IN_KEY',    'put your unique phrase here' );
define( 'NONCE_KEY',        'put your unique phrase here' );
define( 'AUTH_SALT',        'put your unique phrase here' );
define( 'SECURE_AUTH_SALT', 'put your unique phrase here' );
define( 'LOGGED_IN_SALT',   'put your unique phrase here' );
define( 'NONCE_SALT',       'put your unique phrase here' );
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF

#USUARIO Y GRUPO WWW-DATA
chown www-data:www-data -R /var/www/wordpress #Asigno el directorio al grupo y al usuario

#########FILEBEAT

#IMPORTO LA LLAVE
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-7.x.list

#INSTALACION Y ACTUALIZACION DE FILEBEAT Y DE UTILIDADES (yq)
apt-get install -y apt-transport-https
apt-get update -y && apt-get install -y filebeat
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod a+x /usr/local/bin/yq

#HABILITO MODULOS SYSTEM Y NGINX
filebeat modules enable system
filebeat modules enable nginx

#CONFIGURO EL FILEBEAT
yq e -i '."filebeat.inputs"[1].type = "log"' /etc/filebeat/filebeat.yml
yq e -i '."filebeat.inputs"[1].enabled = true' /etc/filebeat/filebeat.yml
yq e -i '."filebeat.inputs"[1].paths[0] = "/var/log/*.log"' /etc/filebeat/filebeat.yml
yq e -i '."filebeat.inputs"[1].paths[1] = "/var/log/nginx/*.log"' /etc/filebeat/filebeat.yml
yq e -i '."filebeat.inputs"[1].paths[2] = "/var/log/mysql/*.log"' /etc/filebeat/filebeat.yml

sed -i 's/output.elasticsearch/#output.elasticsearch/g' /etc/filebeat/filebeat.yml 
sed -i 's/hosts: \["localhost:9200"\]/#hosts: \["localhost:9200"\]/g' /etc/filebeat/filebeat.yml

sed -i 's/#output.logstash/output.logstash/g' /etc/filebeat/filebeat.yml 
sed -i 's/#hosts: \["localhost:5044"\]/  hosts: \["192.168.0.3:5044"\]/g' /etc/filebeat/filebeat.yml

# REINICIO SERVICIOS
systemctl restart nginx 
systemctl restart mariadb 
systemctl restart php7.4-fpm
systemctl restart filebeat

# HABILITO EL SERVICIO DE NUEVO POR SI PARO LA MAQUINA
systemctl enable nginx 
systemctl enable mariadb 
systemctl enable php7.4-fpm
systemctl enable filebeat

