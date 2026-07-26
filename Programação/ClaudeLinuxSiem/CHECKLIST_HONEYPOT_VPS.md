# 🌐 Checklist — Honeypot exposto em VPS público → Dashboard no Wazuh (Parrot)

> **Objetivo:** subir o **Cowrie** num **VPS público** para coletar ataques **reais** da
> internet e visualizá-los no **Wazuh dashboard** que já roda no ParrotOS de casa.
>
> **Ideia-chave da arquitetura:** o Cowrie (pesado, exposto) fica **no VPS**; o seu Parrot
> só recebe os logs no Wazuh que **você já tem**. O VPS fala com o manager de casa por uma
> **VPN privada (Tailscale)** — assim o seu Wazuh **nunca** fica exposto na internet.

```
   INTERNET (atacantes reais)
        │  scans/brute-force na porta 22
        ▼
┌───────────────────────────────┐      Tailscale (VPN privada, grátis)
│  VPS público                  │  100.x.x.x ──────────────────────────┐
│  • Cowrie (SSH honeypot :22)  │                                      │
│  • Wazuh Agent (id 002)       │                                      ▼
│  • SSH real movido p/ :2202   │              ┌──────────────────────────────────┐
└───────────────────────────────┘              │  ParrotOS (casa)                  │
                                                │  • Wazuh manager (master/worker)  │
                                                │  • Wazuh dashboard  ◄── você olha │
                                                │  • regra 100500 (já existe)       │
                                                └──────────────────────────────────┘
```

---

## 💰 Custos — dá pra fazer por R$ 0

| Item | Grátis? | Observação |
|---|---|---|
| **VPS** | ✅ possível | Oracle Cloud *Always Free*, GCP *free e2-micro*, ou crédito novo da DigitalOcean ($200/60d). Pago: Hetzner ~€4/mês, Vultr ~$2,50/mês. |
| **Tailscale** (VPN) | ✅ sim | Plano pessoal grátis (até 100 dispositivos). |
| **MaxMind GeoLite2** (GeoIP p/ o mapa) | ✅ sim | Só criar conta gratuita e gerar uma license key. |
| **AbuseIPDB / GreyNoise** (threat intel, opcional) | ✅ tier grátis | Chave de API gratuita. |
| **Domínio** | — | **Não precisa**. Usa o IP público do VPS. |
| **Cowrie / Wazuh / iptables** | ✅ open source | — |

> **Recomendação:** comece no **Oracle Free Tier** (grátis pra sempre) ou, se quiser algo
> sem burocracia, um **Hetzner CX22 (~€4/mês)**. Cowrie roda folgado em **1 vCPU / 1 GB RAM / 25 GB**.

---

## ✅ FASE 0 — Contas e decisões
- [ ] Escolher o provedor de VPS (Oracle Free / Hetzner / Vultr / DO).
- [ ] Criar conta na **Tailscale** (login com Google/GitHub).
- [ ] Criar conta **MaxMind** e gerar uma *GeoLite2 license key*.
- [ ] *(opcional)* Criar chave de API no **AbuseIPDB** e/ou **GreyNoise**.

## ✅ FASE 1 — Provisionar o VPS
- [ ] Criar a VM (Ubuntu 22.04/24.04 LTS; 1 vCPU / 1 GB é suficiente).
- [ ] Guardar o **IP público** e a chave SSH.
- [ ] Atualizar: `sudo apt update && sudo apt -y upgrade`.

## ✅ FASE 2 — Endurecer o VPS ⚠️ (fazer ANTES de expor)
> **Cuidado para não se trancar pra fora.** Faça nesta ordem e teste o login novo **antes** de fechar o antigo.
- [ ] Mover o **SSH real** para outra porta (ex.: 2202): editar `/etc/ssh/sshd_config` → `Port 2202`, depois `sudo systemctl restart ssh`.
- [ ] **Abrir um novo terminal** e confirmar: `ssh -p 2202 usuario@IP_DO_VPS` funciona.
- [ ] Firewall (só o essencial):
  - [ ] `22/tcp` **aberta pra todos** (é a isca do honeypot).
  - [ ] `2202/tcp` (SSH real) **só do seu IP**, se possível.
  - [ ] Redirecionar a porta 22 → Cowrie (2222):
        `sudo iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222`
        (tornar persistente com `iptables-persistent`).
- [ ] ⚠️ **Nunca** exponha isto por *port-forward* do roteador de casa. VPS isolado só.
- [ ] ⚠️ Não rode nada sensível no VPS. Cowrie é *medium-interaction* (shell emulado), mas trate o VPS como descartável.

## ✅ FASE 3 — Instalar o Cowrie no VPS (porta 22 pública → 2222)
- [ ] Instalar via **Docker** (mesmo padrão que você já usa) ou nativo.
      Docker: `docker run -d --restart always -p 2222:2222 -v cowrie-log:/cowrie/cowrie-git/var/log/cowrie cowrie/cowrie`
- [ ] Confirmar que o `cowrie.json` está sendo gravado.
- [ ] Testar de fora: `ssh root@IP_DO_VPS` (porta 22) deve cair no Cowrie e logar a tentativa.

## ✅ FASE 4 — Conectar VPS ↔ Parrot via Tailscale
- [ ] Instalar Tailscale **no VPS**: `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`.
- [ ] Instalar Tailscale **no Parrot** (host de casa) e subir: `sudo tailscale up`.
- [ ] Anotar o **IP Tailscale do Parrot** (`tailscale ip -4`, algo como `100.x.x.x`).
- [ ] Testar: do VPS, `ping 100.x.x.x` (Parrot) responde.

## ✅ FASE 5 — Wazuh Agent no VPS → manager de casa
- [ ] Instalar o **Wazuh Agent** no VPS (mesma versão do manager, **4.8.0**).
- [ ] No `/var/ossec/etc/ossec.conf` do agente, apontar o `<server><address>` para o **IP Tailscale do Parrot** (não o IP público!).
- [ ] Adicionar o bloco de leitura do log do Cowrie (igual ao que você fez no host):
      `<localfile><log_format>json</log_format><location>/caminho/cowrie.json</location></localfile>`.
- [ ] No **Parrot**, garantir que o manager escuta em `1514/1515` acessível pela rede Tailscale.
- [ ] Registrar/enrolar o agente e reiniciar: deve aparecer como **agent 002** no dashboard.
- [ ] Conferir `ossec.log` do agente do VPS: sem erro `1103`, lendo o `cowrie.json`.

## ✅ FASE 6 — Regras de detecção (reaproveitar o que existe)
- [ ] Confirmar que a regra **`100500`** (comando no honeypot) está no **master E no worker** (o backup já protege isso).
- [ ] *(recomendado)* Adicionar a **regra nível 10+** para comandos críticos (`cat /etc/passwd`, `wget`, `curl`, `chmod +x`).

## ✅ FASE 7 — GeoIP (o que permite o mapa)
- [ ] Ativar o enriquecimento **GeoIP** no Wazuh (GeoLite2 do MaxMind) para os IPs de origem (`data.srcip`).
- [ ] Validar que os alertas passam a ter `GeoLocation` / coordenadas.

## ✅ FASE 8 — Dashboard dedicado do honeypot (no Wazuh)
Criar um dashboard novo (OpenSearch Dashboards) com estas visualizações:
- [ ] 🗺️ **Mapa** dos IPs de origem (Coordinate/Region Map via GeoIP).
- [ ] 📊 **Top 10 IPs** atacantes.
- [ ] 🔑 **Top usuários e senhas** tentados (`cowrie.username` / `cowrie.password`).
- [ ] 💻 **Comandos executados** (`cowrie.command.input`) — tabela.
- [ ] ⬇️ **Downloads/payloads** capturados pelo Cowrie (ouro pra threat intel).
- [ ] 📈 **Ataques ao longo do tempo** (histograma).

## ✅ FASE 9 — Threat Intel *(opcional, mas é o que casa com "Threat Intel Analyst")*
- [ ] Integração que cruza os IPs atacantes com **AbuseIPDB**/**GreyNoise** e marca "known malicious".
- [ ] Adicionar ao dashboard um painel de "IPs já conhecidos como maliciosos".

## ✅ FASE 10 — Validar e gerar o artefato
- [ ] Deixar rodando **24–48 h** (em pouco tempo já chegam centenas de tentativas reais).
- [ ] Conferir alertas no dashboard filtrando por `rule.id:100500` e `agent.name` do VPS.
- [ ] 📸 **Screenshot** do mapa/painel cheio de ataques reais → currículo / LinkedIn / portfólio.

---

## 🧰 Ferramentas usadas (resumo)
| Função | Ferramenta | Custo |
|---|---|---|
| Servidor público | VPS (Oracle Free / Hetzner / Vultr / DO) | Grátis ou ~€4/mês |
| Honeypot SSH | **Cowrie** | Grátis |
| Redirecionar porta 22 → 2222 | **iptables** | Grátis |
| VPN privada VPS ↔ Parrot | **Tailscale** (ou WireGuard) | Grátis |
| Coleta + correlação | **Wazuh** (agent no VPS, manager no Parrot) | Grátis |
| Mapa / geolocalização | **MaxMind GeoLite2** | Grátis (conta) |
| Enriquecimento threat intel | **AbuseIPDB / GreyNoise** | Grátis (tier) |
| Visualização | **Wazuh Dashboard** (OpenSearch) | Grátis |

## ⚠️ Regras de ouro de segurança
1. Mova o SSH real de porta **e teste o login novo** antes de fechar o antigo.
2. VPS **isolado e descartável** — nada sensível nele; nunca por *port-forward* de casa.
3. O manager fica atrás da **VPN**, nunca exposto na internet.
4. **Não** "revidar" ataques (o vídeo brinca, mas é ilegal). Você só **observa e documenta**.
