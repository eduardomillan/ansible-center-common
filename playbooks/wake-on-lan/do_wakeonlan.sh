ansible-playbook -i ../../inventories/inventory_inf2_alu_net2.ini wake_on_lan_simple.yml -u me.millan -b -k --forks 20 --ask-become-pass -e "wol_broadcast=192.168.2.255"
