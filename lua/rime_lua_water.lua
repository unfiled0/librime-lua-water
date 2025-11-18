-- 导入必要的Lua标准库
local os = require("os") -- 操作系统相关功能
local io = require("io") -- 文件I/O操作

-- 常量定义
local CHUNK_SIZE = 1000                                          -- 每次从文本文件读取的字符数
local CONFIG_FILE = os.getenv("USERPROFILE") .. "\\rime_cfg.txt" -- 配置文件路径

-- 配置项
local config = {
    debug = false,                                                   -- 是否开启调试模式
    log_file = os.getenv("USERPROFILE") .. "\\librime_lua_water.log" -- 日志文件路径
}

-- 查询结果缓存，用于提高性能
local queryCache = {}

-- 模块定义
local M = {}

-- 日志记录函数
-- @param message 要记录的日志信息
local function log(message)
    if config.debug then
        local f = io.open(config.log_file, "a") -- 以追加模式打开日志文件
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n")
            f:close()
        end
    end
end

-- 读取配置文件并初始化环境
-- @param env 环境变量表
function M.read_cfg(env)
    -- 打开配置文件
    local file, err = io.open(CONFIG_FILE, "r")
    if not file then
        log("Error no config file in " .. CONFIG_FILE)
        return
    end

    -- 读取偏移量（文件读取位置）
    local offset_line = file:read("*l")
    if not offset_line then
        file:close()
        log("Error config file no offset")
        return
    end

    -- 转换偏移量为数字
    local init_offset = tonumber(offset_line)
    if not init_offset then
        file:close()
        log("Error config offset not a number")
        return
    end

    -- 读取文本文件路径
    local txt_file = file:read("*l") or ""
    if txt_file == "" then
        file:close()
        log("Error config file no txt")
    end

    -- 读取速度设置
    local speed_line = file:read("*l")
    if not speed_line then
        file:close()
        log("Error config file no speed setting")
        return
    end

    -- 设置速度参数，默认为1
    env.speed = tonumber(speed_line) or 1
    file:close()

    -- 记录调试信息
    log("Initial offset: " .. tostring(init_offset))
    log("Text file: " .. tostring(txt_file))
    log("Speed: " .. tostring(env.speed))
    log("Initializing with CHUNK_SIZE: " .. tostring(CHUNK_SIZE))

    -- 初始化环境变量
    env.init_offset = init_offset
    env.offset = env.init_offset
    env.utf8_offset = 0
    env.finished = false

    -- 打开文本文件
    local txtfile, error = io.open(txt_file, "rb")
    if not txtfile then
        log("Error opening txt file: " .. tostring(error))
        return
    end
    local size = txtfile:seek("end")
    log("File length " .. tostring(size))
    if size <= env.offset + 1 then
        log("Finished")
        env.finished = true
        txtfile:close()
        return
    end
    log("Not finished")


    -- 定位到指定偏移量
    txtfile:seek("set", env.offset)
    local content = txtfile:read(CHUNK_SIZE)

    -- 确保从有效的UTF-8字符开始读取
    while true do
        local ok, iter = pcall(utf8.codes, content)
        if not ok then
            log("Not a valid UTF-8 sequence at current position")
            env.offset = env.offset + 1
            log("New offset: " .. tostring(env.offset))
            txtfile:seek("set", env.offset + 1)
            content = txtfile:read(CHUNK_SIZE)
        else
            break
        end
    end

    txtfile:close()
    env.content = content -- 保存当前读取的内容
end

-- 初始化函数，在RIME引擎加载时调用
-- @param env 环境变量表
function M.init(env)
    -- 注册提交通知器，当用户选择候选词时触发
    env.commit_notifier = env.engine.context.commit_notifier:connect(
        function(ctx)
            local cand = ctx:get_selected_candidate()
            -- 只处理自定义类型的候选词
            if (cand and cand.type == "custom") then
                local text = ctx:get_commit_text()
                log("Committed text length: " .. #text)

                -- 更新字节偏移量
                env.offset = env.offset + #text
                log("New byte offset: " .. env.offset)

                -- 更新UTF-8字符偏移量
                env.utf8_offset = env.utf8_offset + utf8.len(text)
                log("New UTF-8 offset: " .. env.utf8_offset)

                -- 清空查询缓存
                queryCache = {}

                -- 读取当前配置文件内容
                local lines = {}
                for line in io.lines(CONFIG_FILE) do
                    table.insert(lines, line)
                end

                if #lines == 0 then
                    log("Error: Empty config file when updating offset")
                    return
                end

                -- 更新偏移量
                log("Saving new offset to config")
                lines[1] = tostring(env.offset)

                -- 写回配置文件
                local file, err = io.open(CONFIG_FILE, "w")
                if not file then
                    log("Error: Could not open config file for writing: " .. tostring(err))
                    return
                end

                for i, line in ipairs(lines) do
                    log("Writing line " .. i .. ": " .. line)
                    file:write(line, "\n")
                end

                log("Closing config file")
                file:close()
                log("Config file updated successfully")
            end
        end
    )

    -- 初始读取配置
    M.read_cfg(env)
end

-- 清理函数，在RIME引擎卸载时调用
-- @param env 环境变量表
function M.fini(env)
    -- 断开提交通知器的连接
    if env.commit_notifier then
        env.commit_notifier:disconnect()
    end
end

-- 从文本中查询指定长度的内容
-- @param len 请求的字符长度
-- @param env 环境变量表
-- @return 返回查询到的文本或nil
function M.query_txt(len, env)
    -- 如果请求的长度超过当前块大小，则重新加载更大的块
    if len >= CHUNK_SIZE then
        CHUNK_SIZE = CHUNK_SIZE * 100 -- 增加块大小
        M.read_cfg(env)               -- 重新加载配置和内容
        return ""
    end

    log(env.utf8_offset)
    -- 计算UTF-8字符在字节串中的起始位置
    local start = utf8.offset(env.content, env.utf8_offset + 1)
    if not start then
        M.read_cfg(env)
        return ""
    end
    log("start position" .. start)

    -- 计算结束位置
    local byte_end = utf8.offset(env.content, env.utf8_offset + len + 1)
    if not byte_end then
        -- 如果超出范围，重新加载配置
        M.read_cfg(env)
        return ""
    end
    log("end position" .. byte_end)

    -- 提取子字符串并缓存结果
    local result = string.sub(env.content, start, byte_end - 1)
    queryCache[len] = result
    return result
end

-- 主处理函数，处理输入并生成候选词
-- @param input 输入迭代器
-- @param env 环境变量表
function M.func(input, env)
    -- 收集所有候选词
    local candidates = {}
    for cand in input:iter() do
        table.insert(candidates, cand)
    end

    -- 如果有多个候选词，添加自定义候选
    if #candidates > 1 then
        local first = candidates[1]
        local text = first.text
        local len = utf8.len(text)
        log("Processing input: " .. text .. " (length=" .. len .. ")")
        -- 根据速度调整请求的长度
        len = len * env.speed
        log("true length " .. len)

        local t = ""
        -- 检查缓存中是否有结果
        if queryCache[len] then
            t = queryCache[len]
            log("Cache hit for length: " .. len)
        elseif env.finished then
            -- 如果未完成，重新读取配置
            M.read_cfg(env)
            log("Re-read config")
        else
            -- 从文本中查询
            t = M.query_txt(len, env)
            log("New text found: " .. t)
        end

        if not t then
            log("No text found for length: " .. len)
            return
        else
            -- 创建自定义候选并插入到列表开头
            table.insert(candidates, 1, Candidate(
                "custom", -- 候选类型
                first.start, -- 起始位置
                first._end, -- 结束位置
                t, -- 候选文本
                "👋" -- 注释
            ))
        end
    end

    -- 返回所有候选词
    for _, c in ipairs(candidates) do
        yield(c)
    end
end

return M
