#ansible-playbook -i inventory_1fpb_alu.ini configure_subnet_alias.yml -e "id_aula=5"

ansible-playbook -i inventory_inf2_alu.ini configure_multiple_ips_nm.yml -b -k --ask-become-pass -e "id_aula=2" -e "interface_target=eth0" --fork 20
