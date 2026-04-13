#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# update_glpi.sh - Atualizador automático GLPI
LOG="/var/log/glpi_update.log"
exec > >(tee -a "$LOG") 2>&1

echo "=============================================="
echo "  Atualizador Automático GLPI - Fix Clean Install"
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
else
  WEB_USER="apache"
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

# 3) Backup de Segurança Integral
echo "Criando backup em $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/glpi_db.sql"
tar -czf "$BACKUP_DIR/glpi_data_files.tar.gz" -C "$GLPI_DIR" config files marketplace

# 4) Download da Última Versão
echo "Buscando última versão no GitHub..."
GLPI_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
  | grep browser_download_url | grep ".tgz" | head -n1 | cut -d '"' -f4)
wget -O /tmp/glpi_latest.tgz "$GLPI_URL"

# 5) Troca Limpa de Binários 
echo "Limpando instalação antiga e instalando binários novos..."
sudo -u "$WEB_USER" php "$GLPI_DIR/bin/console" glpi:maintenance:enable || true

# Move a instalação atual para uma pasta temporária de trabalho
mv "$GLPI_DIR" "${GLPI_DIR}_old"

# Cria a pasta nova e extrai o GLPI limpo
mkdir -p "$GLPI_DIR"
tar -xzf /tmp/glpi_latest.tgz -C /tmp/
# Garante que os arquivos fiquem no local correto (move o conteúdo da pasta extraída para o destino)
mv /tmp/glpi/* "$GLPI_DIR/"

# Restaura apenas os seus dados da pasta antiga para a nova
echo "Restaurando pastas de dados (config, files, marketplace)..."
cp -rp "${GLPI_DIR}_old/config" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/files" "$GLPI_DIR/"
cp -rp "${GLPI_DIR}_old/marketplace" "$GLPI_DIR/" 2>/dev/null || mkdir -p "$GLPI_DIR/marketplace"

# 6) Garantir .htaccess e Permissões (Fix Oracle Cloud)
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

# Limpa a pasta temporária de trabalho
rm -rf "${GLPI_DIR}_old"
rm -rf /tmp/glpi /tmp/glpi_latest.tgz

echo "=============================================="
echo "  ATUALIZAÇÃO CONCLUÍDA COM SUCESSO"
echo "  Sua instalação agora está limpa e atualizada."
echo "=============================================="
