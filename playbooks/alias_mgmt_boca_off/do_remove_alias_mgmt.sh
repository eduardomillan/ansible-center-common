#ansible-playbook -i inventory_1fpb_alu.ini configure_subnet_alias.yml -e "id_aula=5"

ansible-playbook -i inventory_1fpb_alu.ini remove_alias_mgmt.yml -b -k --ask-become-pass -e "id_aula=21" -e "interface_target=eth0"
