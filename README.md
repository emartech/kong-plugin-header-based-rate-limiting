# Header-based rate limiting plugin for Kong API Gateway

## Description

The plugin enables rate limiting of API requests based on a customizable composition of request headers. The targets of rate limiting are identified using the provided list of headers, supporting more fine-grained settings than the built-in (community edition) plugin.

## Configuration

### Enabling the plugin

**POST** http://localhost:8001/plugins

```json
{
	"name": "header-based-rate-limiting",
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

| Attribute | Default | Description |
|-|-|-|
| redis.host | | Address of the Redis server |
| redis.port | 6379 | Port of the Redis server |
| redis.db | 0 | Number of the Redis database |
| default_rate_limit | | Applied if a more specific rule cannot be found for the given request |
| log_only | false | Requests are not terminated when the rate limit is exceeded |
| identification_headers | | Ordered list of headers that identifies the targets of rate limiting |

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

| Attribute | Description | |
| - | - | - |
| service_id | ID of the service to which the plugin is bound | Optional |
| route_id | ID of the route to which the plugin is bound | Optional |
| header_composition | Values for matching the rule of the request identification headers | |
| rate_limit | Rate limit pool size to be applied | |

> Although the `service_id` and `route_id` attributes are optional, if they are provided, the related service and route objects must be present in Kong's data store.

> There may be only one rule configured for a `service_id`, `route_id`, and `header_composition` combination.

> Rules are bound to the service and/or route object to which the plugin is attached. This enables separate rate limit settings for the same entity (designated by the identification headers) on different routes and/or services.

## Header composition

Targets of rate limiting are identified by a configurable composition of request headers. You may think of this as the address of a mail sent through postal services. The addressee is designated by the components of its address, ordered by specificity (Country > County > City > Street > House).

### Lookup procedure

The plugin attempts to identify the addressee of each request by determining the most specific rate limit configuration applicable. It first looks for a rule that matches the values of the identification headers. In case no exact match was found, it looks for a rule with the longest possible suffix match. If nothing was found, it discards the most specific element (the last one), and retries the lookup. This process is repeated until a match is found. If matching is unsuccessful and all elements were discarded, the plugin applies the default rate limit value.

> As a rule of thumb, a longer rule is considered more specific than a shorter one. If two rules are equally long, then the one with less wildcards is considered to me more specific. (e.g.: *, *, X, Y is more specific than *, *, X and *, *, X, Y is more specific than *, *, *, Y)

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

| Order | X-Country | X-County | X-City | X-Street | X-House |
| - | - | - | - | - | - |
| 1 | Hungary | Pest | Budapest | Kossuth Lajos | 7 |
| 2 | * | Pest | Budapest | Kossuth Lajos | 7 |
| 3 | * | * | Budapest | Kossuth Lajos | 7 |
| 4 | * | * | * | Kossuth Lajos | 7 |
| 5 | * | * | * | * | 7 |
| 6 | Hungary | Pest | Budapest | Kossuth Lajos | |
| 7 | * | Pest | Budapest | Kossuth Lajos | |
| 8 | * | * | Budapest | Kossuth Lajos | |
| 9 | * | * | * | Kossuth Lajos | |
| 10 | Hungary | Pest | Budapest | | |
| 11 | * | Pest | Budapest | | |
| 12 | * | * | Budapest | | |
| 13 | Hungary | Pest | | | |
| 14 | * | Pest | | | |
| 15 | Hungary | | | | |

If no match was found (using the matchers above), the default pool size will be used.

## Development environment

### Checkout the Git repository
`git clone git@github.com:emartech/kong-plugin-header-based-rate-limiting.git`

### Build / re-build development Docker image
`make build`

### Start / stop / restart Kong

`make up` / `make down` / `make restart`

### Set up necessary services, routes, and consumers for manual testing

`make dev-env`

### PostgreSQL shell

`make db`

### Open shell inside Kong container

`make ssh`

### Run tests

`make test`

#### Execute just the unit test

`make unit`

#### Execute end-to-end tests

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
