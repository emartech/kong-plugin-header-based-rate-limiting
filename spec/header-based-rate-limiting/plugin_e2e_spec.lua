local cjson_safe = require "cjson.safe"
local helpers = require "spec.helpers"
local pgmoon = require "pgmoon"
local KongSdk = require "spec.kong_sdk"

local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"

local function create_request_sender(http_client)
    return function(request)
        local response = assert(http_client:send(request))

        local raw_body = assert(response:read_body())

        local parsed_body = cjson_safe.decode(raw_body)

        return {
            body = parsed_body or raw_body,
            headers = response.headers,
            status = response.status
        }
    end
end

describe("Plugin: header-based-rate-limiting (access)", function()
    local redis = RedisFactory.create({
        host = "kong-redis",
        port = 6379,
        db = 0
    })

    local default_rate_limit = 3

    local kong_sdk, send_request, send_admin_request

    setup(function()
        helpers.start_kong({ plugins = "bundled,header-based-rate-limiting" })

        kong_sdk = KongSdk.from_admin_client()

        send_request = create_request_sender(helpers.proxy_client())

        send_admin_request = create_request_sender(helpers.admin_client())
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    before_each(function()
        helpers.db:truncate()
        for _, dao in pairs(helpers.db.daos) do
            dao:truncate()
        end
        redis:flushall()
    end)

    describe("admin API", function()

        describe("/plugins/:plugin_id/redis-ping", function()

            local service

            before_each(function()
                service = kong_sdk.services:create({
                    name = "test-service",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/test-route")
            end)

            context("when plugin does not exist", function()
                it("should respond with HTTP 404", function()
                    local response = send_admin_request({
                        method = "GET",
                        path = "/plugins/8d29de00-9fea-11e8-98d0-529269fb1459/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(404, response.status)
                end)
            end)

            context("when the plugin is not a header-based-rate-limiting", function()
                it("should respond with HTTP 400", function()
                    local plugin = kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "key-auth"
                    })

                    local response = send_admin_request({
                        method = "GET",
                        path = "/plugins/" .. plugin.id .. "/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(400, response.status)
                    assert.are.equal("Plugin is not of type header-based-rate-limiting", response.body.message)
                end)
            end)

            context("when Redis connection fails", function()
                it("should respond with HTTP 400", function()
                    local plugin = kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "non-existent-host"
                            },
                            default_rate_limit = 1,
                            identification_headers = { "x-custom-identifier" }
                        }
                    })

                    local response = send_admin_request({
                        method = "GET",
                        path = "/plugins/" .. plugin.id .. "/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(400, response.status)
                    assert.are.equal("Could not connect to Redis", response.body.message)
                end)
            end)

            context("when selecting the DB fails", function()
                it("should respond with HTTP 400", function()
                    local non_existent_db = {
                        host = "kong-redis",
                        db = 128
                    }

                    local plugin = kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "header-based-rate-limiting",
                        config = {
                            redis = non_existent_db,
                            default_rate_limit = 1,
                            identification_headers = { "x-custom-identifier" }
                        }
                    })

                    local response = send_admin_request({
                        method = "GET",
                        path = "/plugins/" .. plugin.id .. "/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(400, response.status)
                    assert.are.equal("Could not select Redis DB", response.body.message)
                end)
            end)

            it("should respond with HTTP 200", function()
                local plugin = kong_sdk.plugins:create({
                    service_id = service.id,
                    name = "header-based-rate-limiting",
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = 1,
                        identification_headers = { "x-custom-identifier" }
                    }
                })

                local response = send_admin_request({
                    method = "GET",
                    path = "/plugins/" .. plugin.id .. "/redis-ping",
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(200, response.status)
                assert.are.equal("PONG", response.body.message)
            end)

        end)

        describe("/header-based-rate-limits", function()

            describe("POST", function()
                local service, route

                before_each(function()
                    service = kong_sdk.services:create({
                        name = "rate-limit-test-service",
                        url = "http://mockbin:8080/request"
                    })

                    route = kong_sdk.routes:create_for_service(service.id, "/custom-rate-limit-route")
                end)

                it("should fail when the service does not exist", function()
                    kong_sdk.routes:delete(route.id)
                    kong_sdk.services:delete(service.id)

                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            service_id = service.id,
                            header_composition = {},
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(400, response.status)
                end)

                it("should fail when the route does not exist", function()
                    kong_sdk.routes:delete(route.id)

                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            route_id = route.id,
                            header_composition = {},
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(400, response.status)
                end)

                it("should store the provided settings", function()
                    local header_composition = { "test-integration", "12345678" }

                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            service_id = service.id,
                            route_id = route.id,
                            header_composition = header_composition,
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, response.status)
                    assert.are.equal(service.id, response.body.service_id)
                    assert.are.equal(route.id, response.body.route_id)
                    assert.are.same(header_composition, response.body.header_composition)
                end)

                it("should store the provided settings when only service is provided", function()
                    local header_composition = { "test-integration", "12345678" }

                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            service_id = service.id,
                            header_composition = header_composition,
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, response.status)
                    assert.are.equal(service.id, response.body.service_id)
                    assert.are.same(header_composition, response.body.header_composition)
                end)

                it("should store the provided settings when only route is provided", function()
                    local header_composition = { "test-integration", "12345678" }

                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            route_id = route.id,
                            header_composition = header_composition,
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, response.status)
                    assert.are.equal(route.id, response.body.route_id)
                    assert.are.same(header_composition, response.body.header_composition)
                end)

                it("should fail on duplicate settings", function()
                    local header_composition = { "test-integration", "12345678" }

                    local expected_status_codes = { 201, 400 }

                    for _, expected_status in ipairs(expected_status_codes) do
                        local response = send_admin_request({
                            method = "POST",
                            path = "/header-based-rate-limits",
                            body = {
                                service_id = service.id,
                                route_id = route.id,
                                header_composition = header_composition,
                                rate_limit = 10
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        })

                        assert.are.equal(expected_status, response.status)
                    end
                end)

                it("should fail when given settings contains infix wildcard", function()
                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            service_id = service.id,
                            route_id = route.id,
                            header_composition = { "test-integration", "*", "12345678" },
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(400, response.status)
                end)

                it("should succeed when given settings contains prefix wildcard", function()
                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            service_id = service.id,
                            route_id = route.id,
                            header_composition = { "*", "*", "12345678" },
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, response.status)
                end)

                it("should trim postfix wildcards on the header composition", function()
                    local response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            service_id = service.id,
                            header_composition = { "test-integration", "*", "*" },
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, response.status)
                    assert.are.same(response.body.header_composition, { "test-integration" })
                end)
            end)

            describe("GET", function()
                it("should return the previously created settings", function()
                    local header_composition = { "test-integration", "12345678" }

                    local creation_response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            header_composition = header_composition,
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, creation_response.status)

                    local retrieval_response = send_admin_request({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(200, retrieval_response.status)

                    local first_rule = retrieval_response.body.data[1]

                    assert.truthy(first_rule.id)
                    assert.are.same(header_composition, first_rule.header_composition)
                end)

                it("should be able to return multiple settings", function()
                    for i = 1, 2 do
                        local response = send_admin_request({
                            method = "POST",
                            path = "/header-based-rate-limits",
                            body = {
                                header_composition = { "test-integration" .. i, "12345678" },
                                rate_limit = 10
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        })

                        assert.are.equal(201, response.status)
                    end

                    local retrieval_response = send_admin_request({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(200, retrieval_response.status)
                    assert.are.equal(2, #retrieval_response.body.data)
                end)

                it("should be able to return settings filtered by service", function()
                    local service = kong_sdk.services:create({
                        name = "other-test-service",
                        url = "http://mockbin:8080/request"
                    })

                    local rate_limit_services = {
                        { id = nil },
                        service
                    }

                    for i, my_service in ipairs(rate_limit_services) do
                        local response = send_admin_request({
                            method = "POST",
                            path = "/header-based-rate-limits",
                            body = {
                                service_id = my_service.id,
                                header_composition = { "test-integration" .. i, "12345678" },
                                rate_limit = 10
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        })

                        assert.are.equal(201, response.status)
                    end

                    local retrieval_response = assert(send_admin_request({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        query = { service_id = service.id },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.are.equal(200, retrieval_response.status)

                    local rules = retrieval_response.body.data

                    assert.are.equal(1, #rules)
                    assert.are.equal(service.id, rules[1].service_id)
                end)
            end)

            describe("DELETE", function()

                it("should delete every rate limit settings", function()
                    local service = kong_sdk.services:create({
                        name = "rate-limit-test-service",
                        url = "http://mockbin:8080/request"
                    })

                    local rate_limit_response = send_admin_request({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            service_id = service.id,
                            header_composition = { "test-integration", "12345678" },
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, rate_limit_response.status)

                    local delete_response = send_admin_request({
                        method = "DELETE",
                        path = "/header-based-rate-limits",
                        query = { service_id = service.id },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(200, delete_response.status)

                    local retrieval_response = send_admin_request({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        query = { service_id = service.id },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(200, retrieval_response.status)
                    assert.are.equal(0, #retrieval_response.body.data)
                end)

            end)

        end)

        describe("/header-based-rate-limits/:id", function()

            describe("DELETE", function()

                context("when rate limit setting does not exist", function()
                    it("should respond with error", function()
                        local response = send_admin_request({
                            method = "DELETE",
                            path = "/header-based-rate-limits/123456789",
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        })

                        assert.are.equal(404, response.status)
                        assert.are.equal("Resource does not exist", response.body.message)
                    end)
                end)

                context("when rate limit setting exists", function()
                    it("should delete setting", function()
                        local service = kong_sdk.services:create({
                            name = "rate-limit-test-service",
                            url = "http://mockbin:8080/request"
                        })

                        local rate_limits = {}

                        for i = 1, 2 do
                            local response = send_admin_request({
                                method = "POST",
                                path = "/header-based-rate-limits",
                                body = {
                                    service_id = service.id,
                                    header_composition = { "test-integration", "12345678" .. i },
                                    rate_limit = 10
                                },
                                headers = {
                                    ["Content-Type"] = "application/json"
                                }
                            })

                            assert.are.equal(201, response.status)

                            table.insert(rate_limits, response.body)
                        end

                        local delete_response = send_admin_request({
                            method = "DELETE",
                            path = "/header-based-rate-limits/" .. rate_limits[1].id,
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        })

                        assert.are.equal(204, delete_response.status)

                        local retrieval_response = send_admin_request({
                            method = "GET",
                            path = "/header-based-rate-limits",
                            query = { service_id = service.id },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        })

                        assert.are.equal(200, retrieval_response.status)
                        assert.are.equal(1, #retrieval_response.body.data)
                    end)
                end)

            end)

        end)

    end)

    describe("Rate limiting", function()

        local function add_rate_limit_rule(config)
            local response = send_admin_request({
                method = "POST",
                path = "/header-based-rate-limits",
                body = config,
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            assert.are.equal(201, response.status)
        end

        local service, route

        before_each(function()
            service = kong_sdk.services:create({
                name = "test-service",
                url = "http://mockbin:8080/request"
            })

            route = kong_sdk.routes:create_for_service(service.id, "/test-route")
        end)

        context("when Redis is unreachable", function()
            it("should not block the request", function()
                local non_existent_redis = {
                    host = "non-existing-host"
                }

                kong_sdk.services:add_plugin(service.id, {
                    name = "header-based-rate-limiting",
                    config = {
                        redis = non_existent_redis,
                        default_rate_limit = 1,
                        identification_headers = { "x-custom-identifier" }
                    }
                })

                local response = send_request({
                    method = "GET",
                    path = "/test-route"
                })

                assert.are.equal(200, response.status)
            end)
        end)

        context("when Redis is configured properly", function()
            it("should rate limit after given amount of requests", function()
                kong_sdk.services:add_plugin(service.id, {
                    name = "header-based-rate-limiting",
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = default_rate_limit,
                        identification_headers = { "x-custom-identifier" }
                    }
                })

                for _ = 1, default_rate_limit do
                    local response = send_request({
                        method = "GET",
                        path = "/test-route"
                    })

                    assert.are.equal(200, response.status)
                end

                local response = send_request({
                    method = "GET",
                    path = "/test-route"
                })

                assert.are.equal(429, response.status)
            end)

            it("should set rate limit headers", function()
                local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", os.time() + 60)

                kong_sdk.services:add_plugin(service.id, {
                    name = "header-based-rate-limiting",
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = default_rate_limit,
                        identification_headers = { "x-custom-identifier" }
                    }
                })

                for i = 1, default_rate_limit do
                    local expected_remaining = default_rate_limit - i

                    local response = send_request({
                        method = "GET",
                        path = "/test-route",
                        headers = {
                            ["X-Custom-Identifier"] = "api_consumer",
                        }
                    })

                    assert.are.equal(200, response.status)
                    assert.are.equal(tostring(expected_remaining), response.headers["x-ratelimit-remaining"])
                    assert.are.equal(tostring(default_rate_limit), response.headers["x-ratelimit-limit"])
                    assert.are.equal(time_reset, response.headers["x-ratelimit-reset"])
                end

                local response = send_request({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["X-Custom-Identifier"] = "api_consumer",
                    }
                })

                assert.are.equal(429, response.status)
                assert.are.equal("0", response.headers["x-ratelimit-remaining"])
                assert.are.equal(tostring(default_rate_limit), response.headers["x-ratelimit-limit"])
                assert.are.equal(time_reset, response.headers["x-ratelimit-reset"])
            end)

            context("when there are multiple consumers", function()
                it("should track rate limit pools separately", function()
                    kong_sdk.services:add_plugin(service.id, {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x-custom-identifier" }
                        }
                    })

                    local consumers = { "api_consumer", "other_api_consumer" }

                    for _, consumer in ipairs(consumers) do
                        for _ = 1, default_rate_limit do
                            local response = send_request({
                                method = "GET",
                                path = "/test-route",
                                headers = {
                                    ["X-Custom-Identifier"] = consumer
                                }
                            })

                            assert.are.equal(200, response.status)
                        end

                        local response = send_request({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                ["X-Custom-Identifier"] = consumer,
                            }
                        })

                        assert.are.equal(429, response.status)
                    end
                end)
            end)

            context("when plugin is configured on multiple services", function()
                it("should track rate limit pools separately", function()
                    local other_service = kong_sdk.services:create({
                        name = "other-test-service",
                        url = "http://mockbin:8080/request"
                    })

                    local other_route = kong_sdk.routes:create_for_service(other_service.id, "/other-test-route")

                    local services = {
                        {
                            service_id = service.id,
                            route_path = route.paths[1],
                            rate_limit = 3
                        },
                        {
                            service_id = other_service.id,
                            route_path = other_route.paths[1],
                            rate_limit = 4
                        }
                    }

                    for _, config in ipairs(services) do
                        kong_sdk.services:add_plugin(config.service_id, {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = config.rate_limit,
                                identification_headers = { "x-custom-identifier" }
                            }
                        })
                    end

                    local function make_request(route_path)
                        local response = send_request({
                            method = "GET",
                            path = route_path,
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer"
                            }
                        })

                        return response
                    end

                    for _, config in ipairs(services) do
                        for _ = 1, config.rate_limit do
                            assert.are.equal(200, make_request(config.route_path).status)
                        end

                        assert.are.equal(429, make_request(config.route_path).status)
                    end
                end)
            end)

            context("when plugin is configured on multiple routes", function()
                it("should track rate limit pools separately", function()
                    local other_route = kong_sdk.routes:create_for_service(service.id, "/other-test-route")

                    local services = {
                        {
                            route_id = route.id,
                            route_path = route.paths[1],
                            rate_limit = 3
                        },
                        {
                            route_id = other_route.id,
                            route_path = other_route.paths[1],
                            rate_limit = 4
                        }
                    }

                    for _, config in ipairs(services) do
                        kong_sdk.routes:add_plugin(config.route_id, {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = config.rate_limit,
                                identification_headers = { "x-custom-identifier" }
                            }
                        })
                    end

                    local function make_request(route_path)
                        local response = send_request({
                            method = "GET",
                            path = route_path,
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer"
                            }
                        })

                        return response
                    end

                    for _, config in ipairs(services) do
                        for _ = 1, config.rate_limit do
                            assert.are.equal(200, make_request(config.route_path).status)
                        end

                        assert.are.equal(429, make_request(config.route_path).status)
                    end
                end)
            end)

            context("when darklaunch mode is enabled", function()
                it("should let request through even after reaching the rate limit", function()
                    kong_sdk.services:add_plugin(service.id, {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            log_only = true,
                            identification_headers = { "x-custom-identifier" }
                        }
                    })

                    for _ = 1, default_rate_limit + 2 do
                        local response = send_request({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer",
                            }
                        })

                        assert.are.equal(200, response.status)

                        assert.are.equal(nil, response.headers["x-ratelimit-remaining"])
                        assert.are.equal(nil, response.headers["x-ratelimit-limit"])
                        assert.are.equal(nil, response.headers["x-ratelimit-reset"])
                    end
                end)
            end)

            context("when plugin is configured with multiple identification headers", function()
                it("should track rate limit pools separately",function()
                    kong_sdk.services:add_plugin(service.id, {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x-customer-id", "x-kong-consumer" }
                        }
                    })

                    local function send_one_header()
                        local response = send_request({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                ["x-customer-id"] = "api_consumer"
                            }
                        })

                        return response
                    end

                    local function send_both_headers()
                        local response = send_request({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                ["x-customer-id"] = "api_consumer",
                                ["x-kong-consumer"] = 1234
                            }
                        })

                        return response
                    end

                    for _ = 1, default_rate_limit do
                        assert.are.equal(200, send_one_header().status)
                    end

                    assert.are.equal(429, send_one_header().status)

                    for _ = 1, default_rate_limit do
                        assert.are.equal(200, send_both_headers().status)
                    end

                    assert.are.equal(429, send_both_headers().status)
                end)
            end)

            context("when the plugin is appended after an authentication plugin", function()
                it("should be able to use the headers applied by it", function()
                    kong_sdk.services:add_plugin(service.id, {
                        name = "key-auth"
                    })

                    kong_sdk.services:add_plugin(service.id, {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x_consumer_username" }
                        }
                    })

                    local consumer = kong_sdk.consumers:create({
                        username = "test-consumer"
                    })

                    local key_response = send_admin_request({
                        method = "POST",
                        path = "/consumers/" .. consumer.id .. "/key-auth",
                        body = {},
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.are.equal(201, key_response.status)

                    local function send_key_auth_request(api_key)
                        local response = send_request({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                apikey = api_key
                            }
                        })

                        return response
                    end

                    local api_key = key_response.body.key

                    for _ = 1, default_rate_limit do
                        assert.are.equal(200, send_key_auth_request(api_key).status)
                    end

                    assert.are.equal(429, send_key_auth_request(api_key).status)
                end)
            end)
        end)

        context("when forward_headers_to_upstream is enabled", function()
            it("should append rate limit headers to the request", function()
                local rate_limit = 4
                local expected_remaining = rate_limit - 1
                local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", os.time() + 60)
                local customer_id = 123456789

                kong_sdk.plugins:create({
                    service_id = service.id,
                    route_id = route.id,
                    name = "header-based-rate-limiting",
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = default_rate_limit,
                        identification_headers = { "x-customer-id" },
                        forward_headers_to_upstream = true
                    }
                })

                add_rate_limit_rule({
                    service_id = service.id,
                    route_id = route.id,
                    header_composition = { customer_id },
                    rate_limit = rate_limit
                })

                local response = send_request({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["x-customer-id"] = customer_id,
                    }
                })

                assert.are.equal(200, response.status)

                local body_headers = response.body.headers

                assert.are.equal(tostring(expected_remaining), body_headers["x-ratelimit-remaining"])
                assert.are.equal(tostring(rate_limit), body_headers["x-ratelimit-limit"])
                assert.are.equal(time_reset, body_headers["x-ratelimit-reset"])
                assert.are.equal("allow", body_headers["x-ratelimit-decision"])
            end)
        end)

        context("when forward_headers_to_upstream is disabled", function()
            it("should not append rate limit headers to the request", function()
                local customer_id = 123456789

                kong_sdk.services:add_plugin(service.id, {
                    name = "header-based-rate-limiting",
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = default_rate_limit,
                        identification_headers = { "x-customer-id" },
                        forward_headers_to_upstream = false
                    }
                })

                local response = send_request({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["x-customer-id"] = customer_id,
                    }
                })

                assert.are.equal(200, response.status)

                local body_headers = response.body.headers

                assert.are.equal(nil, body_headers["x-ratelimit-remaining"])
                assert.are.equal(nil, body_headers["x-ratelimit-limit"])
                assert.are.equal(nil, body_headers["x-ratelimit-reset"])
                assert.are.equal(nil, body_headers["x-ratelimit-decision"])
            end)
        end)

        it("should find an exact match among the header compositions", function()
            local test_integration = "test_integration"
            local customer_id = "123456789"

            kong_sdk.plugins:create({
                service_id = service.id,
                route_id = route.id,
                name = "header-based-rate-limiting",
                config = {
                    redis = {
                        host = "kong-redis"
                    },
                    default_rate_limit = 5,
                    identification_headers = { "x-integration-id", "x-customer-id" }
                }
            })

            local more_specific_rule = {
                service_id = service.id,
                route_id = route.id,
                header_composition = { test_integration, customer_id },
                rate_limit = 3
            }

            local less_specific_rule = {
                service_id = service.id,
                header_composition = { test_integration, customer_id },
                rate_limit = 4
            }

            add_rate_limit_rule(more_specific_rule)
            add_rate_limit_rule(less_specific_rule)

            local function send_both_headers()
                local response = send_request({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["x-customer-id"] = customer_id,
                        ["x-integration-id"] = test_integration
                    }
                })

                return response
            end

            for _ = 1, more_specific_rule.rate_limit do
                assert.are.equal(200, send_both_headers().status)
            end

            assert.are.equal(429, send_both_headers().status)
        end)

        local function make_request_with_headers(headers)
            local response = send_request({
                method = "GET",
                path = "/test-route",
                headers = headers
            })

            return response
        end

        it("should find an exact match with wildcard among the header compositions", function()
            kong_sdk.plugins:create({
                service_id = service.id,
                route_id = route.id,
                name = "header-based-rate-limiting",
                config = {
                    redis = {
                        host = "kong-redis"
                    },
                    default_rate_limit = 1,
                    identification_headers = { "x-First-Header", "X-Second-Header", "X-Third-Header" }
                }
            })

            add_rate_limit_rule({
                service_id = service.id,
                route_id = route.id,
                header_composition = { "*", "BBB", "CCC" },
                rate_limit = 4
            })
            add_rate_limit_rule({
                service_id = service.id,
                route_id = route.id,
                header_composition = { "*", "*", "CCC" },
                rate_limit = 3
            })
            add_rate_limit_rule({
                service_id = service.id,
                route_id = route.id,
                header_composition = { "AAA", "BBB" },
                rate_limit = 2
            })

            for _ = 1, 4 do
                assert.are.equal(200, make_request_with_headers({
                    ["X-First-Header"] = "AAA",
                    ["X-Second-Header"] = "BBB",
                    ["X-Third-Header"] = "CCC"
                }).status)
            end

            assert.are.equal(429, make_request_with_headers({
                ["X-First-Header"] = "AAA",
                ["X-Second-Header"] = "BBB",
                ["X-Third-Header"] = "CCC"
            }).status)
        end)

        context("when plugin is configured for the service", function()
            it("should find an exact match among the header compositions", function()
                kong_sdk.services:add_plugin(service.id, {
                    name = "header-based-rate-limiting",
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = 5,
                        identification_headers = { "x-integration-id", "x-customer-id" }
                    }
                })

                local test_integration = "test_integration"
                local customer_id = "123456789"

                add_rate_limit_rule({
                    service_id = service.id,
                    header_composition = { test_integration, customer_id },
                    rate_limit = 3
                })

                for _ = 1, 3 do
                    assert.are.equal(200, make_request_with_headers({
                        ["x-integration-id"] = test_integration,
                        ["x-customer-id"] = customer_id
                    }).status)
                end

                assert.are.equal(429, make_request_with_headers({
                    ["x-integration-id"] = test_integration,
                    ["x-customer-id"] = customer_id
                }).status)
            end)
        end)

        it("should allow to set less specific rate limit setting", function()
            local test_integration = "test_integration"
            local customer_id = "123456789"

            add_rate_limit_rule({
                service_id = service.id,
                route_id = route.id,
                header_composition = { test_integration, customer_id },
                rate_limit = 4
            })
            add_rate_limit_rule({
                service_id = service.id,
                header_composition = { test_integration, customer_id },
                rate_limit = 3
            })
        end)

        it("should fallback on less specific settings based on the provided header compositions", function()
            local test_integration = "test_integration"
            local customer_id = "123456789"

            kong_sdk.plugins:create({
                service_id = service.id,
                route_id = route.id,
                name = "header-based-rate-limiting",
                config = {
                    redis = {
                        host = "kong-redis"
                    },
                    default_rate_limit = 5,
                    identification_headers = { "x-integration-id", "x-customer-id" }
                }
            })

            add_rate_limit_rule({
                service_id = service.id,
                route_id = route.id,
                header_composition = { test_integration },
                rate_limit = 3
            })
            add_rate_limit_rule({
                service_id = service.id,
                header_composition = { test_integration },
                rate_limit = 4
            })

            for _ = 1, 3 do
                assert.are.equal(200, make_request_with_headers({
                    ["x-customer-id"] = customer_id,
                    ["x-integration-id"] = test_integration
                }).status)
            end

            assert.are.equal(429, make_request_with_headers({
                ["x-customer-id"] = customer_id,
                ["x-integration-id"] = test_integration
            }).status)
        end)

        local function wipe_rate_limit_rules()
            local pg = pgmoon.new({
                host = "kong-database",
                port = 5432,
                database = "kong",
                user = "kong",
                password = "kong"
            })

            assert(pg:connect())
            assert(pg:query("TRUNCATE header_based_rate_limits"))
            assert(pg:disconnect())
        end

        context("when DB becomes unreachable", function()
            it("should keep the configured limit in the cache", function()
                local test_integration = "test_integration"
                local customer_id = "123456789"

                kong_sdk.plugins:create({
                    service_id = service.id,
                    route_id = route.id,
                    name = "header-based-rate-limiting",
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = 5,
                        identification_headers = { "x-integration-id", "x-customer-id" }
                    }
                })

                add_rate_limit_rule({
                    service_id = service.id,
                    route_id = route.id,
                    header_composition = { test_integration, customer_id },
                    rate_limit = 4
                })

                assert.are.equal(200, make_request_with_headers({
                    ["x-customer-id"] = customer_id,
                    ["x-integration-id"] = test_integration
                }).status)

                wipe_rate_limit_rules()

                for _ = 1, 3 do
                    assert.are.equal(200, make_request_with_headers({
                        ["x-customer-id"] = customer_id,
                        ["x-integration-id"] = test_integration
                    }).status)
                end

                assert.are.equal(429, make_request_with_headers({
                    ["x-customer-id"] = customer_id,
                    ["x-integration-id"] = test_integration
                }).status)
            end)
        end)

    end)
end)
