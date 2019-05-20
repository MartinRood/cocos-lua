local timer         = require "kernel.timer"
local downloader    = require "kernel.downloader"

local assert = assert

local MAX_LOADING_FILES = 10
local MAX_ATTEMPTS = 3
local ATTEMPT_INTERVAL = 0.5

local loadQueue = {}
local loadTasks = {}
local started = false

local function checkStart()
    if not started then
        started = true
        timer.delay(0.01, function ()
            started = false

            local count = MAX_LOADING_FILES
            for _, task in pairs(loadQueue) do
                if task.attempts > 0 then
                    count = count - 1
                end
            end
            
            for _, task in pairs(loadQueue) do
                if count < 0 then
                    break
                end
                count = count - 1

                if task.attempts == 0 then
                    task.attempts = 1
                    downloader.load(task.url, task.path, task.md5)
                end
            end
        end)
    end
end

local function load(task)
    assert(task.url, "no url")
    if not loadQueue[task.url] then
        loadQueue[task.url] = {
            attempts = 0,
            url = task.url,
            path = assert(task.path, task.url),
            md5 = task.md5,
        }
    end
    
    loadTasks[task] = true
    checkStart()
end

local function notify(url, loaded)
    local doneTasks = {}
    for task in pairs(loadTasks) do
        if task.url == url then
            doneTasks[#doneTasks + 1] = task
        end
    end
    for _, task in ipairs(doneTasks) do
        loadTasks[task] = nil
        if task.callback then
            task.callback(loaded, task)
        end
    end
    checkStart()
end

downloader.setDispatcher(function (url, path, state)
    if state == 'ioerror' or state == 'invalid' then
        local task = assert(loadQueue[url], url)
        task.attempts = task.attempts + 1
        if task.attempts >= MAX_ATTEMPTS then
            print('[NO] load: ' .. url)
            loadQueue[url] = nil
            notify(url, false)
        else
            timer.delay(ATTEMPT_INTERVAL, function ()
                downloader.load(task.url, task.path, task.md5)
            end)
        end
    else
        print('[OK] load: ' .. url)
        loadQueue[url] = nil
        notify(url, true)
    end
end)

return {load = load}