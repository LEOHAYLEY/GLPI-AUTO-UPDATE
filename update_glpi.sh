#!/bin/bash
set -uo pipefail
IFS=$'\n\t'

# update_glpi.sh - Performance & Security Edition
LOG="/var/log/glpi_update.log"
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo "  GLPI Update - Segurança e Performance"
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Execute como root." >&2
  exit 1
fi

GLPI_DIR="/var/www/glpi"
CONFIG_PHP="$GLPI_DIR/config/config_db.php"
BACKUP_DIR="/root/glpi_backup_$(date +%Y%m%d_%H%M%S)"

[ -f /etc/debian_version ] && WEB_USER="www-data" || WEB_USER="apache"

# 1) EXTRAÇÃO EM MEMÓRIA (Sem arquivos temporários)
echo "Extraindo credenciais do core..."
if [ ! -f "$CONFIG_PHP" ]; then
    echo "ERRO: Configuração do GLPI não encontrada." >&2
    exit 1
fi

# Perl Regex: A forma mais segura de extrair strings de arquivos PHP
DB_NAME=$(grep -Po "dbdefault\s*=\s*['\"]\K[^'\"]+" "$CONFIG_PHP" || grep -Po "dbname\s*=\s*['\"]\K[^'\"]+" "$CONFIG_PHP")
DB_USER=$(grep -Po "dbuser\s*=\s*['\"]\K[^'\"]+" "$CONFIG_PHP")
DB_PASS=$(grep -Po "dbpassword\s*=\s*['\"]\K[^'\"]+" "$CONFIG_PHP")

if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" ]]; then
    echo "ERRO: Não foi possível ler as credenciais. Abortando por segurança."
    exit 1
fi

# 2) BACKUP INTEGRAL (Banco + Plugins)
echo "Gerando backup de segurança..."
mkdir -p "$BACKUP_DIR"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/glpi_db.sql"
tar -czf "$BACKUP_DIR/glpi_data.tar.gz" -C "$GLPI_DIR" config files marketplace plugins 2>/dev/null || true

# 3) DOWNLOAD E ATUALIZAÇÃO DO CORE
echo "Buscando última versão oficial..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep browser_download_url | grep ".tgz" | head -n1 | cut -d '"' -f4)
wget -q -O /tmp/glpi_latest.tgz "$GLPI_URL"

echo "Substituindo binários (Modo Manutenção)..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:enable || true

# Isolamos a instalação antiga e criamos a nova
mv "$GLPI_DIR" "${GLPI_DIR}_old"
mkdir -p "$GLPI_DIR"
tar -xzf /tmp/glpi_latest.tgz -C /tmp/
mv /tmp/glpi/* "$GLPI_DIR/"

# Restauramos o que é seu (Config, Fotos/Anexos e Plugins)
echo "Restaurando configurações e plugins..."
cp -rp "${GLPI_DIR}_old/config" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/files" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/marketplace" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/marketplace"
cp -rp "${GLPI_DIR}_old/plugins" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/plugins"

# 4) PERMISSÕES E FIX ORACLE CLOUD
chown -R "${WEB_USER}:${WEB_USER}" "$GLPI_DIR"
cat > "${GLPI_DIR}/public/.htaccess" <<HTACCESS
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule ^(.*)$ index.php [QSA,L]
</IfModule>
HTACCESS
chown "${WEB_USER}:${WEB_USER}" "${GLPI_DIR}/public/.htaccess"

# 5) MIGRAÇÃO DE BANCO E LIMPEZA
echo "Finalizando atualização via CLI..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" db:update --no-interaction
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" cache:clear || true
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:disable || true

# Removemos os rastros e a pasta antiga
rm -rf "${GLPI_DIR}_old" /tmp/glpi /tmp/glpi_latest.tgz

echo "=============================================="
echo "  SISTEMA ATUALIZADO COM SUCESSO"
echo "  Sua senha foi preservada e os plugins mantidos."
echo "=============================================="
