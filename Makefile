SHELL := /bin/bash

DOCKER_COMPOSE := docker compose
APP_SERVICE := app

.PHONY: up down restart logs ps app-shell db-shell deps setup migrate reset test test-watch format ping clean

up:
	$(DOCKER_COMPOSE) up -d --build

down:
	$(DOCKER_COMPOSE) down

restart: down up

logs:
	$(DOCKER_COMPOSE) logs -f --tail=200

ps:
	$(DOCKER_COMPOSE) ps

app-shell:
	$(DOCKER_COMPOSE) exec $(APP_SERVICE) sh

db-shell:
	$(DOCKER_COMPOSE) exec postgres psql -U $${POSTGRES_USER:-postgres} -d $${POSTGRES_DB:-social_scribe_dev}

deps:
	$(DOCKER_COMPOSE) exec $(APP_SERVICE) mix deps.get

setup:
	$(DOCKER_COMPOSE) exec $(APP_SERVICE) mix setup

migrate:
	$(DOCKER_COMPOSE) exec $(APP_SERVICE) mix ecto.migrate

reset:
	$(DOCKER_COMPOSE) exec $(APP_SERVICE) mix ecto.reset

test:
	$(DOCKER_COMPOSE) exec -e MIX_ENV=test -e POSTGRES_TEST_DB=social_scribe_test -e POSTGRES_HOST=postgres $(APP_SERVICE) sh -c "mix deps.get && mix test"

test-watch:
	$(DOCKER_COMPOSE) exec -e MIX_ENV=test -e POSTGRES_TEST_DB=social_scribe_test -e POSTGRES_HOST=postgres $(APP_SERVICE) mix test.watch

format:
	$(DOCKER_COMPOSE) exec $(APP_SERVICE) mix format

ping:
	curl -fsS http://localhost:$${APP_PORT:-4100} > /dev/null && echo "App reachable on http://localhost:$${APP_PORT:-4100}"

clean:
	$(DOCKER_COMPOSE) down -v --remove-orphans
