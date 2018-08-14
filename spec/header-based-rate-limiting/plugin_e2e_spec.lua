local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("Plugin: header-based-rate-limiting (access)", function()

    setup(function()
        helpers.start_kong({ custom_plugins = 'header-based-rate-limiting' })
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    before_each(function()
        helpers.dao:truncate_tables()
    end)

    describe("admin API", function()
        describe("/plugins/:plugin_id/redis-ping", function()
            local service_id

            before_each(function()
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
                    local plugin_response = assert(helpers.admin_client():send({
                        method = "POST",
                        path = "/services/" .. service_id .. "/plugins",
                        body = {
                            name = "basic-auth"
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
                                }
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
                                }
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
                            }
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
end)
