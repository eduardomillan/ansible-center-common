#ansible-playbook -i inventory_1fpb_alu.ini configure_subnet_alias.yml -e "id_aula=5"

ansible-playbook -i inventory_thinkpad.ini configure_alias_mgmt.yml -b -k --ask-become-pass --limit="thinkpad88,thinkpad89,thinkpad90,thinkpad91,thinkpad92" -e "id_aula=80" -e "interface_target=wlan0"
