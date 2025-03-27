#!/bin/bash

# Сохранение текущих правил iptables
sudo iptables-save > /tmp/iptables_backup.txt

# Разрешение существующих соединений (для текущего SSH)
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Сброс iptables
sudo iptables -F FORWARD
sudo iptables -F INPUT
sudo iptables -F OUTPUT
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -t raw -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Разрешение SSH через enp4s0
sudo iptables -A INPUT -i enp4s0 -p tcp --dport 22 -j ACCEPT
sudo iptables -A OUTPUT -o enp4s0 -p tcp --sport 22 -j ACCEPT

# Восстановление сохранённой конфигурации UFW
if [ -d ~/ufw_backup ]; then
    sudo ufw disable
    sudo cp ~/ufw_backup/before.rules /etc/ufw/before.rules
    sudo cp ~/ufw_backup/after.rules /etc/ufw/after.rules
    sudo cp ~/ufw_backup/user.rules /etc/ufw/user.rules
    sudo cp ~/ufw_backup/user6.rules /etc/ufw/user6.rules
    sudo ufw enable
else
    echo "Предупреждение: бэкап UFW не найден, используется стандартный сброс."
    sudo ufw allow in on enp4s0 to any port 22 proto tcp
    sudo ufw disable
    sudo ufw reset <<EOF
    y
EOF
fi

# Удаление маршрута
sudo ip route del 188.40.167.82 2>/dev/null

echo "Сброс завершен. Проверка:"
sudo iptables -L -v -n
sudo iptables -t nat -L -v -n
sudo ufw status
echo "Текущий внешний IP:"
curl ifconfig.me