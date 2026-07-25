# 🛡️ Mini-Lab SOC — Resumo do Projeto (ParrotOS)

> **Objetivo:** Laboratório SOC em SSD externo com deteção de intrusão (Suricata),
> SIEM (Wazuh), firewall (pfSense) e um honeypot SSH (Cowrie), tudo integrado
> num único fluxo de alertas.
>
> **Estado atual:** ✅ **Lab funcional e persistente** (sobe sozinho após reboot).
> **Base:** ParrotOS Security instalado *bare-metal* no SSD externo (migrado do Kali).
> **Data do último avanço:** 16/07/2026.

---

## 🗺️ Arquitetura atual

```
┌──────────────────────────────────────────────────────────────────────┐
│  HOST: ParrotOS (bare-metal no SSD externo)   victor@parrot           │
│  Wi-Fi wlp4s0 = 192.168.1.8                                           │
│                                                                      │
│  ┌────────────────────────┐   ┌──────────────────────────────────┐  │
│  │ KVM / libvirt (vm1)    │   │ Docker                           │  │
│  │  pfSense (firewall)    │   │  ┌────────────────────────────┐  │  │
│  │  + Suricata 6.0.4 (IDS)│   │  │ Wazuh Cluster 4.8.0        │  │  │
│  │  WAN: 192.168.122.x    │   │  │  master-1 / worker-1       │  │  │
│  │       (KVM default)    │   │  │  + indexer + dashboard     │  │  │
│  │  LAN: 192.168.100.254  │   │  └────────────────────────────┘  │  │
│  └───────────┬────────────┘   │  ┌────────────────────────────┐  │  │
│              │ syslog UDP/514 │  │ Cowrie honeypot (SSH :2222)│  │  │
│              ▼                │  │  → cowrie.json             │  │  │
│  ┌────────────────────────┐   │  └─────────────┬──────────────┘  │  │
│  │ Wazuh Agent (host)     │◄──┼── lê logs locais + cowrie.json   │  │
│  │  agent.id 001          │   └──────────────────────────────────┘  │
│  │  → 192.168.1.8:1514    │──────────► roteado para o WORKER          │
│  └────────────────────────┘                                          │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                      Wazuh Dashboard (Discover / Alerts)
```

### Mapa de rede (referência rápida)
| Elemento | Endereço |
|---|---|
| Host ParrotOS (Wi-Fi `wlp4s0`) | `192.168.1.8` |
| pfSense LAN | `192.168.100.254/24` |
| pfSense WAN (DHCP do KVM) | `192.168.122.x` |
| Rede LAN do lab (lado host, `virbr1`) | `192.168.100.1` |
| Wazuh manager (porta agente) | `192.168.1.8:1514/tcp` |
| Cowrie (SSH honeypot) | `localhost:2222` |
| Redes Docker | `172.17–172.19.x` |

---

## ✅ 1. O que foi feito até agora

- [x] **Migração Kali → ParrotOS** instalado bare-metal no SSD externo (instalador Calamares resolveu a dor de cabeça do Kali).
- [x] **Pré-requisitos de sistema** para o Wazuh: ajuste do `vm.max_map_count` no kernel.
- [x] **Docker Engine** instalado via repositório oficial do Debian (Bookworm) + resolução do conflito do alias `docker`→Podman do Parrot.
- [x] **Wazuh 4.8.0** em cluster multinó via `docker-compose`: `master-1`, `worker-1`, indexer e dashboard.
- [x] **pfSense em VM KVM/QEMU** (`vm1`), gerido por libvirt/virt-manager, com WAN (DHCP) e LAN isolada `192.168.100.254/24`.
- [x] **Suricata (IDS)** instalado como pacote dentro do pfSense, com regras **Emerging Threats** + regras customizadas de teste.
- [x] **Integração pfSense → Wazuh via Syslog (UDP/514)** com decoders/regras customizadas:
  - `rule.id 100010` — evento de firewall do pfSense
  - `rule.id 100022` — alerta Suricata de média gravidade (prioridade 2)
  - (regras de ping: `100012` e `100021`)
- [x] **Wazuh Agent** instalado no próprio host Parrot (`agent.id 001`, `Parrot-Host`).
- [x] **Cowrie (honeypot SSH)** em Docker, escutando na `:2222`, gravando em `cowrie.json`.
- [x] **Integração Cowrie → Wazuh**: regra customizada **`rule.id 100500`** que detecta comandos digitados no honeypot (`cowrie.command.input`). ✅ Alertas subindo no Dashboard.
- [x] **Persistência pós-reboot** configurada (ver secção 5).

---

## 🚧 2. O que ainda falta fazer

- [ ] **Validar o pipeline inteiro após um reboot real** (ligar/desligar e conferir que tudo sobe sozinho e os logs voltam a fluir).
- [ ] **Resolver a limitação de topologia** (ver ⚠️ abaixo): hoje o tráfego *real* do host não passa pelo pfSense, então testes externos (ex. `testmyids.com`) **não** geram alerta no Suricata. Só tráfego direcionado à LAN `192.168.100.x` é inspecionado.
- [ ] **Confirmar que o syslog do pfSense continua a chegar** ao Wazuh depois do reboot (a caixa "Send log messages to remote syslog server" apontando para `192.168.1.8:514`).
- [ ] **Reduzir alertas duplicados** (o ping estava a gerar 2 alertas: `100012` + `100021`).
- [ ] **Regras de alta gravidade no Cowrie** (ex. nível 10 quando o atacante lê `/etc/passwd` ou baixa payload com `wget`/`curl`).
- [ ] **Criar/organizar dashboards** dedicados (um painel só para o honeypot, outro para o firewall/IDS).
- [ ] **Documentar as regras/decoders customizados** (guardar cópia dos `.xml` fora dos containers, senão perdem-se se o volume for recriado).

> ### ⚠️ Limitação de arquitetura conhecida (importante)
> Como o ParrotOS roda *bare-metal* e o pfSense é uma VM **dentro** dele, o host **não está atrás** do firewall. O tráfego normal do Parrot sai pela Wi-Fi `wlp4s0` (`192.168.1.8`) e **não** atravessa a LAN monitorada (`192.168.100.x`). Por isso os testes locais (`nc`, `curl` para `192.168.100.254`) funcionaram, mas o `curl testmyids.com` não gerou alerta. É uma escolha consciente ("não quero forçar o caminho correto") — só fica registado para quando quiseres um SOC que inspecione tudo de verdade.

---

## 🐛 3. Erros principais e como foram solucionados

| # | Erro / Sintoma | Causa | Solução aplicada |
|---|---|---|---|
| 1 | Instalador do **Kali** travava em *"Configure the package manager"* / *"Select and install software"* | Instalador do Debian + energia USB + mirror de rede | **Migrou para ParrotOS** (instalador Calamares) |
| 2 | Comando `docker` era desviado para o **Podman** | Parrot vem com alias `docker`→`podman.sock` de fábrica | Instalou o Docker CE oficial / removeu o desvio |
| 3 | Suricata: `pid file '/var/run/suricata_emX.pid' exists but appears stale` | Processo anterior não encerrou (RAM insuficiente derrubava o serviço) | `rm -f /var/run/suricata_emX.pid` + `killall -9 suricata`; **aumentou a RAM da VM para 3 GB** (correção de raiz) |
| 4 | Interface do Suricata não dava "Play" após adicionar regra custom | Erro de sintaxe/config na regra ICMP | Corrigiu a regra e reiniciou o serviço |
| 5 | `curl testmyids.com` não gerava alerta | Tráfego do host não passa pela LAN do pfSense (ver ⚠️) | Testes redirecionados à LAN (`nc -zv 192.168.100.254 22`, `curl 192.168.100.254`) — esses **funcionaram** |
| 6 | Cowrie: `PermissionError: [Errno 13] ... cowrie.json` | Permissões do volume montado no container | Ajustou dono/permissões da pasta `~/cyber_lab/cowrie/var/log/cowrie` |
| 7 | `wazuh-logcollector: ERROR (1103): Could not open file '.../cowrie.json'` | O `cowrie.json` ainda não existia (Cowrie não conseguia escrever) | Resolvido junto com o #6; ao subir o Cowrie na ordem certa o ficheiro passou a existir |
| 8 | `wazuh-logtest` parava na **Phase 2** (sem Phase 3 = sem alerta) | Regra `100001` mal formada (`$(input)`, `if_sid`, ID duplicado) | Reescreveu como **`rule.id 100500`** com `<decoded_as>json</decoded_as>` + `<field name="eventid">^cowrie.command.input$</field>` |
| 9 | Regra funcionava no `logtest` do **master**, mas **não aparecia no Dashboard** | O agente envia logs para o nó **worker**, que não tinha a regra | Copiou `local_cowrie.xml` **também para o worker** + `wazuh-control restart` → ✅ **FUNCIONOU** |

---

## 🚀 4. Próximos passos recomendados

1. **Teste de reboot completo** — desligar, ligar, esperar ~2 min e rodar o checkup da secção 5.
2. **Simular ataque no honeypot** — conectar via `ssh root@127.0.0.1 -p 2222` e rodar `wget`/`curl`/`cat /etc/passwd`; observar os eventos no Cowrie e no Wazuh.
3. **Criar regra de alta gravidade** (nível 10+) clonando a `100500` para comandos críticos.
4. **Higienizar alertas duplicados** do ping.
5. **Backup das customizações**: guardar cópias de `local_cowrie.xml`, decoders/regras do pfSense e Suricata **fora dos containers** (num diretório versionado no SSD).
6. *(Opcional/avançado)* **Redesenhar a topologia** para o tráfego passar mesmo pelo pfSense (VMs vítimas na LAN, ou o host atrás do firewall), fechando a limitação ⚠️.

---

## 🔍 5. Como validar o que foi feito

### 5.1 Checkup rápido pós-reboot (host Parrot)
```bash
# 1. pfSense (VM) está a correr?
sudo virsh list --all           # vm1 deve estar "running"

# 2. Containers no ar?
docker ps                       # master-1, worker-1, cowrie

# 3. Agente a ler os logs sem erro?
sudo tail -n 20 /var/ossec/logs/ossec.log
#   procurar:  Analyzing file: '.../cowrie/cowrie.json'
#   NÃO deve aparecer:  ERROR (1103): Could not open file
```

### 5.2 Testar a cadeia do Honeypot (fim a fim)
```bash
# Gera atividade no honeypot
ssh root@127.0.0.1 -p 2222      # senha qualquer; tente 'whoami', 'uname -a'

# Confirma que o Cowrie registou
tail -n 20 ~/cyber_lab/cowrie/var/log/cowrie/cowrie.json
```
No **Wazuh Dashboard → Discover**, filtrar por:
```
rule.id: "100500"
```
> Deve aparecer o alerta **"Cowrie: Comando executado no Honeypot: <comando>"** (nível 5).

### 5.3 Testar a regra isoladamente (sem esperar pelo Dashboard)
```bash
docker exec -it multi-node-wazuh.master-1 /var/ossec/bin/wazuh-logtest
# colar uma linha do cowrie.json e conferir que aparece a "Phase 3" com id 100500
```
> ⚠️ Lembrete: a regra tem de existir **no master E no worker** (o agente cai no worker).

### 5.4 Testar Suricata + pfSense
```bash
# Tráfego DENTRO da LAN monitorada (é o que o Suricata enxerga)
nc -zv 192.168.100.254 22
for i in {1..45}; do curl -s -o /dev/null http://192.168.100.254/ & done
```
No Dashboard, filtrar por:
```
rule.groups: "suricata"     # alertas do IDS
rule.id: "100010"           # eventos de firewall do pfSense
```

### 5.5 Configs / ficheiros-chave (onde mexer)
| O quê | Onde |
|---|---|
| Config do agente Wazuh (host) | `/var/ossec/etc/ossec.conf` (bloco `<server>` → `192.168.1.8:1514`) |
| Regra custom do Cowrie | `/var/ossec/etc/rules/local_cowrie.xml` (dentro do **master e do worker**) |
| Logs do agente Wazuh | `/var/ossec/logs/ossec.log` |
| Logs do Cowrie | `~/cyber_lab/cowrie/var/log/cowrie/cowrie.json` |
| Syslog do pfSense → Wazuh | pfSense: *Status → System Logs → Settings → Remote Logging* (`192.168.1.8:514`) |
| Suricata | Painel web do pfSense → *Services → Suricata* |

---

## 🔁 6. Persistência (o que já está configurado para sobreviver ao reboot)

```bash
sudo virsh autostart vm1            # pfSense sobe sozinho ✅ (já feito)
sudo virsh net-autostart default    # rede KVM sobe sozinha (⚠️ confirmar se foi feito)
sudo systemctl enable wazuh-agent   # agente inicia no boot
docker update --restart always $(docker ps -a -q)   # containers reiniciam sozinhos
```
> **Ordem de subida (se precisar subir na mão):** pfSense (KVM) → Wazuh cluster → Cowrie → `wazuh-agent`.
> O agente deve ser o **último**, para o `cowrie.json` já existir quando ele começar a ler.

---

*Documento gerado a partir do log completo do projeto (`ParrotOS_MiniLAB.pdf`, 252 págs).*
