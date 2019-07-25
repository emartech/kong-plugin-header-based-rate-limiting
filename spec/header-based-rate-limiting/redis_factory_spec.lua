local Redis = require "resty.redis"
local RedisFactory = require "kong.plugins.header-based-rate-limiting.redis_factory"

local FakeRedis = {}

function FakeRedis:set_timeout()
    return true
end

function FakeRedis:connect()
    return true
end

function FakeRedis:select()
    return true
end

local FakeRedisMeta = {
    __index = FakeRedis
}

local function create_fake_redis()
    return setmetatable({}, FakeRedisMeta)
end

describe("RedisFactory.create", function()

    local redis_new = Redis.new

    before_each(function()
        Redis.new = create_fake_redis

        spy.on(FakeRedis, "set_timeout")
        spy.on(FakeRedis, "connect")
        spy.on(FakeRedis, "select")
    end)

    after_each(function()
        Redis.new = redis_new

        FakeRedis.set_timeout:revert()
        FakeRedis.connect:revert()
        FakeRedis.select:revert()
    end)

    it("should return a Redis instance with given config", function()
        local redis = RedisFactory.create({
            timeout_in_milliseconds = 500,
            host = "my-redis-host",
            port = 1234,
            db = 10
        })

        assert.is_equal(getmetatable(redis), FakeRedisMeta)
        assert.spy(FakeRedis.set_timeout).was_called_with(FakeRedis, 500)
        assert.spy(FakeRedis.connect).was_called_with(FakeRedis, "my-redis-host", 1234)
        assert.spy(FakeRedis.select).was_called_with(FakeRedis, 10)
    end)

end)
