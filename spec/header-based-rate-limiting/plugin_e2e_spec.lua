local cjson = require "cjson"
local helpers = require "spec.helpers"
local pgmoon = require "pgmoon"
local KongSdk = require "spec.kong_sdk"

local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"

describe("Plugin: header-based-rate-limiting (access)", function()
    local redis = RedisFactory.create({
        host = "kong-redis",
        port = 6379,
        db = 0
    })

    setup(function()
        helpers.start_kong({ custom_plugins = 'header-based-rate-limiting' })
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    before_each(function()
        helpers.dao:truncate_tables()
        redis:flushall()
    end)

    describe("admin API", function()
        describe("/plugins/:plugin_id/redis-ping", function()
            local kong_sdk, service

            before_each(function()
                kong_sdk = KongSdk.from_admin_client()

                service = kong_sdk.services:create({
                    name = "test-service",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/test-route")
            end)

            context("when plugin does not exist", function()
                it("should respond with HTTP 404", function()
                    local response = helpers.admin_client():send({
                        method = "GET",
                        path = "/plugins/8d29de00-9fea-11e8-98d0-529269fb1459/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    assert.res_status(404, response)
                end)
            end)

            context("when the plugin is not a header-based-rate-limiting", function()
                it("should respond with HTTP 400", function()
                    local plugin = kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "key-auth"
                    })

                    local response = helpers.admin_client():send({
                        method = "GET",
                        path = "/plugins/" .. plugin.id .. "/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    local raw_body = assert.res_status(400, response)
                    local body = cjson.decode(raw_body)

                    assert.are.equal("Plugin is not of type header-based-rate-limiting", body.message)
                end)
            end)

            context("when Redis connection fails", function()
                it("should respond with HTTP 400", function()
                    local non_existent_redis = {
                        host = "some-redis-host"
                    }

                    local plugin = kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "header-based-rate-limiting",
                        config = {
                            redis = non_existent_redis,
                            default_rate_limit = 1,
                            identification_headers = { "x-custom-identifier" }
                        }
                    })

                    local response = helpers.admin_client():send({
                        method = "GET",
                        path = "/plugins/" .. plugin.id .. "/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    local raw_body = assert.res_status(400, response)
                    local body = cjson.decode(raw_body)

                    assert.are.equal("Could not connect to Redis", body.message)
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

                    local response = helpers.admin_client():send({
                        method = "GET",
                        path = "/plugins/" .. plugin.id .. "/redis-ping",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    })

                    local raw_body = assert.res_status(400, response)
                    local body = cjson.decode(raw_body)

                    assert.are.equal("Could not select Redis DB", body.message)
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

                local response = helpers.admin_client():send({
                    method = "GET",
                    path = "/plugins/" .. plugin.id .. "/redis-ping",
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local raw_body = assert.res_status(200, response)
                local body = cjson.decode(raw_body)

                assert.are.equal("PONG", body.message)
            end)
        end)

        describe("/header-based-rate-limits", function()
            describe("POST", function()
                local kong_sdk, service, route

                before_each(function()
                    kong_sdk = KongSdk.from_admin_client()

                    service = kong_sdk.services:create({
                        name = "rate-limit-test-service",
                        url = "http://mockbin:8080/request"
                    })

                    route = kong_sdk.routes:create_for_service(service.id, "/custom-rate-limit-route")
                end)

                it("should fail when the service does not exist", function()
                    kong_sdk.routes:delete(route.id)
                    kong_sdk.services:delete(service.id)

                    local response = assert(helpers.admin_client():send({
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
                    }))

                    assert.res_status(400, response)
                end)

                it("should fail when the route does not exist", function()
                    kong_sdk.routes:delete(route.id)

                    local response = assert(helpers.admin_client():send({
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
                    }))

                    assert.res_status(400, response)
                end)

                it("should store the provided settings", function()
                    local header_composition = { "test-integration", "12345678" }

                    local response = assert(helpers.admin_client():send({
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
                    }))

                    local raw_body = assert.res_status(201, response)
                    local body = cjson.decode(raw_body)

                    assert.truthy(body.id)
                    assert.are.equal(service.id, body.service_id)
                    assert.are.equal(route.id, body.route_id)
                    assert.are.same(header_composition, body.header_composition)
                end)

                it("should store the provided settings when only service is provided", function()
                    local header_composition = { "test-integration", "12345678" }

                    local response = assert(helpers.admin_client():send({
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
                    }))

                    local raw_body = assert.res_status(201, response)
                    local body = cjson.decode(raw_body)

                    assert.truthy(body.id)
                    assert.are.equal(service.id, body.service_id)
                    assert.are.same(header_composition, body.header_composition)
                end)

                it("should store the provided settings when only route is provided", function()
                    local header_composition = { "test-integration", "12345678" }

                    local response = assert(helpers.admin_client():send({
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
                    }))

                    local raw_body = assert.res_status(201, response)
                    local body = cjson.decode(raw_body)

                    assert.truthy(body.id)
                    assert.are.equal(route.id, body.route_id)
                    assert.are.same(header_composition, body.header_composition)
                end)

                it("should fail on duplicate settings", function()
                    local header_composition = { "test-integration", "12345678" }

                    local expected_status_codes = { 201, 400 }

                    for _, expected_status in ipairs(expected_status_codes) do
                        local response = assert(helpers.admin_client():send({
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
                        }))

                        assert.res_status(expected_status, response)
                    end
                end)

                it("should fail when given settings contains infix wildcard", function()
                    local header_composition = { "test-integration", "*", "12345678" }

                    local response = assert(helpers.admin_client():send({
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
                    }))

                    assert.res_status(400, response)
                end)

                it("should succeed when given settings contains prefix wildcard", function()
                    local header_composition = { "*", "*", "12345678" }

                    local response = assert(helpers.admin_client():send({
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
                    }))

                    assert.res_status(201, response)
                end)

                it("should trim postfix wildcards on the header composition", function()
                    local response = assert(helpers.admin_client():send({
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
                    }))

                    local raw_body = assert.res_status(201, response)
                    local body = cjson.decode(raw_body)

                    assert.are.same(body.header_composition, { "test-integration" })
                end)
            end)

            describe("GET", function()
                it("should return the previously created settings", function()
                    local header_composition = { "test-integration", "12345678" }

                    local creation_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/header-based-rate-limits",
                        body = {
                            header_composition = header_composition,
                            rate_limit = 10
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, creation_response)

                    local retrieval_response = assert(helpers.admin_client():send({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_body = assert.res_status(200, retrieval_response)
                    local body = cjson.decode(raw_body)

                    assert.truthy(body.data[1].id)
                    assert.are.same(header_composition, body.data[1].header_composition)
                end)

                it("should be able to return multiple settings", function()
                    for i = 1, 2 do
                        local rate_limit_response = assert(helpers.admin_client():send({
                            method = "POST",
                            path = "/header-based-rate-limits",
                            body = {
                                header_composition = { "test-integration" .. i, "12345678" },
                                rate_limit = 10
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        assert.res_status(201, rate_limit_response)
                    end

                    local retrieval_response = assert(helpers.admin_client():send({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_body = assert.res_status(200, retrieval_response)
                    local body = cjson.decode(raw_body)

                    assert.are.same(2, #body.data)
                end)

                it("should be able to return settings filtered by service", function()
                    local kong_sdk = KongSdk.from_admin_client()

                    local service = kong_sdk.services:create({
                        name = "rate-limit-test-service",
                        url = "http://mockbin:8080/request"
                    })

                    local rate_limit_services = {
                        { id = nil },
                        service
                    }

                    for i, service in ipairs(rate_limit_services) do
                        local rate_limit_response = assert(helpers.admin_client():send({
                            method = "POST",
                            path = "/header-based-rate-limits",
                            body = {
                                service_id = service.id,
                                header_composition = { "test-integration" .. i, "12345678" },
                                rate_limit = 10
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        assert.res_status(201, rate_limit_response)
                    end

                    local retrieval_response = assert(helpers.admin_client():send({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        query = { service_id = service.id },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_body = assert.res_status(200, retrieval_response)
                    local body = cjson.decode(raw_body)

                    assert.are.same(1, #body.data)
                    assert.are.same(service.id, body.data[1].service_id)
                end)
            end)

            describe("DELETE", function()

                it("should delete every rate limit settings", function()
                    local kong_sdk = KongSdk.from_admin_client()

                    local service = kong_sdk.services:create({
                        name = "rate-limit-test-service",
                        url = "http://mockbin:8080/request"
                    })

                    local rate_limit_response = assert(helpers.admin_client():send({
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
                    }))

                    assert.res_status(201, rate_limit_response)

                    local delete_response = assert(helpers.admin_client():send({
                        method = "DELETE",
                        path = "/header-based-rate-limits",
                        query = { service_id = service.id },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(200, delete_response)

                    local retrieval_response = assert(helpers.admin_client():send({
                        method = "GET",
                        path = "/header-based-rate-limits",
                        query = { service_id = service.id },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_body = assert.res_status(200, retrieval_response)
                    local body = cjson.decode(raw_body)

                    assert.are.same(0, #body.data)
                end)

            end)

        end)

        describe("/header-based-rate-limits/:id", function()
            describe("DELETE", function()
                context("when rate limit setting does not exist", function()
                    it("should respond with error", function()

                        local delete_response = assert(helpers.admin_client():send({
                            method = "DELETE",
                            path = "/header-based-rate-limits/123456789",
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        local raw_response_body = assert.res_status(404, delete_response)
                        local body = cjson.decode(raw_response_body)

                        assert.are.same('Resource does not exist', body.message)
                    end)
                end)

                context("when rate limit setting exists", function()
                    it("should delete setting", function()

                        local service_response = assert(helpers.admin_client():send({
                            method = "POST",
                            path = "/services/",
                            body = {
                                name = 'rate-limit-test-service',
                                url = 'http://mockbin:8080/request'
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        local raw_service_response_body = assert.res_status(201, service_response)
                        local service_id = cjson.decode(raw_service_response_body).id

                        local first_rate_limit_response = assert(helpers.admin_client():send({
                            method = "POST",
                            path = "/header-based-rate-limits",
                            body = {
                                service_id = service_id,
                                header_composition = { "test-integration", "87654321" },
                                rate_limit = 5
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        assert.res_status(201, first_rate_limit_response)

                        local rate_limit_response = assert(helpers.admin_client():send({
                            method = "POST",
                            path = "/header-based-rate-limits",
                            body = {
                                service_id = service_id,
                                header_composition = { "test-integration", "12345678" },
                                rate_limit = 10
                            },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        local raw_rate_limit_setting = assert.res_status(201, rate_limit_response)
                        local rate_limit_setting_id = cjson.decode(raw_rate_limit_setting).id


                        local delete_response = assert(helpers.admin_client():send({
                            method = "DELETE",
                            path = "/header-based-rate-limits/" .. rate_limit_setting_id,
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        assert.res_status(204, delete_response)

                        local retrieval_response = assert(helpers.admin_client():send({
                            method = "GET",
                            path = "/header-based-rate-limits",
                            query = { service_id = service_id },
                            headers = {
                                ["Content-Type"] = "application/json"
                            }
                        }))

                        local raw_body = assert.res_status(200, retrieval_response)
                        local body = cjson.decode(raw_body)

                        assert.are.same(1, #body.data)
                    end)
                end)
            end)
        end)

    end)

    describe("Rate limiting", function()
        context("when Redis is unreachable", function()
            it("shouldn't block the request", function()

                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'test-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/routes/",
                    body = {
                        service = {
                            id = service_id
                        },
                        paths = { '/test-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, route_response)

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "non-existing-host"
                            },
                            default_rate_limit = 1,
                            identification_headers = { "x-custom-identifier" }
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route"
                }))

                assert.res_status(200, response)
            end)
        end)

        context("when Redis is configured properly", function()
            local default_rate_limit = 3

            it("should rate limit after given amount of requests", function()
                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'test-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/routes/",
                    body = {
                        service = {
                            id = service_id
                        },
                        paths = { '/test-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, route_response)

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x-custom-identifier" }
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                for i = 1, 3 do
                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/test-route"
                    }))

                    assert.res_status(200, response)
                end

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route"
                }))

                assert.res_status(429, response)
            end)

            it("should set rate limit headers", function()
                local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", os.time() + 60)

                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'test-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/routes/",
                    body = {
                        service = {
                            id = service_id
                        },
                        paths = { '/test-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, route_response)

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x-custom-identifier" }
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                for i = 1, default_rate_limit do
                    local expected_remaining = default_rate_limit - i
                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/test-route",
                        headers = {
                            ["X-Custom-Identifier"] = "api_consumer",
                        }
                    }))

                    assert.res_status(200, response)
                    assert.are.equal(tostring(expected_remaining), response.headers['x-ratelimit-remaining'])
                    assert.are.equal(tostring(default_rate_limit), response.headers['x-ratelimit-limit'])
                    assert.are.equal(time_reset, response.headers['x-ratelimit-reset'])
                end

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["X-Custom-Identifier"] = "api_consumer",
                    }
                }))

                assert.res_status(429, response)
                assert.are.equal('0', response.headers['x-ratelimit-remaining'])
                assert.are.equal(tostring(default_rate_limit), response.headers['x-ratelimit-limit'])
                assert.are.equal(time_reset, response.headers['x-ratelimit-reset'])
            end)

            context("when there are multiple consumers", function()
                it("should track rate limit pools separately", function()

                    local service_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/",
                        body = {
                            name = 'test-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_service_response_body = assert.res_status(201, service_response)
                    local service_id = cjson.decode(raw_service_response_body).id

                    local route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/test-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, route_response)

                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = default_rate_limit,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, plugin_response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer"
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/test-route",
                        headers = {
                            ["X-Custom-Identifier"] = "api_consumer",
                        }
                    }))

                    assert.res_status(429, response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                ["X-Custom-Identifier"] = "other_api_consumer",
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/test-route",
                        headers = {
                            ["X-Custom-Identifier"] = "other_api_consumer",
                        }
                    }))

                    assert.res_status(429, response)
                end)
            end)

            context("when plugin is configured on multiple services", function()
                it("should track rate limit pools separately", function()

                    local service_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/",
                        body = {
                            name = 'test-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_service_response_body = assert.res_status(201, service_response)
                    local service_id = cjson.decode(raw_service_response_body).id

                    local route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/test-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, route_response)

                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = default_rate_limit,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, plugin_response)

                    local other_service_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/",
                        body = {
                            name = 'other-test-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local other_raw_service_response_body = assert.res_status(201, other_service_response)
                    local other_service_id = cjson.decode(other_raw_service_response_body).id

                    local other_route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = other_service_id
                            },
                            paths = { '/other-test-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, other_route_response)

                    local other_plugin_response = (helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. other_service_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = 4,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, other_plugin_response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/test-route",
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer"
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/test-route",
                        headers = {
                            ["X-Custom-Identifier"] = "api_consumer",
                        }
                    }))

                    assert.res_status(429, response)

                    for i = 1, 4 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/other-test-route",
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer",
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/other-test-route",
                        headers = {
                            ["X-Custom-Identifier"] = "api_consumer",
                        }
                    }))

                    assert.res_status(429, response)
                end)
            end)

            context("when plugin is configured on multiple routes", function()
                it("should track rate limit pools separately", function()
                    local service_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/",
                        body = {
                            name = 'common-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_service_response_body = assert.res_status(201, service_response)
                    local service_id = cjson.decode(raw_service_response_body).id

                    local first_route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/first-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_first_route_response_body = assert.res_status(201, first_route_response)
                    local first_route_id = cjson.decode(raw_first_route_response_body).id

                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/" .. first_route_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = 3,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, plugin_response)

                    local second_route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/second-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_second_route_response_body = assert.res_status(201, second_route_response)
                    local second_route_id = cjson.decode(raw_second_route_response_body).id

                    local other_plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/" .. second_route_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = 4,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, other_plugin_response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/first-route",
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer"
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/first-route",
                        headers = {
                            ["X-Custom-Identifier"] = "api_consumer",
                        }
                    }))

                    assert.res_status(429, response)

                    for i = 1, 4 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/second-route",
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer",
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/second-route",
                        headers = {
                            ["X-Custom-Identifier"] = "api_consumer",
                        }
                    }))

                    assert.res_status(429, response)
                end)
            end)

            context("when darklaunch mode is enabled", function()
                it("should let request through even after reaching the rate limit", function()
                    local service_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/",
                        body = {
                            name = 'another-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_service_response_body = assert.res_status(201, service_response)
                    local service_id = cjson.decode(raw_service_response_body).id

                    local route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/another-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, route_response)

                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = 3,
                                log_only = true,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, plugin_response)

                    for i = 1, 5 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/another-route",
                            headers = {
                                ["X-Custom-Identifier"] = "api_consumer",
                            }
                        }))

                        assert.res_status(200, response)

                        assert.are.equal(nil, response.headers['x-ratelimit-remaining'])
                        assert.are.equal(nil, response.headers['x-ratelimit-limit'])
                        assert.are.equal(nil, response.headers['x-ratelimit-reset'])
                    end
                end)
            end)

            context("when plugin is configured whith multiple identification headers", function()

                it("should track rate limit pools separately based on them",function()
                    local service_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/",
                        body = {
                            name = 'common-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_service_response_body = assert.res_status(201, service_response)
                    local service_id = cjson.decode(raw_service_response_body).id

                    local route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local route_response_body = assert.res_status(201, route_response)
                    local route_id = cjson.decode(route_response_body).id

                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/" .. route_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = 3,
                                identification_headers = { "x-customer-id", "x-kong-consumer" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, plugin_response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/route",
                            headers = {
                                ["x-customer-id"] = "api_consumer",
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/route",
                        headers = {
                            ["x-customer-id"] = "api_consumer",
                        }
                    }))

                    assert.res_status(429, response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/route",
                            headers = {
                                ["x-customer-id"] = "api_consumer",
                                ["x-kong-consumer"] = 1234
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/route",
                        headers = {
                            ["x-customer-id"] = "api_consumer",
                            ["x-kong-consumer"] = 1234
                        }
                    }))

                    assert.res_status(429, response)
                end)

            end)

            context("when the plugin is appended after an authentication plugin", function()
                it("should be able to use the headers applied by it", function()
                    local service_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/",
                        body = {
                            name = 'secure-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_service_response_body = assert.res_status(201, service_response)
                    local service_id = cjson.decode(raw_service_response_body).id

                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = 'key-auth'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, plugin_response)

                    local consumer_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/consumers",
                        body = {
                            username = 'authenticated_consumer'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_consumer_response_body = assert.res_status(201, consumer_response)
                    local consumer_id = cjson.decode(raw_consumer_response_body).id

                    local key_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/consumers/" .. consumer_id .. "/key-auth",
                        body = {},
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_key_response_body = assert.res_status(201, key_response)

                    local key = cjson.decode(raw_key_response_body).key

                    local second_consumer_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/consumers",
                        body = {
                            username = 'second_authenticated_consumer'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_second_consumer_response_body = assert.res_status(201, second_consumer_response)
                    local second_consumer_id = cjson.decode(raw_second_consumer_response_body).id

                    local second_key_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/consumers/" .. second_consumer_id .. "/key-auth",
                        body = {},
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_second_key_response_body = assert.res_status(201, second_key_response)
                    local second_key = cjson.decode(raw_second_key_response_body).key

                    local route_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/secure-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, route_response)

                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis"
                                },
                                default_rate_limit = 3,
                                identification_headers = { "x_consumer_username" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert.res_status(201, plugin_response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/secure-route",
                            headers = {
                                apikey = key
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/secure-route",
                        headers = {
                            apikey = key
                        }
                    }))

                    assert.res_status(429, response)

                    for i = 1, 3 do
                        local response = assert(helpers.proxy_client():send({
                            method = "GET",
                            path = "/secure-route",
                            headers = {
                                apikey = second_key
                            }
                        }))

                        assert.res_status(200, response)
                    end

                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = "/secure-route",
                        headers = {
                            apikey = second_key
                        }
                    }))

                    assert.res_status(429, response)
                end)
            end)
        end)

        context("when forward_headers_to_upstream is enabled", function()

            it("should append rate limit headers to the request", function()
                local default_rate_limit = 5
                local rate_limit = 4
                local expected_remaining = rate_limit - 1
                local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", os.time() + 60)
                local customer_id = 123456789

                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'test-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/routes/",
                    body = {
                        paths = { '/test-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_route_response_body = assert.res_status(201, route_response)
                local route_id = cjson.decode(raw_route_response_body).id

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        service_id = service_id,
                        route_id = route_id,
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x-customer-id" },
                            forward_headers_to_upstream = true
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                local rate_limit_response = (helpers.admin_client():send({
                    method = "POST",
                    path = "/header-based-rate-limits",
                    body = {
                        service_id = service_id,
                        route_id = route_id,
                        header_composition = { customer_id },
                        rate_limit = rate_limit
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, rate_limit_response)

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["x-customer-id"] = customer_id,
                    }
                }))

                local raw_response_body = assert.res_status(200, response)
                local response_body = cjson.decode(raw_response_body)

                assert.are.equal(tostring(expected_remaining), response_body.headers['x-ratelimit-remaining'])
                assert.are.equal(tostring(rate_limit), response_body.headers['x-ratelimit-limit'])
                assert.are.equal(time_reset, response_body.headers['x-ratelimit-reset'])
                assert.are.equal('allow', response_body.headers['x-ratelimit-decision'])
            end)

            it("should append rate limit headers to the request", function()
                local default_rate_limit = 5
                local rate_limit = 4
                local expected_remaining = rate_limit - 1
                local time_reset = os.date("!%Y-%m-%dT%H:%M:00Z", os.time() + 60)
                local customer_id = 123456789

                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'test-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/routes/",
                    body = {
                        paths = { '/test-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_route_response_body = assert.res_status(201, route_response)
                local route_id = cjson.decode(raw_route_response_body).id

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        service_id = service_id,
                        route_id = route_id,
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x-customer-id" },
                            forward_headers_to_upstream = true
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                local rate_limit_response = (helpers.admin_client():send({
                    method = "POST",
                    path = "/header-based-rate-limits",
                    body = {
                        service_id = service_id,
                        route_id = route_id,
                        header_composition = { customer_id },
                        rate_limit = rate_limit
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, rate_limit_response)

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["x-customer-id"] = customer_id,
                    }
                }))

                local raw_response_body = assert.res_status(200, response)
                local response_body = cjson.decode(raw_response_body)

                assert.are.equal(tostring(expected_remaining), response_body.headers['x-ratelimit-remaining'])
                assert.are.equal(tostring(rate_limit), response_body.headers['x-ratelimit-limit'])
                assert.are.equal(time_reset, response_body.headers['x-ratelimit-reset'])
                assert.are.equal('allow', response_body.headers['x-ratelimit-decision'])
            end)

        end)

        context("when forward_headers_to_upstream is disabled", function()

            it("should append rate limit headers to the request", function()
                local default_rate_limit = 5
                local customer_id = 123456789

                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'test-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/routes/",
                    body = {
                        service = {
                            id = service_id
                        },
                        paths = { '/test-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, route_response)

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = default_rate_limit,
                            identification_headers = { "x-customer-id" },
                            forward_headers_to_upstream = false
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["x-customer-id"] = customer_id,
                    }
                }))

                local raw_response_body = assert.res_status(200, response)
                local response_body = cjson.decode(raw_response_body)

                assert.are.equal(nil, response_body.headers['x-ratelimit-remaining'])
                assert.are.equal(nil, response_body.headers['x-ratelimit-limit'])
                assert.are.equal(nil, response_body.headers['x-ratelimit-reset'])
            end)

        end)

        it("should find an exact match among the header compositions", function()
            local test_integration = "test_integration"
            local customer_id = '123456789'

            local service_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/services/",
                body = {
                    name = 'brand-new-service',
                    url = 'http://mockbin:8080/request'
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_service_response_body = assert.res_status(201, service_response)
            local service_id = cjson.decode(raw_service_response_body).id

            local route_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/routes/",
                body = {
                    service = {
                        id = service_id
                    },
                    paths = { '/super-route' }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_route_response_body = assert.res_status(201, route_response)
            local route_id = cjson.decode(raw_route_response_body).id

            local plugin_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/plugins",
                body = {
                    name = "header-based-rate-limiting",
                    route_id =  route_id,
                    service_id = service_id,
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = 5,
                        identification_headers = { "x-integration-id", "x-customer-id" }
                    }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, plugin_response)

            local rate_limit_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    route_id = route_id,
                    header_composition = { test_integration, customer_id },
                    rate_limit = 3
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, rate_limit_response)

            local other_rate_limit_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    header_composition = { test_integration, customer_id },
                    rate_limit = 4
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, other_rate_limit_response)

            for i = 1, 3 do
                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = '/super-route',
                    headers = {
                        ["x-customer-id"] = customer_id,
                        ["x-integration-id"] = test_integration
                    }
                }))

                assert.res_status(200, response)
            end

            local response = assert(helpers.proxy_client():send({
                method = "GET",
                path = '/super-route',
                headers = {
                    ["x-customer-id"] = customer_id,
                    ["x-integration-id"] = test_integration
                }
            }))

            assert.res_status(429, response)

        end)

        it("should find an exact match with wildcard among the header compositions", function()
            local test_integration = "test_integration"
            local customer_id = '123456789'

            local service_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/services/",
                body = {
                    name = 'brand-new-service',
                    url = 'http://mockbin:8080/request'
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_service_response_body = assert.res_status(201, service_response)
            local service_id = cjson.decode(raw_service_response_body).id

            local route_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/routes/",
                body = {
                    service = {
                        id = service_id
                    },
                    paths = { '/super-route' }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_route_response_body = assert.res_status(201, route_response)
            local route_id = cjson.decode(raw_route_response_body).id

            local plugin_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/plugins",
                body = {
                    name = "header-based-rate-limiting",
                    route_id =  route_id,
                    service_id = service_id,
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = 1,
                        identification_headers = { "x-First-Header", "X-Second-Header", "X-Third-Header" }
                    }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, plugin_response)

            local rate_limit_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    route_id = route_id,
                    header_composition = { "*", "BBB", "CCC" },
                    rate_limit = 4
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, rate_limit_response)


            local rate_limit_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    route_id = route_id,
                    header_composition = { "*", "*", "CCC" },
                    rate_limit = 3
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, rate_limit_response)

            local rate_limit_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    route_id = route_id,
                    header_composition = { "AAA", "BBB" },
                    rate_limit = 2
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, rate_limit_response)

            for i = 1, 4 do
                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = '/super-route',
                    headers = {
                        ["X-First-Header"] = "AAA",
                        ["X-Second-Header"] = "BBB",
                        ["X-Third-Header"] = "CCC",
                    }
                }))

                assert.res_status(200, response)
            end

            local response = assert(helpers.proxy_client():send({
                method = "GET",
                path = '/super-route',
                headers = {
                    ["X-First-Header"] = "AAA",
                    ["X-Second-Header"] = "BBB",
                    ["X-Third-Header"] = "CCC",
                }
            }))

            assert.res_status(429, response)

        end)

        context("when plugin is configured for the service", function()
            it("should find an exact match among the header compositions", function()
                local function sleep(seconds)
                    local clock = os.clock

                    local started_at = clock()
                    while clock() - started_at <= seconds do end
                end

                local test_integration = "test_integration"
                local customer_id = '123456789'

                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'brand-new-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/routes/",
                    body = {
                        paths = { '/super-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_route_response_body = assert.res_status(201, route_response)
                local route_id = cjson.decode(raw_route_response_body).id

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        service_id = service_id,
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = 5,
                            identification_headers = { "x-integration-id", "x-customer-id" }
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                local rate_limit_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/header-based-rate-limits",
                    body = {
                        service_id = service_id,
                        header_composition = { test_integration, customer_id },
                        rate_limit = 3
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, rate_limit_response)

                for i = 1, 3 do
                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = '/super-route',
                        headers = {
                            ["x-integration-id"] = test_integration,
                            ["x-customer-id"] = customer_id
                        }
                    }))

                    assert.res_status(200, response)
                end

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = '/super-route',
                    headers = {
                        ["x-customer-id"] = customer_id,
                        ["x-integration-id"] = test_integration
                    }
                }))

                assert.res_status(429, response)
            end)
        end)

        it("should allow to set less specific rate limit setting", function()
            local test_integration = "test_integration"
            local customer_id = '123456789'

            local service_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/services/",
                body = {
                    name = 'cool-new-service',
                    url = 'http://mockbin:8080/request'
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_service_response_body = assert.res_status(201, service_response)
            local service_id = cjson.decode(raw_service_response_body).id

            local route_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/routes/",
                body = {
                    service = {
                        id = service_id
                    },
                    paths = { '/perfect-route' }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_route_response_body = assert.res_status(201, route_response)
            local route_id = cjson.decode(raw_route_response_body).id

            local rate_limit_response = (helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    route_id = route_id,
                    header_composition = { test_integration, customer_id },
                    rate_limit = 4
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, rate_limit_response)

            local less_specific_setting_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    header_composition = { test_integration, customer_id },
                    rate_limit = 3
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, less_specific_setting_response)


        end)

        it("should fallback on less specific settings based on the provided header compositions", function()
            local test_integration = "test_integration"
            local customer_id = '123456789'

            local service_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/services/",
                body = {
                    name = 'brand-new-service',
                    url = 'http://mockbin:8080/request'
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_service_response_body = assert.res_status(201, service_response)
            local service_id = cjson.decode(raw_service_response_body).id

            local route_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/routes/",
                body = {
                    service = {
                        id = service_id
                    },
                    paths = { '/super-route' }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            local raw_route_response_body = assert.res_status(201, route_response)
            local route_id = cjson.decode(raw_route_response_body).id

            local plugin_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/plugins",
                body = {
                    name = "header-based-rate-limiting",
                    route_id =  route_id,
                    service_id = service_id,
                    config = {
                        redis = {
                            host = "kong-redis"
                        },
                        default_rate_limit = 5,
                        identification_headers = { "x-integration-id", "x-customer-id" }
                    }
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, plugin_response)

            local rate_limit_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    route_id = route_id,
                    header_composition = { test_integration },
                    rate_limit = 3
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, rate_limit_response)

            local other_rate_limit_response = assert(helpers.admin_client():send({
                method = "POST",
                path = "/header-based-rate-limits",
                body = {
                    service_id = service_id,
                    header_composition = { test_integration },
                    rate_limit = 4
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            }))

            assert.res_status(201, other_rate_limit_response)

            for i = 1, 3 do
                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = '/super-route',
                    headers = {
                        ["x-customer-id"] = customer_id,
                        ["x-integration-id"] = test_integration
                    }
                }))

                assert.res_status(200, response)
            end

            local response = assert(helpers.proxy_client():send({
                method = "GET",
                path = '/super-route',
                headers = {
                    ["x-customer-id"] = customer_id,
                    ["x-integration-id"] = test_integration
                }
            }))

            assert.res_status(429, response)

        end)

        context("when DB becomes unreachable", function()
            it("should keep the configured limit in the cache", function()
                local test_integration = "test_integration"
                local customer_id = '123456789'

                local service_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/",
                    body = {
                        name = 'brand-new-service',
                        url = 'http://mockbin:8080/request'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_service_response_body = assert.res_status(201, service_response)
                local service_id = cjson.decode(raw_service_response_body).id

                local route_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/routes/",
                    body = {
                        service = {
                            id = service_id
                        },
                        paths = { '/super-route' }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_route_response_body = assert.res_status(201, route_response)
                local route_id = cjson.decode(raw_route_response_body).id

                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        route_id =  route_id,
                        service_id = service_id,
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = 5,
                            identification_headers = { "x-integration-id", "x-customer-id" }
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, plugin_response)

                local rate_limit_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/header-based-rate-limits",
                    body = {
                        service_id = service_id,
                        route_id = route_id,
                        header_composition = { test_integration, customer_id },
                        rate_limit = 4
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                assert.res_status(201, rate_limit_response)

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = '/super-route',
                    headers = {
                        ["x-customer-id"] = customer_id,
                        ["x-integration-id"] = test_integration
                    }
                }))

                assert.res_status(200, response)

                local pg = pgmoon.new({
                    host = 'kong-database',
                    port = 5432,
                    database = 'kong',
                    user = 'kong',
                    password = 'kong'
                })

                assert(pg:connect())
                assert(pg:query("TRUNCATE header_based_rate_limits"))
                assert(pg:disconnect())

                for i = 1, 3 do
                    local response = assert(helpers.proxy_client():send({
                        method = "GET",
                        path = '/super-route',
                        headers = {
                            ["x-customer-id"] = customer_id,
                            ["x-integration-id"] = test_integration
                        }
                    }))

                    assert.res_status(200, response)
                end

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = '/super-route',
                    headers = {
                        ["x-customer-id"] = customer_id,
                        ["x-integration-id"] = test_integration
                    }
                }))

                assert.res_status(429, response)

            end)
        end)

    end)
end)
