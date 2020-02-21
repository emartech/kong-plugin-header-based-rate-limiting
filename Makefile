SHELL=/bin/bash
.PHONY: help publish test

help: ## Show this help
	@echo "Targets:"
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/\(.*\):.*##[ \t]*/    \1 ## /' | sort | column -t -s '##'

up: ## Start containers
	docker-compose up -d

down: ## Stops containers
	docker-compose down

restart: down up ## Restart containers

clear-db: ## Clears local db
	bash -c "rm -rf .docker"

build: ## Rebuild containers
	docker-compose build --no-cache

complete-restart: clear-db down up    ## Clear DB and restart containers

publish: ## Build and publish plugin to luarocks
	docker-compose run --rm kong bash -c "cd /kong-plugins && chmod +x publish.sh && ./publish.sh"

test: ## Run tests
	docker-compose run --rm kong bash -c "kong migrations bootstrap && cd /kong && bin/busted /kong-plugins/spec"
	docker-compose down

test-full: ## Run tests
	docker-compose run --rm kong bash -c "cd /kong && bin/kong migrations up && bin/busted /kong-plugins/spec"
	docker-compose -f docker-compose.yml -f docker-compose-cassandra.yml down
	docker-compose -f docker-compose.yml -f docker-compose-cassandra.yml run kong bash -c "/wait-for-it.sh kong-database-cassandra:9042 -t 0 && cd /kong && bin/kong migrations up && bin/busted /kong-plugins/spec"
	docker-compose -f docker-compose.yml -f docker-compose-cassandra.yml down

unit: ## Run unit tests
	docker-compose run --rm kong bash -c "cd /kong && bin/kong migrations up && bin/busted --exclude-tags='e2e' /kong-plugins/spec"
	docker-compose down

e2e: ## Run end to end tests
	docker-compose run --rm  kong bash -c "cd /kong && bin/kong migrations up && bin/busted -t 'e2e' /kong-plugins/spec"
	docker-compose down

dev-env: ## Creates a service (myservice) and attaches a plugin to it (header-based-rate-limiting)
	bash -c "curl -i -X POST --url http://localhost:8001/services/ --data 'name=testapi' --data 'protocol=http' --data 'host=mockbin' --data 'path=/request' --data 'port=8080'"
	bash -c "curl -i -X POST --url http://localhost:8001/services/testapi/routes/ --data 'paths[]=/'"
	bash -c "curl -i -X POST --url http://localhost:8001/services/testapi/plugins/ --data 'name=header-based-rate-limiting' --data 'config.redis.host=kong-redis' --data 'config.default_rate_limit=10' --data 'config.log_only=false' --data 'config.forward_headers_to_upstream=true' --data 'config.identification_headers=x-customer-id,x-consumer-username'"

add-plugin:
	bash -c "curl -i -X POST --url http://localhost:8001/services/testapi/plugins/ --data 'name=header-based-rate-limiting' --data 'config.redis.host=kong-redis' --data 'config.default_rate_limit=10' --data 'config.log_only=false' --data 'config.forward_headers_to_upstream=true' --data 'config.identification_headers=x-customer-id,x-consumer-username'"

ping: ## Pings kong on localhost:8000
	bash -c "curl -i http://localhost:8000"

ssh: ## Pings kong on localhost:8000
	docker-compose run --rm kong bash

redis: ## Redis
	docker-compose exec kong-redis redis-cli

db: ## Access DB
	docker-compose run --rm kong bash -c "psql -h kong-database -U kong"
