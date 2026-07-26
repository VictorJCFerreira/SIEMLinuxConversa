#!/usr/bin/env bash
# ============================================================
# backup.sh — extrai as customizações do lab SOC para dentro
# do repositório git, para que NADA de detecção (regras,
# decoders, configs) fique só dentro dos volumes Docker.
#
# RODE NO HOST ParrotOS, a partir desta pasta:
#     cd .../Programação/ClaudeLinuxSiem/backup
#     chmod +x backup.sh
#     ./backup.sh
#
# Depois: git add -A && git commit && git push (ver README.md).
# ============================================================
set -euo pipefail

# ---------- AJUSTE AQUI SE OS NOMES/CAMINHOS FOREM DIFERENTES ----------
# Confirme os nomes com:  docker ps --format '{{.Names}}'
MASTER="multi-node-wazuh.master-1"
WORKER="multi-node-wazuh.worker-1"

# Onde estão os docker-compose / configs no seu host (AJUSTE se preciso):
COWRIE_DIR="$HOME/cyber_lab/cowrie"
WAZUH_COMPOSE_DIR="$HOME/cyber_lab/wazuh"
# ----------------------------------------------------------------------

DEST="$(cd "$(dirname "$0")" && pwd)"   # a própria pasta backup/
echo "==> Destino do backup: $DEST"

# ------------------------------------------------------------
# 1) Regras e decoders de DENTRO dos containers Wazuh
#    (extrai do master E do worker — a regra tem de existir nos dois)
# ------------------------------------------------------------
for NODE in master worker; do
  if [ "$NODE" = master ]; then CID="$MASTER"; else CID="$WORKER"; fi
  echo "==> Extraindo regras/decoders do nó '$NODE' ($CID)"
  if ! docker inspect "$CID" >/dev/null 2>&1; then
    echo "   !! container '$CID' não encontrado — confira o nome com 'docker ps' e ajuste o script."
    continue
  fi
  mkdir -p "$DEST/wazuh/$NODE/rules" "$DEST/wazuh/$NODE/decoders"
  docker cp "$CID:/var/ossec/etc/rules/."    "$DEST/wazuh/$NODE/rules/"    2>/dev/null || echo "   (sem rules custom?)"
  docker cp "$CID:/var/ossec/etc/decoders/." "$DEST/wazuh/$NODE/decoders/" 2>/dev/null || echo "   (sem decoders custom?)"
done

# ------------------------------------------------------------
# 2) Config do AGENTE Wazuh no host
#    (copia SÓ o ossec.conf — NUNCA o client.keys, que é segredo)
# ------------------------------------------------------------
echo "==> Copiando ossec.conf do agente (host)"
mkdir -p "$DEST/wazuh/agent"
if sudo test -f /var/ossec/etc/ossec.conf; then
  sudo cp /var/ossec/etc/ossec.conf "$DEST/wazuh/agent/ossec.conf"
  sudo chown "$USER":"$USER" "$DEST/wazuh/agent/ossec.conf"
else
  echo "   (ossec.conf do agente não encontrado em /var/ossec/etc/)"
fi

# ------------------------------------------------------------
# 3) Cowrie — config e docker-compose (NÃO os logs)
# ------------------------------------------------------------
echo "==> Copiando config do Cowrie"
mkdir -p "$DEST/cowrie"
for f in "$COWRIE_DIR/cowrie.cfg" "$COWRIE_DIR/etc/cowrie.cfg"; do
  [ -f "$f" ] && cp "$f" "$DEST/cowrie/" && echo "   + $f"
done
find "$COWRIE_DIR" -maxdepth 2 -iname 'docker-compose*.y*ml' -exec cp {} "$DEST/cowrie/" \; 2>/dev/null || true

# ------------------------------------------------------------
# 4) docker-compose do cluster Wazuh
# ------------------------------------------------------------
echo "==> Copiando docker-compose do Wazuh"
mkdir -p "$DEST/wazuh"
find "$WAZUH_COMPOSE_DIR" -maxdepth 2 -iname 'docker-compose*.y*ml' -exec cp {} "$DEST/wazuh/" \; 2>/dev/null || true

echo ""
echo "==> Concluído. Agora reveja o que mudou:"
echo "      git status"
echo "      git add -A && git commit -m 'backup: customizacoes do lab SOC' && git push -u origin master-l4qind"
echo ""
echo "!! Lembrete de segurança: confira que NENHUM segredo entrou"
echo "   (client.keys, .env, senhas, config.xml do pfSense). O .gitignore"
echo "   já bloqueia os padrões comuns, mas confirme com 'git status'."
