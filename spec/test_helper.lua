local helpers = require "spec.helpers"

local TestHelper = {}

function TestHelper.setup_service()

    return assert(helpers.admin_client():send {
        method = "POST",
        path = "/services/",
        body = {
            name = 'testservice',
            url = 'http://mockbin:8080/request'
        },
        headers = {
            ["Content-Type"] = "application/json"
        }
    })

end

function TestHelper.setup_route_for_service(service_id)
    return assert(helpers.admin_client():send {
        method = "POST",
        path = "/services/" .. service_id .. "/routes/",
        body = {
            paths = {'/'},
        },
        headers = {
            ["Content-Type"] = "application/json"
        }
    })
end

function TestHelper.setup_plugin_for_service(service_id, plugin_name, config)
    local request_body = {name = plugin_name}

    if config ~= nil then
        request_body.config = config
    end

    return assert(helpers.admin_client():send {
        method = "POST",
        path = "/services/" .. service_id .. "/plugins/",
        body = request_body,
        headers = {
            ["Content-Type"] = "application/json"
        }
    })
end

function TestHelper.setup_consumer(customer_name)
    return assert(helpers.admin_client():send {
        method = "POST",
        path = "/consumers/",
        body = {
            username = customer_name,
        },
        headers = {
            ["Content-Type"] = "application/json"
        }
    })
end

return TestHelper
