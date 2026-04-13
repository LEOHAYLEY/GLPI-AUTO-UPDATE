#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# update_glpi.sh - Atualizador automático GLPI 10
LOG="/var/log/glpi_update.log"
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo "  Atualizador Automático GLPI"
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "Execute como root (sudo)." >&2
  exit 1
fi

# 1) Detecção de Ambiente e Variáveis
GLPI_DIR="/var/www/glpi"
CRED_FILE="/root/glpi_db_credentials.txt"
BACKUP_DIR="/root/glpi_backup_$(date +%Y%m%d_%H%M%S)"

if [ -f /etc/debian_version ]; then
  WEB_USER="www-data"
  APACHE_SERVICE="apache2"
else
  WEB_USER="apache"
  APACHE_SERVICE="httpd"
fi

# 2) Recuperar Credenciais do Banco
if [ -f "$CRED_FILE" ]; then
    DB_NAME=$(grep 'DB_NAME=' "$CRED_FILE" | cut -d'=' -f2)
    DB_USER=$(grep 'DB_USER=' "$CRED_FILE" | cut -d'=' -f2)
    DB_PASS=$(grep 'DB_PASS=' "$CRED_FILE" | cut -d'=' -f2)
else
    echo "ERRO: Arquivo de credenciais $CRED_FILE não encontrado." >&2
    exit 1
fi

# 3) Backup de Segurança (Banco e Arquivos)
echo "Criando backup em $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/glpi_db.sql"
tar -czf "$BACKUP_DIR/glpi_data_files.tar.gz" -C "$GLPI_DIR" config files marketplace

# 4) Download da Última Versão
echo "Buscando última versão no GitHub..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
  | grep browser_download_url | grep ".tgz" | head -n1 | cut -d '"' -f4)
wget -O /tmp/glpi_latest.tgz "$GLPI_URL"

# 5) Modo Manutenção e Atualização de Binários
echo "Ativando modo de manutenção e extraindo arquivos..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:enable || true

mkdir -p /tmp/glpi_new
tar -xzf /tmp/glpi_latest.tgz -C /tmp/glpi_new
# Sincroniza o core excluindo pastas de dados que já fizemos backup
rsync -avz /tmp/glpi_new/glpi/ "$GLPI_DIR/" --exclude='config' --exclude='files' --exclude='marketplace'

# 6) Garantir .htaccess e Permissões
echo "Ajustando permissões e fix do .htaccess..."
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

# 7) Atualização do Banco de Dados via CLI
echo "Executando db:update..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" db:update --no-interaction

# 8) Finalização
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" cache:clear || true
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:disable || true

echo "=============================================="
echo "  ATUALIZAÇÃO CONCLUÍDA"
echo "  Backup em: $BACKUP_DIR"
echo "=============================================="
