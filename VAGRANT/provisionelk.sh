#!/bin/bash

######### INSTALACION DE DEPENDENCIAS

#ACTUALIZO E INSTALO EL JDK
apt update -y
apt install -y default-jre 

#IMPORTO LA LLAVE
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

apt install -y apt-transport-https
apt update -y

##########LOGSTASH

#ACTUALIZO E INSTALO LOGSTASH
apt-get -y update
apt install -y logstash

#VER SI EXISTE el DIRECTORIO Y SI NO EXISTE, CREARLO
DIRECTORIO=/etc/logstash/conf.d
if [ ! -d "$DIRECTORIO" ]
then
    mkdir -p $DIRECTORIO
fi

#CONFIGURO iNPUT
cat << EOF > /etc/logstash/conf.d/02-beats-input.conf
input {
 beats {
   port => 5044
 }
}
EOF

#CONFIGURO FILTER
cat << EOF > /etc/logstash/conf.d/10-syslog-filter.conf
filter {
  if [fileset][module] == "system" {
    if [fileset][name] == "auth" {
      grok {
        match => { "message" => ["%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: %{DATA:[system][auth][ssh][event]} %{DATA:[system][auth][ssh][method]} for (invalid user )?%{DATA:[system][auth][user]} from %{IPORHOST:[system][auth][ssh][ip]} port %{NUMBER:[system][auth][ssh][port]} ssh2(: %{GREEDYDATA:[system][auth][ssh][signature]})?",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: %{DATA:[system][auth][ssh][event]} user %{DATA:[system][auth][user]} from %{IPORHOST:[system][auth][ssh][ip]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: Did not receive identification string from %{IPORHOST:[system][auth][ssh][dropped_ip]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sudo(?:\[%{POSINT:[system][auth][pid]}\])?: \s*%{DATA:[system][auth][user]} :( %{DATA:[system][auth][sudo][error]} ;)? TTY=%{DATA:[system][auth][sudo][tty]} ; PWD=%{DATA:[system][auth][sudo][pwd]} ; USER=%{DATA:[system][auth][sudo][user]} ; COMMAND=%{GREEDYDATA:[system][auth][sudo][command]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} groupadd(?:\[%{POSINT:[system][auth][pid]}\])?: new group: name=%{DATA:system.auth.groupadd.name}, GID=%{NUMBER:system.auth.groupadd.gid}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} useradd(?:\[%{POSINT:[system][auth][pid]}\])?: new user: name=%{DATA:[system][auth][user][add][name]}, UID=%{NUMBER:[system][auth][user][add][uid]}, GID=%{NUMBER:[system][auth][user][add][gid]}, home=%{DATA:[system][auth][user][add][home]}, shell=%{DATA:[system][auth][user][add][shell]}$",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} %{DATA:[system][auth][program]}(?:\[%{POSINT:[system][auth][pid]}\])?: %{GREEDYMULTILINE:[system][auth][message]}"] }
        pattern_definitions => {
          "GREEDYMULTILINE"=> "(.|\n)*"
        }
        remove_field => "message"
      }
      date {
        match => [ "[system][auth][timestamp]", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
      }
      geoip {
        source => "[system][auth][ssh][ip]"
        target => "[system][auth][ssh][geoip]"
      }
    }
    else if [fileset][name] == "syslog" {
      grok {
        match => { "message" => ["%{SYSLOGTIMESTAMP:[system][syslog][timestamp]} %{SYSLOGHOST:[system][syslog][hostname]} %{DATA:[system][syslog][program]}(?:\[%{POSINT:[system][syslog][pid]}\])?: %{GREEDYMULTILINE:[system][syslog][message]}"] }
        pattern_definitions => { "GREEDYMULTILINE" => "(.|\n)*" }
        remove_field => "message"
      }
      date {
        match => [ "[system][syslog][timestamp]", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
      }
    }
  }
}
EOF

#CONFIGURO EL OUTPUT
cat << EOF > /etc/logstash/conf.d/30-elasticsearch-output.conf
output {
 elasticsearch {
   hosts => ["localhost:9200"]
   manage_template => false
   index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
  }
}
EOF

#systemctl enable logstash --now
systemctl restart logstash
systemctl enable logstash

###########ELASTICSEARCH

#INSTALO ELASTICSEARCH
apt install -y elasticsearch

DIRECTORIO=/var/lib/elasticsearch
if [ ! -d "$DIRECTORIO" ]
then
    mkdir -p $DIRECTORIO
fi

chown -R elasticsearch:elasticsearch /var/lib/elasticsearch #Le doy permisos a elasticsearch

#ARRANCO EL SISTEMA
systemctl restart elasticsearch 
systemctl enable elasticsearch

############KIBANA

#INSTALO KIBANA
apt install -y kibana
apt install -y nginx

cat << EOF > /etc/nginx/sites-available/default
# Managed by installation script - Do not change
server {
   listen 80;
   server_name kibana.demo.com localhost;
   auth_basic "Restricted Access";
   auth_basic_user_file /etc/nginx/htpasswd.users;
   location / {
      proxy_pass http://localhost:5601;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection 'upgrade';
      proxy_set_header Host \$host;
      proxy_cache_bypass \$http_upgrade;
   }
}
EOF

#CREO LA CARPETA Y METO LA CONTRASEÑA
echo 'keepcoding' > /vagrant/.kibana

#GENERO EL FICHERO DE LA CONTRASEÑA
echo "kibanaadmin:$(openssl passwd -apr1 -in /vagrant/.kibana)" | sudo tee -a /etc/nginx/htpasswd.users

# REINICIO SERVICIOS
systemctl restart nginx
systemctl restart kibana


# HABILITO EL SERVICIO DE NUEVO POR SI PARO LA MAQUINA
systemctl enable nginx
systemctl enable kibana

