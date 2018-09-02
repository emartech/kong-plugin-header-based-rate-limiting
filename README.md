# Header based rate limiting plugin for Kong API Gateway

## Description

The plugin enables rate limiting API requests based on a customizable composition of request headers. The provided list of headers will be used to identify subjects of rate limiting, thus allowing us to define more fine-grained settings than the built-in (community edition) plugin.

## Configuration

### Enabling the plugin

**POST** http://localhost:8001/plugins

```json
{
	"name": "header-based-rate-limiting"
	"service_id": "...",
	"route_id": "...",
	"config": {
		"redis": {
			"host": "redis-host",
			"port": 6379,
			"db": 0
		},
		"default_rate_limit": 10,
		"log_only": false,
		"identification_headers": [
			"X-Country",
			"X-County",
			"X-City",
			"X-Street",
			"X-House"
		]
	}
}
```

| Attributes | Default | Description |
|-|-|-|
| redis.host | | address of the Redis server |
| redis.port | 6379 | port of the Redis server |
| redis.db | 0 | number of the Redis database |
| default_rate_limit | | will be applied if a more specific rule couldn't be found for the given request |
| log_only | false | requests won't be terminated when rate limit exceeded |
| identification_headers | | this (ordered) list of headers will be used to identify the subjects of rate limiting |

### Adding rate limit rules

**POST** http://localhost:8001/header-based-rate-limits

```json
{
    "service_id": "...",
    "route_id": "...",
    "header_composition": [
        "Hungary",
        "Pest",
        "Budapest",
        "Kossuth Lajos",
        "7"
    ],
    "rate_limit": 25
}
```

## Header composition

Subjects of rate limiting are idenfified by a configurable composition of request headers. You may think of this as the address on a mail sent through postal services. The addressee is designated by components of its address, and each of these components make the identification a bit more specific (Country > County > City > Street > House).

### Lookup procedure

The plugin tries to identify the addressee of each request and determine the most specific rate limit config applicable.
It first tries to find a rule matching the values of the identification headers. If there was no exact match, it discards the most specific element (the last one) and retries the lookup. We do this until a match is found, or there are no more elements to discard (in this case, the dafault value will be applied).

#### Example

Identification headers:
| Order | Header |
| - | - |
| 1 | X-Country |
| 2 | X-County |
| 3 | X-City |
| 4 | X-Street |
| 5 | X-House |

Request headers:
| Header | Value |
| - | - |
| X-Country | Hungary |
| X-County | Pest |
| X-City | Budapest |
| X-Street| Kossuth Lajos |
| X-House | 7 |

Lookup order:

| Order | Header composition |
| - | - |
| 1 | Hungary, Pest, Budapest, Kossuth Lajos, 7 |
| 2 | Hungary, Pest, Budapest, Kossuth Lajos |
| 3 | Hungary, Pest, Budapest |
| 4 | Hungary, Pest |
| 5 | Hungary |
| 6 | default rate limit |

## Development environment

### Checkout the Git repository
`git clone git@github.com:emartech/kong-plugin-header-based-rate-limiting.git`

### Build / re-build development Docker image
`make build`

### Start / stop / restart Kong

`make up` / `make down` / `make restart`

### Setup necessary services, routes and consumers for hands-on testing

`make dev-env`

### PostgreSQL shell

`make db`

### Open shell inside Kong container

`make ssh`

### Run tests

`make test`

#### Execute just the unit test:

`make unit`

#### Execute end-to-end tests:

`make e2e`

## Publish new release

- set LUAROCKS_API_KEY environment variable
    - retrieve your API key from [LuaRocks](https://luarocks.org/settings/api-keys)
    - `echo "export LUAROCKS_API_KEY=<my LuaRocks API key>" >> ~/.bash_profile`
- set version number
    - rename *.rockspec file
    - change the *version* and *source.tag* in rockspec file
    - commit and push changes
        - `git commit -m "Bump version"`
        - `git push`
    - tag the current revision
        - `git tag x.y.z`
        - `git push --tags`
- publish to LuaRocks
    - `make publish`
