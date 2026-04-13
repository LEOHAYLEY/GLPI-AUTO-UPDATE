#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# update_glpi.sh - Atualizador Automático GLPI
LOG="/var/log/glpi_update.log"
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo "  Atualizador Automático GLPI - Regex Sync"
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Execute como root." >&2
  exit 1
fi

# 1) Definição de Variáveis
GLPI_DIR="/var/www/glpi"
CONFIG_PHP="$GLPI_DIR/config/config_db.php"
BACKUP_DIR="/root/glpi_backup_$(date +%Y%m%d_%H%M%S)"

[ -f /etc/debian_version ] && WEB_USER="www-data" || WEB_USER="apache"

# 2) Extração Lê direto do arquivo de config
echo "Extraindo credenciais do banco de dados..."
if [ ! -f "$CONFIG_PHP" ]; then
    echo "ERRO: Arquivo $CONFIG_PHP não encontrado." >&2
    exit 1
fi

# Regex para capturar os valores entre aspas (funciona com ' ou ")
DB_NAME=$(grep "\$dbname" "$CONFIG_PHP" | sed -E "s/.*='?([^';]+)'?;/\1/" | tr -d "[:space:]")
DB_USER=$(grep "\$dbuser" "$CONFIG_PHP" | sed -E "s/.*='?([^';]+)'?;/\1/" | tr -d "[:space:]")
DB_PASS=$(grep "\$dbpassword" "$CONFIG_PHP" | sed -E "s/.*='?([^';]+)'?;/\1/" | tr -d "[:space:]")

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then
    echo "ERRO: Não foi possível extrair os dados do banco." >&2
    exit 1
fi

# 3) Backup de Segurança
echo "Iniciando backup em $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/glpi_db.sql"
tar -czf "$BACKUP_DIR/glpi_data_files.tar.gz" -C "$GLPI_DIR" config files marketplace plugins 2>/dev/null || true

# 4) Download da Última Versão
echo "Baixando última release..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep browser_download_url | grep ".tgz" | head -n1 | cut -d '"' -f4)
wget -O /tmp/glpi_latest.tgz "$GLPI_URL"

# 5) Troca Limpa de Binários
echo "Limpando core e preparando nova versão..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:enable || true

mv "$GLPI_DIR" "${GLPI_DIR}_old"
mkdir -p "$GLPI_DIR"
tar -xzf /tmp/glpi_latest.tgz -C /tmp/
mv /tmp/glpi/* "$GLPI_DIR/"

# Restaurando Dados e Plugins
echo "Restaurando configurações e plugins..."
cp -rp "${GLPI_DIR}_old/config" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/files" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/marketplace" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/marketplace"
cp -rp "${GLPI_DIR}_old/plugins" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/plugins"

# 6) Permissões e Fix .htaccess (Crucial para Oracle Cloud)
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

# 7) Atualização via CLI
echo "Executando migração do banco de dados..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" db:update --no-interaction

# 8) Finalização
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" cache:clear || true
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:disable || true
rm -rf "${GLPI_DIR}_old" /tmp/glpi /tmp/glpi_latest.tgz

echo "=============================================="
echo "  ATUALIZAÇÃO CONCLUÍDA"
echo "=============================================="
