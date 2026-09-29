#!/bin/bash
echo "🔧 Solucionando conflictos de SSH keys..."

# Verificar que se proporcionó un parámetro
if [ -z "$1" ]; then
    echo "❌ Error: Debes proporcionar una red de clase C (ej: 192.168.1.0)"
    echo "Uso: $0 <red>"
    echo "Ejemplo: $0 192.168.1.0"
    exit 1
fi

# Crear backup
cp ~/.ssh/known_hosts ~/.ssh/known_hosts.backup.$(date +%Y%m%d_%H%M%S)

# Extraer los primeros tres octetos de la red
network=$(echo "$1" | cut -d'.' -f1-3)

# Eliminar entradas conflictivas de la red $1 (primer parámetro)
echo "🗑️ Eliminando entradas antiguas para la red $network.0/24..."
for i in {1..254}; do
    ssh-keygen -R "$network.$i" >/dev/null 2>&1
done

# Añadir fingerprints correctos de los equipos activos
echo "🔍 Obteniendo nuevos fingerprints para la red $network.0/24..."
for ip in $(nmap -sn $network.0/24 | grep -oE "$network\.[0-9]+"); do
    ssh-keyscan -H $ip >> ~/.ssh/known_hosts 2>/dev/null
    echo "✅ Añadido: $ip"
done

echo "🎯 Listo! Red $network.0/24 procesada correctamente."
