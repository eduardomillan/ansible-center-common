# Simulación sin cambios reales
#ansible-playbook -i inventory_1fpb_alu.ini simulate_alias_mgmt.yml --check --diff

# Con aula específica
#ansible-playbook -i inventory_1fpb_alu.ini simulate_alias_mgmt.yml -e "id_aula=1" --check --diff

# Con output más detallado
#ansible-playbook -i inventory_1fpb_alu.ini simulate_alias_mgmt.yml -e "id_aula=1" --check -v

ansible-playbook -i inventory_thinkpad.ini simulate_alias_mgmt_simple.yml --check --diff -b -k --ask-become-pass --limit="thinkpad88,thinkpad89,thinkpad90,thinkpad91,thinkpad92" -e "id_aula=80"
