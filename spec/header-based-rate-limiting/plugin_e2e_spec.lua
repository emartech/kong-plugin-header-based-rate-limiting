local cjson = require "cjson"
local helpers = require "spec.helpers"

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

    local service_id, route_id

    before_each(function()
        helpers.dao:truncate_tables()

        redis:flushall()

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

        local raw_service_response_body = service_response:read_body()

        service_id = cjson.decode(raw_service_response_body).id

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

        local raw_route_response_body = route_response:read_body()

        route_id = cjson.decode(raw_route_response_body).id
    end)

    describe("admin API", function()
        describe("/plugins/:plugin_id/redis-ping", function()

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
                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "key-auth"
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_plugin_response_body = plugin_response:read_body()
                    local plugin_id = cjson.decode(raw_plugin_response_body).id

                    local response = helpers.admin_client():send({
                        method = "GET",
                        path = "/plugins/" .. plugin_id .. "/redis-ping",
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
                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "some-redis-host"
                                },
                                default_rate_limit = 1,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_plugin_response_body = plugin_response:read_body()
                    local plugin_id = cjson.decode(raw_plugin_response_body).id

                    local response = helpers.admin_client():send({
                        method = "GET",
                        path = "/plugins/" .. plugin_id .. "/redis-ping",
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
                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "header-based-rate-limiting",
                            config = {
                                redis = {
                                    host = "kong-redis",
                                    db = 128
                                },
                                default_rate_limit = 1,
                                identification_headers = { "x-custom-identifier" }
                            }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_plugin_response_body = plugin_response:read_body()
                    local plugin_id = cjson.decode(raw_plugin_response_body).id

                    local response = helpers.admin_client():send({
                        method = "GET",
                        path = "/plugins/" .. plugin_id .. "/redis-ping",
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
                local plugin_response = assert(helpers.admin_client():send({
                    method = "POST",
                    path = "/services/" .. service_id .. "/plugins",
                    body = {
                        name = "header-based-rate-limiting",
                        config = {
                            redis = {
                                host = "kong-redis"
                            },
                            default_rate_limit = 1,
                            identification_headers = { "x-custom-identifier" }
                        }
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                }))

                local raw_plugin_response_body = plugin_response:read_body()
                local plugin_id = cjson.decode(raw_plugin_response_body).id

                local response = helpers.admin_client():send({
                    method = "GET",
                    path = "/plugins/" .. plugin_id .. "/redis-ping",
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                local raw_body = assert.res_status(200, response)
                local body = cjson.decode(raw_body)

                assert.are.equal("PONG", body.message)
            end)
        end)
    end)

    describe("Rate limiting", function()
        context("when Redis is unreachable", function()
            it("shouldn't block the request", function()
                assert(helpers.admin_client():send({
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

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route"
                }))

                assert.res_status(200, response)
            end)
        end)

        context("when Redis is configured properly", function()
            local plugin_id
            local default_rate_limit = 3

            before_each(function()
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

                local raw_plugin_response_body = plugin_response:read_body()
                plugin_id = cjson.decode(raw_plugin_response_body).id
            end)

            it("should rate limit after given amount of requests", function()
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

                local response = assert(helpers.proxy_client():send({
                    method = "GET",
                    path = "/test-route",
                    headers = {
                        ["X-Custom-Identifier"] = "api_consumer",
                    }
                }))

                local raw_response_body = response:read_body()
                headers = cjson.decode(raw_response_body).headers

                assert.are.equal('2', response.headers['x-ratelimit-remaining'])
                assert.are.equal(tostring(default_rate_limit), response.headers['x-ratelimit-limit'])
                assert.are.equal(time_reset, response.headers['x-ratelimit-reset'])
            end)

            context("when there are multiple consumers", function()
                it("should track rate limit pools separately", function()
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
                            name = 'other-test-service',
                            url = 'http://mockbin:8080/request'
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    local raw_service_response_body = service_response:read_body()

                    local service_id = cjson.decode(raw_service_response_body).id

                    assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/routes/",
                        body = {
                            service = {
                                id = service_id
                            },
                            paths = { '/other-test-route' }
                        },
                        headers = {
                            ["Content-Type"] = "application/json"
                        }
                    }))

                    assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
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

                    local raw_service_response_body = service_response:read_body()

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

                    local raw_first_route_response_body = first_route_response:read_body()

                    local first_route_id = cjson.decode(raw_first_route_response_body).id

                    assert(helpers.admin_client():send({
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

                    local raw_second_route_response_body = second_route_response:read_body()

                    local second_route_id = cjson.decode(raw_second_route_response_body).id

                    assert(helpers.admin_client():send({
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

                    local raw_service_response_body = service_response:read_body()

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

                    local raw_route_response_body = route_response:read_body()

                    local route_id = cjson.decode(raw_route_response_body).id

                    assert(helpers.admin_client():send({
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

                    local raw_service_response_body = service_response:read_body()

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

                    local route_response_body = route_response:read_body()

                    local route_id = cjson.decode(route_response_body).id

                    assert(helpers.admin_client():send({
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
        end)
    end)
end)
