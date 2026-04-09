# 🌐 A Rota das Coisas
### Serviço de Integração IoT com **Elixir/OTP** + **Sockets TCP/UDP** + **Docker**

<p align="center">
  <img src="./relatorio/assets/banner-rota-das-coisas.gif" alt="Banner do projeto" width="900"/>
</p>

<p align="center">
  <img alt="Elixir" src="https://img.shields.io/badge/Elixir-OTP-purple?style=for-the-badge&logo=elixir">
  <img alt="Erlang" src="https://img.shields.io/badge/Erlang-BEAM-red?style=for-the-badge&logo=erlang">
  <img alt="Docker" src="https://img.shields.io/badge/Docker-Compose-blue?style=for-the-badge&logo=docker">
  <img alt="Protocolos" src="https://img.shields.io/badge/Protocolos-UDP%20%7C%20TCP-2ea44f?style=for-the-badge">
</p>

---

## 📌 Resumo Executivo

### Contexto
Em Internet das Coisas (IoT), sensores e atuadores geram muitos eventos em paralelo.  
Quando tudo conversa “ponto a ponto”, o sistema fica acoplado, difícil de escalar e propenso a travamentos.

### Problema
- Alto acoplamento entre dispositivos e clientes;
- Gargalo de comunicação quando há muitos dados simultâneos;
- Mistura de tráfegos diferentes (telemetria contínua e comandos críticos) no mesmo canal.

### Solução
A aplicação **A Rota das Coisas** atua como um **hub central**:
- recebe telemetria de sensores via **UDP** (baixo overhead),
- entrega comandos para atuadores via **TCP** (confiável),
- processa tudo de forma concorrente com **BEAM + OTP**,
- roda de forma reproduzível em **containers Docker**.

---

## 🏗️ Arquitetura (visão didática)

<p align="center">
  <img src="./asserts/arquitetura.png" alt="Arquitetura geral do sistema" width="900"/>
</p>



### Componentes do sistema
- **Sensor app** (`apps/sensor`)  
  Emite dados periódicos (telemetria) para o servidor via UDP.
- **Actuator app** (`apps/actuator`)  
  Recebe comandos via TCP e executa ações (ON/OFF etc.).
- **Server app** (`apps/server`)  
  Núcleo do sistema: recebe, roteia, mantém estado e expõe comandos administrativos.
- **Client app** (`apps/client`)  
  Interface shell para listar dispositivos, enviar comandos e visualizar telemetria.
- **Shared app** (`apps/shared`)  
  Contratos comuns de protocolo/mensagem entre aplicações.

---

## ⚙️ Decisões Técnicas 
## 1) Por que Elixir/OTP e BEAM?
A BEAM usa o **modelo de atores**:
- processos leves;
- isolamento de falhas;
- troca de mensagens sem memória compartilhada.

Na prática, isso significa:
- um cliente lento não derruba o servidor;
- uma conexão problemática não bloqueia as demais;
- concorrência massiva com estabilidade.

## 2) Por que UDP para telemetria?
Telemetria costuma ser:
- frequente,
- volumosa,
- tolerante a perdas pontuais.

O **UDP** evita handshake e reduz overhead por mensagem.  
Resultado: maior vazão para fluxo contínuo de dados de sensores.

## 3) Por que TCP para comandos?
Comando de atuador é crítico:
- precisa chegar,
- precisa manter ordem,
- precisa ter confirmação de entrega.

O **TCP** atende esses requisitos com confiabilidade de transporte.

## 4) Supervision Tree (resiliência OTP)
A estrutura usa supervisão para reinício automático de processos e isolamento:

- `Server.TcpServer` → aceita conexões TCP;
- `Server.UdpServer` → recebe datagramas UDP;
- `Server.ClientSupervisor` (`DynamicSupervisor`) → cria handlers por conexão;
- `Server.ClientHandler` → processa sessão TCP de cada cliente;
- `Server.SensorManager` / `Server.ActuadorManager` → estado e registro de dispositivos;
- `Server.Metrics` → observabilidade e métricas internas;
- Tasks assíncronas para processamento sem bloquear listeners.

<p align="center">
  <img src="./asserts/arvore de supervisão.png" alt="Arquitetura distribuida do sistema" width="900"/>
</p>

---

## 📂 Estrutura real do monorepo (umbrella)

```text
iot_system/
├── apps/
│   ├── actuator/
│   │   └── lib/
│   │       ├── actuator.ex
│   │       └── actuator/worker.ex
│   ├── client/
│   │   └── lib/
│   │       ├── client.ex
│   │       ├── client/connection.ex
│   │       └── client/shell.ex
│   ├── sensor/
│   │   └── lib/
│   │       ├── sensor.ex
│   │       └── sensor/worker.ex
│   ├── server/
│   │   └── lib/
│   │       ├── server.ex
│   │       └── server/
│   │           ├── tcp_server.ex
│   │           ├── udp_server.ex
│   │           ├── client_supervisor.ex
│   │           ├── client_handler.ex
│   │           ├── sensor_manager.ex
│   │           ├── actuador_manager.ex
│   │           ├── actuador_handler.ex
│   │           └── metrics.ex
│   └── shared/
│       └── lib/
│           └── shared/
│               ├── protocol.ex
│               └── message.ex
├── config/
├── docker-compose.yml
├── Dockerfile
└── relatorio/
    ├── principal.tex / principal.pdf
    └── *.tex
```

---

## 🧩 Mapa rápido dos módulos (para arguição)

| Módulo | Função |
|---|---|
| `Server.TcpServer` | Escuta conexões TCP e delega sessões sem bloquear o accept loop |
| `Server.UdpServer` | Recebe pacotes UDP de telemetria em alta frequência |
| `Server.ClientSupervisor` | Cria handlers dinamicamente para cada conexão/cliente |
| `Server.ClientHandler` | Processa comandos TCP de uma sessão específica |
| `Server.SensorManager` | Mantém estado/listagem de sensores e seus dados |
| `Server.ActuadorManager` | Mantém atuadores conectados e roteamento de comandos |
| `Server.Metrics` | Exibe dados de observabilidade (processos, memória, in-flight etc.) |
| `Client.Shell` | CLI interativa para demonstração (`ls`, `graph`, `send`, `server status`) |
| `Shared.Protocol` / `Shared.Message` | Contrato de serialização/formato de mensagens entre apps |

---

## ✅ Pré-requisitos

- **Docker** e **Docker Compose** instalados;
- (Opcional) Elixir/Erlang locais para desenvolvimento fora de container.

---

## 🚀 Como rodar (setup rápido)

```bash
# na raiz do projeto
docker compose up --build
```

Comandos úteis:
```bash
# subir em background
docker compose up --build -d

# ver status
docker compose ps

# logs do servidor
docker compose logs -f server

# derrubar tudo
docker compose down
```

---

## 🛠️ Execução alternativa com Makefile (rede local / múltiplas máquinas)

<p align="center">
  <img src="./asserts/arquitetura distribuida.png" alt="Arquitetura distribuida do sistema" width="900"/>
</p>


`Exemplo de execução com 4 máquinas`


Além do `docker compose`, o projeto também fornece um **`Makefile`** para subir os serviços de forma modular.
Esse modo é ideal para:

- simular múltiplos dispositivos em terminais diferentes;
- distribuir cliente/sensor/atuador em outras máquinas da rede local;
- apresentar a arquitetura desacoplada sem depender apenas de um único `compose up`.

### Alvos principais do Makefile

- `make setup-network` → cria a rede Docker `iot_network` (se necessário);
- `make build-server` / `make build-client` / `make build-sensor` / `make build-actuator`;
- `make build-all` → build de todos os apps;
- `make run-server` → sobe o servidor (TCP `4000` e UDP `5000`);
- `make run-client` → sobe cliente interativo;
- `make run-sensor` → sobe 1 sensor por execução;
- `make run-actuator` → sobe 1 atuador por execução.

### Fluxo recomendado (uma máquina, múltiplos terminais)

Terminal 1:
```bash
make run-server
```

Terminal 2:
```bash
make run-client
```

Terminal 3+:
```bash
make run-sensor
```

Terminal 4+:
```bash
make run-actuator
```

> Você pode repetir `make run-sensor` e `make run-actuator` em várias abas para simular carga concorrente.

### Executando em outras máquinas da mesma rede (LAN)

Por padrão, o `Makefile` usa `SERVER_IP=server_app` (resolução interna da rede Docker).
Quando o cliente/sensor/atuador estiver em outro host, passe o IP da máquina do servidor:

```bash
make run-client SERVER_IP=192.168.0.50
make run-sensor SERVER_IP=192.168.0.50
make run-actuator SERVER_IP=192.168.0.50
```

### Variáveis úteis

- `SERVER_IP` (default: `server_app`) → host/IP do servidor;
- `CLIENT_PORT` (default: `4000`) → porta TCP de comandos;
- `SENSOR_PORT` (default: `5000`) → porta UDP de telemetria;
- `NETWORK_NAME` (default: `iot_network`) → rede Docker compartilhada.

Exemplo com portas customizadas:

```bash
make run-server CLIENT_PORT=4100 SENSOR_PORT=5100
make run-client SERVER_IP=192.168.0.50 CLIENT_PORT=4100
make run-sensor SERVER_IP=192.168.0.50 SENSOR_PORT=5100
```

## 🧪 `## Subindo o projeto passo a passo`


### Passo 1 — Subindo o ambiente
No terminal da raiz (modo orquestrado):
```bash
docker compose up --build -d
docker compose ps
```

> Alternativa para demo modular com Makefile:
```bash
make run-server
```

---

### Passo 2 — Telemetria em tempo real (UDP)
Abra o shell do cliente (ajuste o nome do container se necessário):
```bash
docker compose attach client
```

No shell:
```text
> help
Comandos disponíveis:
- help: Exibe esta mensagem de ajuda.
- exit: Encerra o shell.
- q: Sai do modo de monitoramento gráfico.
- ls: Lista todos os sensores ativos.
- ls actuators: Lista todos os atuadores ativos.
- cat sensors: Lista os detalhes de todos os sensores.
- cat <sensor_id>: Exibe os detalhes de um sensor específico.
- cat actuators: Lista os detalhes de todos os atuadores.
- cat actuator <actuator_id>: Exibe os detalhes de um atuador específico.
- graph <sensor_id>: Exibe o gráfico de um sensor específico.
- send <actuator_id> <ON/OFF>: Envia um comando para um atuador específico.
- server status: Exibe o status e métricas de processamento do servidor.
- slow <segundos>: Simula um comando lento para testar concorrência.

```

No shell:
```text
> ls
> graph <id_sensor>
```

---

### Passo 3 — Comandos e confiabilidade (TCP)
Ainda no shell:
```text
> ls actuators
> send <id_atuador> ON
> send <id_atuador> OFF
```
---

### Passo 4 — Concorrência extrema / isolamento
No terminal A (shell cliente):
```text
> slow 15
```

Sem esperar terminar, no terminal B:
```text
> send <id_atuador> ON
> ls
```

Uma operação lenta não bloqueia as demais. Cada conexão é isolada por processo da BEAM.

---

### Passo 5 — Observabilidade
No shell:
```text
> server status
```
---

## Analogia simples

Imagine uma central telefônica:

- **Sensores** são pessoas ligando toda hora para dar atualizações curtas (UDP);
- **Atuadores** são ordens importantes que precisam de confirmação (TCP);
- **Servidor** é o operador que recebe tudo e encaminha corretamente;
- **BEAM** é uma equipe enorme de atendentes independentes: se um fica ocupado, os outros continuam trabalhando.

---

## 📈 Resultados observados 

- Suporte a múltiplas instâncias de sensores emitindo dados em alta frequência;
- Testes com grande volume de conexões TCP simultâneas;
- Processamento não bloqueante mesmo em cenários de estresse;
- Validação da separação de transporte por perfil de tráfego (UDP vs TCP).

---

## ⚠️ Limitações atuais

- Sem persistência histórica de dados em banco;
- Sem autenticação forte de dispositivos;
- Handshake/protocolo de identificação ainda simplificado;
- Sem criptografia de transporte fim-a-fim por padrão.

---

## 🛣️ Trabalhos futuros

- Persistência com banco orientado a séries temporais;
- TLS/mTLS para comandos e autenticação de dispositivos;
- Estratégia de retentativa e QoS para telemetria;
- Dashboards web de observabilidade;
- Cluster BEAM para alta disponibilidade horizontal.

---

## 👤 Autor

**Lucas Oliveira da Silva**  
Departamento de Tecnologia — UEFS  
📧 lucasoliveiraecomp@gmail.com
