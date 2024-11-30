#!/bin/bash
#######################################################___________________Переменные__________________#########################################################
#####____Глобальные переменные____####
ssh_key="ssh_rsa" # название ssh ключа в проекте
vinfra_password="****" #Пароль от root кибера в домене Default
domain_name="VDI" #Имя нового домена
project_name="VDI" # Имя нового проекта
PASSWORD="****" # Пароль от админа домена
#_Сеть_#
net_name="vdi_net" # название сети
cidr="172.30.1.0/24" #CIDR
gateway="172.30.1.1" # Шлюз
dns="8.8.8.8" # DNS
pool="172.30.1.5-172.30.1.250" # Пул адресов в вирутальной сети
swith_name="vdi_switch" # Название маршрутизатора
name_balnacer="vdi_balancer" # Название балансировщика нагрузки
#################################################################################################################################################################

###############__Загрузка образов__################################
mkdir -p /mnt/nfs_obraz # Создаем папку для передачи образов образов из NFS хранилища
mkdir /mnt/VDI # Создаем папку на сервере для образов
mount 10.22.17.101:/Obraz /mnt/nfs_obraz # Монтируем NFS хранилище для передачи образов на сервер
cp /mnt/nfs_obraz/* /mnt/VDI # Передаем образы на сервере
wait
cd /mnt/VDI # Переходим в папку с образами на сервере

############################____Загрузка образов из папки в Киберинфраструктуру____################################
install_image() {
# Путь к папке с файлами образов
folder_path="/mnt/VDI"

# Список образов, которые нужно проверить на наличие
images_to_check=(
    "vdi-server-2024-05-30.qcow2"
    "vdi-mysql-2024-04-02.qcow2"
    "redos-base-gold-2024-05-29.qcow2"
    "alt-base-gold-2023-11-29.qcow2_shrinked.qcow2"
    "vdi-setup-2024-04-20.qcow2"
    "vdi-tunnel-2024-05-16.qcow2"
)

# Получаем список существующих образов
existing_images=$(vinfra service compute image list -f value -c name)

# Проходим по всем файлам в папке
for file in "$folder_path"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")

        # Проверяем, есть ли файл в списке необходимых образов
        if printf '%s\n' "${images_to_check[@]}" | grep -qx "$filename"; then
            # Проверяем, есть ли образ уже в системе
            if echo "$existing_images" | grep -qx "$filename"; then
                echo "Образ '$filename' уже существует, пропускаем добавление."
            else
                echo "Добавляем образ '$filename'..."
                vinfra service compute image create --file "$file" "$filename" --public --wait
            fi
        else
            echo "Образ '$filename' не в списке необходимых образов, пропускаем."
        fi
    fi
done

}

install_image
#####################################################################################################################

#########################################################################___Развертка кибер VDI___########################################################################################

#__Создание ssh-ключа__#
KEY_PATH="$HOME/.ssh/id_rsa"
ssh-keygen -t rsa -b 4096 -N "" -f "$KEY_PATH" -q

##__Создание проекта__##
vinfra domain create --enable $domain_name --vinfra-password $vinfra_password #__Вводим пароль от vinfra только один раз__#
vinfra domain project create --enable --domain $domain_name $project_name
project_id=$(vinfra domain project show --domain $domain_name $project_name | grep '^| id ' | awk '{print $4}')
##___Создание админа домена___##
echo -e "$PASSWORD\n$PASSWORD" | vinfra domain user create --domain $domain_name --domain-permissions domain_admin --enable admin
#_Назначение квоты в проект_#
vinfra service compute quotas update --lbaas-loadbalancer -1 $project_id
#___Авторизируемся как админ в новом проекте___#
export VINFRA_DOMAIN=$domain_name
export VINFRA_PROJECT=$project_name
export VINFRA_USERNAME=admin
export VINFRA_PASSWORD=admin

#__Добавление ssh-ключа в проект__#
vinfra service compute key create $ssh_key --public-key  /root/.ssh/id_rsa.pub --description /root/.ssh/id_rsa.pub
##___Создание виртуальной сети___##
vinfra service compute network create $net_name --dhcp --cidr $cidr --gateway $gateway --dns-nameserver $dns --allocation-pool $pool # нет --wait
##__Создание маршрутизатора__##
vinfra service compute router create $swith_name --external-gateway public --enable-snat --internal-interface $net_name # нет --wait
##__Создание плавающего IP__##
vinfra service compute floatingip create --network public

#################################################____________________Создание ВМ_______________________####################################################
##__Создание 3 ВМ БД__##
vinfra service compute server create --key-name $ssh_key --network id=$net_name --network id=public --flavor large vdi-mysql-1 --volume source=image,id=vdi-mysql-2024-04-02.qcow2,size=500,rm=yes --wait
vinfra service compute server create --key-name $ssh_key --network id=$net_name --network id=public --flavor large vdi-mysql-2 --volume source=image,id=vdi-mysql-2024-04-02.qcow2,size=500,rm=yes --wait
vinfra service compute server create --key-name $ssh_key --network id=$net_name --network id=public --flavor large vdi-mysql-3 --volume source=image,id=vdi-mysql-2024-04-02.qcow2,size=500,rm=yes --wait
##__Создание 2 ВМ тунели__##
vinfra service compute server create --key-name $ssh_key --network id=$net_name --flavor large vdi-tunnel-1 --volume source=image,id=vdi-tunnel-2024-05-16.qcow2,size=100,rm=yes --wait
vinfra service compute server create --key-name $ssh_key --network id=$net_name --flavor large vdi-tunnel-2 --volume source=image,id=vdi-tunnel-2024-05-16.qcow2,size=100,rm=yes --wait
##__Создание 2 ВМ брокеры__##
vinfra service compute server create --key-name $ssh_key --network id=$net_name --network id=public --flavor large vdi-server-1 --volume source=image,id=vdi-server-2024-05-30.qcow2,size=100,rm=yes --wait
vinfra service compute server create --key-name $ssh_key --network id=$net_name --network id=public --flavor large vdi-server-2 --volume source=image,id=vdi-server-2024-05-30.qcow2,size=100,rm=yes --wait
##__Создание ВМ конфигуратор__##
vinfra service compute server create --key-name $ssh_key --network id=$net_name --network id=public --flavor large vdi-setup --volume source=image,id=vdi-setup-2024-04-20.qcow2,size=100,rm=yes --wait
##__Создание балансировщика нагрузки__##
float_ip=$(vinfra service compute floatingip list | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}")
vinfra service compute load-balancer create --enable --floating-ip $float_ip --enable-ha $name_balnacer $net_name --wait
################################################################################################################################################################

##################________________Добавление IP адресов в переменные____________________#######################################
ip_mysql_1=$(vinfra service compute server show vdi-mysql-1 | awk '/ips:/{getline; print $4; exit}')
ip_public_sql_1=$(vinfra service compute server show vdi-mysql-1 | sed -n '/ips:/,/mac_addr:/p' | grep -oP '(?<=- )\d+\.\d+\.\d+\.\d+' | sed -n '2p')
ip_mysql_2=$(vinfra service compute server show vdi-mysql-2 | awk '/ips:/{getline; print $4; exit}')
ip_public_sql_2=$(vinfra service compute server show vdi-mysql-2 | sed -n '/ips:/,/mac_addr:/p' | grep -oP '(?<=- )\d+\.\d+\.\d+\.\d+' | sed -n '2p')
ip_mysql_3=$(vinfra service compute server show vdi-mysql-3 | awk '/ips:/{getline; print $4; exit}')
ip_public_sql_3=$(vinfra service compute server show vdi-mysql-3 | sed -n '/ips:/,/mac_addr:/p' | grep -oP '(?<=- )\d+\.\d+\.\d+\.\d+' | sed -n '2p')
ip_tunnel_1=$(vinfra service compute server show vdi-tunnel-1 | awk '/ips:/{getline; print $4}')
ip_tunnel_2=$(vinfra service compute server show vdi-tunnel-2 | awk '/ips:/{getline; print $4}')
ip_broker_1=$(vinfra service compute server show vdi-server-1 | awk '/ips:/{getline; print $4; exit}')
ip_broker_2=$(vinfra service compute server show vdi-server-2 | awk '/ips:/{getline; print $4; exit}')
ip_public_conf=$(vinfra service compute server show vdi-setup | sed -n '/ips:/,/mac_addr:/p' | grep -oP '(?<=- )\d+\.\d+\.\d+\.\d+' | sed -n '2p')
ip_load_balancer=$(vinfra service compute load-balancer show $name_balnacer | awk '/address\s+\|/ {print $4}')
#_Проверка переменных_#
echo "ip_mysql_1=$ip_mysql_1"
echo "ip_public_sql_1=$ip_public_sql_1"
echo "ip_mysql_2=$ip_mysql_2"
echo "ip_public_sql_2=$ip_public_sql_2"
echo "ip_mysql_3=$ip_mysql_3"
echo "ip_public_sql_3=$ip_public_sql_3"
########################################################################################################################

##__Создание 4 пулов балансировки__##
#HTTPS-HTTPS 443-443 Брокеры
vinfra service compute load-balancer pool create $name_balnacer --protocol HTTPS --port 443 --algorithm ROUND_ROBIN --backend-protocol HTTPS --backend-port 443 --healthmonitor type=TCP --member address=$ip_broker_1,enabled=true --member address=$ip_broker_2,enabled=true --enable --disable-sticky-session --name HTTPS-HTTPS --wait
#нужно +- 30 секунд
#HTTP-HTTP 80-80
vinfra service compute load-balancer pool create $name_balnacer --protocol HTTP --port 80 --algorithm ROUND_ROBIN --backend-protocol HTTP --backend-port 80 --healthmonitor type=TCP --member address=$ip_broker_1,enabled=true --member address=$ip_broker_2,enabled=true --enable --disable-sticky-session --name HTTP-HTTP --wait
#TCP-TCP 7777-7777 Тунели
vinfra service compute load-balancer pool create $name_balnacer --protocol TCP --port 7777 --algorithm ROUND_ROBIN --backend-protocol TCP --backend-port 7777 --healthmonitor type=TCP --member address=$ip_tunnel_1,enabled=true --member address=$ip_tunnel_2,enabled=true --enable --disable-sticky-session --name TCP-TCP --wait
#HTTPS-HTTPS 8080-8080
vinfra service compute load-balancer pool create $name_balnacer --protocol HTTPS --port 8080 --algorithm SOURCE_IP --backend-protocol HTTPS --backend-port 8080 --healthmonitor type=TCP --member address=$ip_tunnel_1,enabled=true --member address=$ip_tunnel_2,enabled=true --enable --disable-sticky-session --name HTTPS-HTTPST --wait

#####________Настройка отказоустойчивого кластера MariaDB________######

scp -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no /root/.ssh/id* cloud-user@$ip_public_conf:~/.ssh/
scp -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no /root/.ssh/id* cloud-user@$ip_public_sql_1:~/.ssh/
scp -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no /root/.ssh/id* cloud-user@$ip_public_sql_2:~/.ssh/
scp -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no /root/.ssh/id* cloud-user@$ip_public_sql_3:~/.ssh/

# Массив с IP-адресами всех ВМ
hosts_public=("$ip_public_sql_1" "$ip_public_sql_2" "$ip_public_sql_3")

ip_sql_1="$ip_mysql_1"
ip_sql_2="$ip_mysql_2"
ip_sql_3="$ip_mysql_3"
# Сценарий, который будет выполняться на каждой ВМ
setup_script=$(cat << 'EOF'
sudo bash -c 'cat << EOF2 > /etc/systemd/system/mariadb_check.service
[Unit]
Description=Check and Start MariaDB Cluster
After=network.target

[Service]
User=cloud-user
Group=cloud-user
ExecStartPre=/bin/sleep 60
ExecStart=/usr/local/bin/check_and_start_mariadb.sh
Restart=on-failure
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF2'

sudo bash -c 'cat << EOF2 > /usr/local/bin/check_and_start_mariadb.sh
#!/bin/bash

# Список хостов
hosts=("/$ip_sql_1" "/$ip_sql_2" "/$ip_sql_3")

# Флаг для определения, нужно ли выполнять galera_new_cluster
bootstrap_needed=false

# Проверка статуса MariaDB на всех хостах
for host in "\${hosts[@]}"; do
    status=\$(ssh -o StrictHostKeyChecking=no "\$host" "sudo systemctl status mariadb | grep Active | awk '\''{print \$2}'\''")
    if [ "\$status" == "failed" ]; then
        bootstrap_needed=true
    else
        bootstrap_needed=false
        break
    fi
done

# Если все сервисы MariaDB failed
if [ "\$bootstrap_needed" == true ]; then
    for host in "\${hosts[@]}"; do
        # Проверка параметра safe_to_bootstrap
        safe_to_bootstrap=\$(ssh -o StrictHostKeyChecking=no "\$host" "sudo cat /var/lib/mysql/grastate.dat | grep safe_to_bootstrap | awk '\''{print \$2}'\'' | tr -d ','")
        if [ "\$safe_to_bootstrap" == "1" ]; then
            echo "Host \$host is safe to bootstrap. Bootstrapping Galera Cluster..."
            ssh -o StrictHostKeyChecking=no "\$host" "sudo galera_new_cluster"
            ssh -o StrictHostKeyChecking=no "\$host" "sudo systemctl start mariadb"
            
            # Перезапуск MariaDB на остальных хостах
            for other_host in "\${hosts[@]}"; do
                if [ "\$other_host" != "\$host" ]; then
                    ssh -o StrictHostKeyChecking=no "\$other_host" "sudo systemctl start mariadb"
                fi
            done
            
            echo "Кластер MariaDB успешно запущен на всех нодах."
            exit 0
        fi
    done

    # Если ни на одном из хостов safe_to_bootstrap не был равен 1
    echo "Не был найден мастер. Мастером делаю 1 хост."
    ssh -o StrictHostKeyChecking=no "\${hosts[0]}" "sudo sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' /var/lib/mysql/grastate.dat"
    ssh -o StrictHostKeyChecking=no "\${hosts[0]}" "sudo galera_new_cluster"
    ssh -o StrictHostKeyChecking=no "\${hosts[0]}" "sudo systemctl start mariadb"
    
    # Перезапуск MariaDB на остальных хостах
    for other_host in "\${hosts[@]}"; do
        if [ "\$other_host" != "\${hosts[0]}" ]; then
            ssh -o StrictHostKeyChecking=no "\$other_host" "sudo systemctl start mariadb"
        fi
    done
    
    echo "Кластер MariaDB успешно запущен на всех нодах."
else
    echo "Сервис MariaDB запущен. Действия не требуются."
fi
EOF2'

sudo chown cloud-user:cloud-user /usr/local/bin/check_and_start_mariadb.sh
sudo chmod +x /usr/local/bin/check_and_start_mariadb.sh
sudo systemctl enable mariadb_check.service
sudo systemctl daemon-reload
EOF
)

# Цикл по каждой ВМ для выполнения скрипта
for hosts_public in "${hosts_public[@]}"; do
    echo "Подключение к $hosts_public"
    ssh -o StrictHostKeyChecking=no cloud-user@$hosts_public "$setup_script"
    echo "Команды выполнены на $hosts_public, отключение"
done

######################################################################################################################################################################

#####_______________Старт VDI_________________#####

# Прямое присвоение значений переменным
ip_mysql_1_value="$ip_mysql_1"
ip_mysql_2_value="$ip_mysql_2"
ip_mysql_3_value="$ip_mysql_3"
ip_broker_1_value="$ip_broker_1"
ip_broker_2_value="$ip_broker_2"
ip_tunnel_1_value="$ip_tunnel_1"
ip_tunnel_2_value="$ip_tunnel_2"
ip_load_balancer_value="$ip_load_balancer"

# Формирование команды setup_vdi.py
setup_vdi=$(cat << EOF
sudo bash -c 'cat << EOF2 > /tmp/start.sh
setup_vdi.py --broker $ip_broker_1_value $ip_broker_2_value -d $ip_mysql_1_value $ip_mysql_2_value $ip_mysql_3_value -t $ip_tunnel_1_value $ip_tunnel_2_value --broker-balancer $ip_load_balancer_value
EOF2'
sudo chmod 7777 /tmp/start.sh
sh /tmp/start.sh
EOF
)

ssh -o StrictHostKeyChecking=no cloud-user@$ip_public_conf "$setup_vdi"

####################################################################################################################################################################
