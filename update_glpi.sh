#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# update_glpi.sh - Atualizador Automático GLPI 
LOG="/var/log/glpi_update.log"
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo "  Atualizador Automático GLPI
echo "=============================================="

if [ "$EUID" -ne 0 ]; then
  echo "ERRO: Execute como root (sudo)." >&2
  exit 1
fi

# 1) Definição de Caminhos e Ambiente
GLPI_DIR="/var/www/glpi"
CONFIG_PHP="$GLPI_DIR/config/config_db.php"
BACKUP_DIR="/root/glpi_backup_$(date +%Y%m%d_%H%M%S)"

[ -f /etc/debian_version ] && WEB_USER="www-data" || WEB_USER="apache"

# 2) Extração Cirúrgica de Credenciais (Single Source of Truth)
echo "Extraindo credenciais de: $CONFIG_PHP"
if [ ! -f "$CONFIG_PHP" ]; then
    echo "ERRO: Arquivo de configuração não encontrado em $GLPI_DIR" >&2
    exit 1
fi

# Captura os valores entre aspas simples (formato padrão do GLPI)
DB_NAME=$(grep "dbdefault" "$CONFIG_PHP" | cut -d"'" -f2)
DB_USER=$(grep "dbuser" "$CONFIG_PHP" | cut -d"'" -f2)
DB_PASS=$(grep "dbpassword" "$CONFIG_PHP" | cut -d"'" -f2)

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
    echo "ERRO: Falha na extração dos dados. Verifique o formato do config_db.php" >&2
    exit 1
fi

echo "----------------------------------------------"
echo "DATABASE: $DB_NAME"
echo "USER    : $DB_USER"
echo "----------------------------------------------"

# 3) Backup Integral de Segurança
echo "Iniciando backup preventivo..."
mkdir -p "$BACKUP_DIR"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/glpi_db.sql" || { echo "Falha no dump SQL!"; exit 1; }
tar -czf "$BACKUP_DIR/glpi_data_files.tar.gz" -C "$GLPI_DIR" config files marketplace plugins 2>/dev/null || true

# 4) Download da Última Release Oficial
echo "Buscando última versão no GitHub..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep browser_download_url | grep ".tgz" | head -n1 | cut -d '"' -f4)
wget -q -O /tmp/glpi_latest.tgz "$GLPI_URL"

# 5) Transplante de Binários (Clean Upgrade)
echo "Ativando modo de manutenção e trocando core..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:enable || true

# Backup rápido da pasta atual e criação da nova estrutura limpa
mv "$GLPI_DIR" "${GLPI_DIR}_old"
mkdir -p "$GLPI_DIR"
tar -xzf /tmp/glpi_latest.tgz -C /tmp/
mv /tmp/glpi/* "$GLPI_DIR/"

# Restauração dos dados persistentes
echo "Restaurando Config, Files e Plugins..."
cp -rp "${GLPI_DIR}_old/config" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/files" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/marketplace" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/marketplace"
cp -rp "${GLPI_DIR}_old/plugins" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/plugins"

# 6) Permissões e Fix de Rotas (Oracle Cloud / GLPI 10)
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

# 7) Atualização do Schema via CLI
echo "Executando db:update..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" db:update --no-interaction

# 8) Finalização e Limpeza
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" cache:clear || true
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:disable || true
rm -rf "${GLPI_DIR}_old" /tmp/glpi /tmp/glpi_latest.tgz

echo "=============================================="
echo "  ATUALIZAÇÃO CONCLUÍDA COM SUCESSO"
echo "  LOG: $LOG"
echo "=============================================="
