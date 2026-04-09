# Nome da rede docker para os containers se comunicarem localmente
NETWORK_NAME=iot_network

# Variáveis padrão (podem ser sobrescritas na linha de comando)
SERVER_IP ?= server_app
CLIENT_PORT ?= 4000
SENSOR_PORT ?= 5000

.PHONY: setup-network build-all build-server build-client build-sensor build-actuator run-server run-client run-sensor run-actuator

# Cria a rede docker caso ela não exista
setup-network:
	@docker network inspect $(NETWORK_NAME) >/dev/null 2>&1 || docker network create $(NETWORK_NAME)

# --- COMANDOS DE BUILD ---

build-server:
	docker build -f apps/server/Dockerfile -t iot_server .

build-client:
	docker build -f apps/client/Dockerfile -t iot_client .

build-sensor:
	docker build -f apps/sensor/Dockerfile -t iot_sensor .

build-actuator:
	docker build -f apps/actuator/Dockerfile -t iot_actuator .

build-all: build-server build-client build-sensor build-actuator

# --- COMANDOS DE EXECUÇÃO ---

# O Servidor possui um nome fixo (server_app) para facilitar a descoberta local
# e mapeia a porta 8080 TCP e UDP para a máquina hospedeira.
run-server: setup-network build-server
	docker run -it --rm \
		--name server_app \
		--network $(NETWORK_NAME) \
		-p 4000:4000/tcp \
		-p 5000:5000/udp \
		iot_server

# Clientes, Sensores e Atuadores NÃO possuem nome fixo (--name).
# Isso permite que você rode "make run-sensor" múltiplas vezes em abas diferentes
# para simular vários dispositivos simultaneamente.
run-client: setup-network build-client
	docker run -it --rm \
		--network $(NETWORK_NAME) \
		-e SERVER_HOST=$(SERVER_IP) \
		-e SERVER_IP=$(SERVER_IP) \
		-e SERVER_PORT=$(CLIENT_PORT) \
		iot_client

run-sensor: setup-network build-sensor
	docker run -it --rm \
		--network $(NETWORK_NAME) \
		-e SERVER_HOST=$(SERVER_IP) \
		-e SERVER_IP=$(SERVER_IP) \
		-e SERVER_PORT=$(SENSOR_PORT) \
		iot_sensor

run-actuator: setup-network build-actuator
	docker run -it --rm \
		--network $(NETWORK_NAME) \
		-e SERVER_HOST=$(SERVER_IP) \
		-e SERVER_IP=$(SERVER_IP) \
		-e SERVER_PORT=$(CLIENT_PORT) \
		iot_actuator
