GLPI Auto Update 🚀
Script de alta performance para automação do processo de atualização (upgrade) do GLPI 10. Projetado para ambientes de produção que buscam consistência, segurança de dados e intervenção manual zero.

📋 Diferenciais Estratégicos
Ao contrário de atualizações manuais, este script executa um fluxo otimizado para evitar timeouts e corrupção de arquivos:
Integridade de Dados: Executa backup completo (Dump SQL + Arquivos sensíveis) antes de qualquer alteração.
Zero Downtime Interno: Ativa o modo de manutenção do GLPI via CLI para garantir que nenhuma transação seja feita durante o processo.
Sincronização via Rsync: Atualiza apenas o core do sistema, preservando diretórios de dados (files), configurações (config) e plugins (marketplace).
Compatibility Fix (Oracle Cloud): Recria automaticamente o arquivo .htaccess na pasta public, garantindo que rotas e URLs amigáveis funcionem imediatamente após o update.
Database Migration CLI: Realiza o db:update via console PHP, eliminando gargalos de execução do servidor web.
🛠️ Pré-requisitos
O script foi desenhado para ser totalmente compatível com o GLPI-Auto-Install, utilizando o arquivo de credenciais persistido em:
 /root/glpi_db_credentials.txt

🚀 Como usar
Execute os comandos abaixo no terminal da sua instância (Debian/Ubuntu ou RHEL/Rocky):
```bash
wget https://raw.githubusercontent.com/LEOHAYLEY/GLPI-AUTO-UPDATE/main/update_glpi.sh -O update.sh
chmod +x update.sh
sudo ./update.sh
 ```
 📂 Estrutura de Backup
Em cada execução, o script gera um diretório de salvaguarda em /root/ seguindo o padrão:
glpi_backup_YYYYMMDD_HHMMSS/
glpi_db.sql: Dump completo do banco de dados.
glpi_data_files.tar.gz: Backup das pastas /config, /files e /marketplace.

⚙️ Especificações Técnicas
Recurso,Descrição
Linguagem,Bash Script (Shell)
Compatibilidade,GLPI 10.x.x
OS Suportados,"Debian, Ubuntu, RHEL, Rocky Linux"
Web Server,Apache / HTTPD
Cache Support,Redis (preserva definições em local_define.php)

⚠️ Notas de Segurança
O script deve ser executado obrigatoriamente como root.
Certifique-se de que sua instância possui conectividade externa para baixar a última release oficial do repositório glpi-project/glpi.
