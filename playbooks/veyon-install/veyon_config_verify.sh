#!/bin/bash
# verificar-configuracion.sh
echo "=== VERIFICACIÓN CONFIGURACIÓN VEYON ==="
echo "Rol: $(veyon-cli config get Network/Role)"
echo "AutoStart: $(veyon-cli config get Service/AutoStart)"
echo "Método Auth: $(veyon-cli config get Authentication/Method)"
echo "Backend Auth: $(veyon-cli config get Authentication/Backend)"
echo "Notificaciones Icono: $(veyon-cli config get UserInterface/NotificationIconEnabled)"
echo "Notificaciones Acceso: $(veyon-cli config get UserInterface/AccessNotificationEnabled)"
echo "Notificaciones Conexión: $(veyon-cli config get UserInterface/ConnectionNotificationEnabled)"
echo "Access Control Backend: $(veyon-cli config get AccessControl/Backend)"
echo "Access Rule: $(veyon-cli config get AccessControl/AccessRule)"
echo "Servicio: $(systemctl is-active veyon)"