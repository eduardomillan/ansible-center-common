#!/bin/bash

# Obtener las MAC asociadas a las IPs de la red

nmap -sn 172.28.222.0/24 | awk '/^Nmap scan report/ {ip=$NF} /MAC Address:/ {mac=$3; print mac, ip}' > macs_ip_temp.txt
