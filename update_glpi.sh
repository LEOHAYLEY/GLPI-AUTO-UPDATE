#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

LOG="/var/log/glpi_update.log"
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo "  Atualizador Automático GLPI 
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Execute como root." >&2
  exit 1
fi

GLPI_DIR="/var/www/glpi"
CONFIG_PHP="$GLPI_DIR/config/config_db.php"
BACKUP_DIR="/root/glpi_backup_$(date +%Y%m%d_%H%M%S)"

[ -f /etc/debian_version ] && WEB_USER="www-data" || WEB_USER="apache"

echo "Lendo credenciais de: $CONFIG_PHP"

if [ ! -f "$CONFIG_PHP" ]; then
    echo "ERRO: Arquivo $CONFIG_PHP não encontrado!" >&2
    exit 1
fi

# Extração via Regex Robusto (Ignora espaços, abrange aspas simples/duplas e 'dbdefault')
DB_NAME=$(grep "dbdefault" "$CONFIG_PHP" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" | xargs)
DB_USER=$(grep "dbuser" "$CONFIG_PHP" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" | xargs)
DB_PASS=$(grep "dbpassword" "$CONFIG_PHP" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" | xargs)

# Verificação de segurança
if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" ]]; then
    echo "ERRO: Falha crítica ao ler o config_db.php."
    echo "Verifique se o arquivo está no formato padrão."
    exit 1
fi

echo "Banco Detectado: $DB_NAME"
echo "Usuário Detectado: $DB_USER"

# 3) Backup Total
echo "Iniciando backup em $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/glpi_db.sql"
tar -czf "$BACKUP_DIR/glpi_data_files.tar.gz" -C "$GLPI_DIR" config files marketplace plugins 2>/dev/null || true

# 4) Download
echo "Baixando última versão..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep browser_download_url | grep ".tgz" | head -n1 | cut -d '"' -f4)
wget -q -O /tmp/glpi_latest.tgz "$GLPI_URL"

# 5) Transplante de Core
echo "Substituindo binários..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:enable || true

mv "$GLPI_DIR" "${GLPI_DIR}_old"
mkdir -p "$GLPI_DIR"
tar -xzf /tmp/glpi_latest.tgz -C /tmp/
mv /tmp/glpi/* "$GLPI_DIR/"

echo "Restaurando pastas de persistência e PLUGINS..."
cp -rp "${GLPI_DIR}_old/config" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/files" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/marketplace" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/marketplace"
cp -rp "${GLPI_DIR}_old/plugins" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/plugins"

# 6) Fix .htaccess e Permissões
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

# 7) Update
echo "Executando atualização do banco de dados..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" db:update --no-interaction

# 8) Fim
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" cache:clear || true
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:disable || true
rm -rf "${GLPI_DIR}_old" /tmp/glpi /tmp/glpi_latest.tgz

echo "=============================================="
echo "  SUCESSO: GLPI ATUALIZADO"
echo "=============================================="
