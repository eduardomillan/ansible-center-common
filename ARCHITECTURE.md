# 🏗️ Arquitectura: ansible-center-common

## 📦 Dos Repositorios, Una Filosofía

Este proyecto usa una **arquitectura de dos repositorios** para separar código reutilizable de configuración específica:

### 🌐 ansible-center-common (PÚBLICO)
- **URL:** `github.com/tuusuario/ansible-center-common`
- **Privacidad:** PÚBLICO
- **Contenido:** Playbooks genéricos, reutilizables
- **Propósito:** Referencia educativa, compartible con comunidad
- **Audiencia:** Otros centros educativos, profesores, estudiantes

### 🔒 ansible-center-boca (PRIVADO)
- **URL:** `github.com/tuusuario/ansible-center-boca`
- **Privacidad:** PRIVADO
- **Contenido:** Configuración específica de IES Bocairent
- **Propósito:** Gestión interna de infraestructura
- **Audiencia:** Solo equipo TI de Bocairent

---

## 📋 Contenido por Repositorio

### Ambos Repositorios (Sincronizados)
```
playbooks/              # Idénticos en ambos
├── change-hostname/
├── create-lliurex-user/
├── exec-remote-script/
├── interfaz_virtual_boca/
├── klavaro-ktouch-install/
├── network-scanner/
├── pinta-install/
├── poweroff/
├── restart/
├── ssh-check/
├── unityhub-install/
├── veyon-install/
├── wake-on-lan/
└── alias_mgmt_boca_off/

group_vars/             # Idénticos
├── all.yml

ansible.cfg             # Idénticos
AGENTS.md              # Idénticos
SECURITY.md            # Idénticos
```

### Solo ansible-center-common (PÚBLICO)
```
inventories/
└── inventory.template.ini    # Template de ejemplo

password_ENV.txt.example      # Ejemplo (sin valores reales)
```

### Solo ansible-center-boca (PRIVADO)
```
inventories/
├── inventory.ini              # ⚠️ IPs reales
├── inventory_inf1_alu.ini     # ⚠️ IPs + MACs
├── inventory_inf2.ini         # ⚠️ Configuración de red
├── inventory_inf3.ini         # ⚠️ Laboratorios
├── inventory_thinkpad.ini     # ⚠️ Máquinas específicas
└── vault_secrets.yml          # ⚠️ Credenciales encriptadas

.local/                        # ⚠️ Backups, configuración local
csshs/                         # ⚠️ MACs generadas automáticamente
password_ENV.txt               # ⚠️ Contraseña REAL

setup_local_config.sh          # Scripts de configuración local
```

---

## 🔄 Flujo de Trabajo

### Si Modificas un Playbook

1. **Cambio en ansible-center-boca** (local):
   ```bash
   cd /ruta/a/ansible-center-boca
   # Editar: playbooks/change-hostname/change_host_name.yml
   git add playbooks/
   git commit -m "fix: mejorar manejo de errores en change-hostname"
   git push
   ```

2. **Sincronizar a ansible-center-common**:
   ```bash
   cp -r /ruta/a/ansible-center-boca/playbooks/* \
         /ruta/a/ansible-center-common/playbooks/
   
   cd /ruta/a/ansible-center-common
   git add playbooks/
   git commit -m "sync: actualizar playbooks desde boca"
   git push
   ```

### Si Añades un Nuevo Playbook

1. Crear en boca
2. Probar localmente
3. Sincronizar a common
4. Documentar en AGENTS.md (ambos repos)

---

## ✅ Checklist de Seguridad

Antes de hacer **push a ansible-center-common**, verificar:

```bash
# ✅ No hay archivos de inventario específicos
git ls-files | grep inventory_
# Debe retornar SOLO: inventories/inventory.template.ini

# ✅ No hay archivos de secretos
git ls-files | grep -E "(vault|password_ENV|\.local|csshs)"
# No debe retornar nada

# ✅ No hay IPs privadas en el código
git grep "172\.28\." .
git grep "10\." .
# No debe encontrar nada (o solo en comentarios)

# ✅ Verificar .gitignore funciona
git check-ignore -v inventories/inventory_inf1_alu.ini
# Debe retornar: inventories/inventory_inf1_alu.ini
```

---

## 🚀 Para Nuevos Colaboradores

### Si Quieres Usar Estos Playbooks

1. Clona **solo** el repo público:
   ```bash
   git clone https://github.com/tuusuario/ansible-center-common.git
   ```

2. Crea tu propio inventario:
   ```bash
   cp inventories/inventory.template.ini inventories/inventory.ini
   # Editar con tus valores
   ```

3. Ejecuta los playbooks:
   ```bash
   ansible-playbook playbooks/change-hostname/change_host_name.yml \
     -i inventories/inventory.ini \
     -e "host_name=nuevo-host"
   ```

### Si Eres del IES Bocairent

1. Acceso a ambos repos (requiere permisos)
2. Clona el repo privado (que también tiene los playbooks)
3. Usa `inventories/inventory_*.ini` con configuración real

---

## 🔐 Por Qué Esta Arquitectura

| Beneficio | Explicación |
|-----------|-----------|
| **Seguridad** | IPs y MACs no se exponen públicamente |
| **Reutilización** | Otros centros usan tus playbooks |
| **Mantenibilidad** | Un solo lugar para playbooks, dos para configuración |
| **Aprendizaje** | Ejemplo de buenas prácticas de infraestructura como código |
| **Colaboración** | Comunidad puede mejorar playbooks sin acceso a tu red |

---

## 📞 Soporte

- **Preguntas sobre playbooks:** Abre issue en `ansible-center-common`
- **Problemas de infraestructura:** Contacta a TI del IES Bocairent
- **Mejoras/patches:** Bienvenidos en `ansible-center-common`

---

## 📚 Lecturas Relacionadas

- [AGENTS.md](AGENTS.md) - Catálogo completo de playbooks
- [SECURITY.md](SECURITY.md) - Consideraciones de seguridad
- [README-PRIVADO.md](../ansible-center-boca/README-PRIVADO.md) - Guía del repo privado
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

---

**Última actualización:** 2026-09-29
