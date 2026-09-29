#ansible-playbook -i inventory_1fpb_alu.ini configure_subnet_alias.yml -e "id_aula=5"

ansible-playbook -i inventory_thinkpad.ini simulate_multiple_ips_nm.yml -e "id_aula=80" -e "interface_target=wlan0" --fork 20 --limit "thinkpad88" -b -k --ask-become-pass
