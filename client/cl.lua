local ESX = exports['es_extended']:getSharedObject()
local regzones = {}

local function isboss(jobname, grade)
    local cfg = dnj.jobs[jobname]
    if not cfg then return false end
    for _, g in ipairs(cfg.boss_grades) do
        if grade == g then return true end
    end
    return false
end

local function unregister()
    for job in pairs(regzones) do
        exports.ox_target:removeZone('bossmenu_' .. job)
        regzones[job] = nil
    end
end

local function notify(typ, message)
    lib.notify({ type = typ, description = message })
end

local hlmenu, employes, hire, salaries, kasa

function hlmenu(job)
    local cfg = dnj.jobs[job]
    local data = ESX.GetPlayerData()

    if not data.job or data.job.name ~= job or not isboss(job, data.job.grade) then
        notify('error', 'Nemáš oprávnění.')
        return
    end

    lib.registerContext({
        id = 'hl',
        title = cfg.label .. ' — Boss Menu',
        options = {
            { title = 'Zaměstnanci',      icon = 'users',       onSelect = function() employes(job) end },
            { title = 'Nábor hráče',      icon = 'user-plus',   onSelect = function() hire(job) end },
            { title = 'Správa platů',     icon = 'dollar-sign', onSelect = function() salaries(job) end },
            { title = 'Firemní pokladna', icon = 'landmark',    onSelect = function() kasa(job) end },
        },
    })
    lib.showContext('hl')
end

local function targets(job, cfg)
    if regzones[job] then return end
    exports.ox_target:addBoxZone({
        coords = cfg.coords,
        size = vec3(1.2, 1.2, 2.2),
        rotation = 0,
        debug = false,
        options = {
            {
                name = 'bossmenu_' .. job,
                label = cfg.target_label,
                icon = 'fas fa-briefcase',
                onSelect = function() hlmenu(job) end,
            },
        },
    })
    regzones[job] = true
end

local function targetsupdate(jobname, grade)
    unregister()
    local cfg = dnj.jobs[jobname]
    if cfg and isboss(jobname, grade) then
        targets(jobname, cfg)
    end
end

function employes(job)
    local empls = lib.callback.await('dnj_bossmenu:getemployees', false, job)
    if not empls or #empls == 0 then
        notify('inform', 'Žádní zaměstnanci.')
        return
    end

    local grady = lib.callback.await('dnj_bossmenu:getgrades', false, job)
    local gradelabels = {}
    for _, g in ipairs(grady or {}) do gradelabels[g.grade] = g.label end

    local serverid = GetPlayerServerId(PlayerId())

    local options = {}
    for _, emp in ipairs(empls) do
        local empref = {
            source = tonumber(emp.source),
            identifier = emp.identifier,
            name = emp.name,
            grade = emp.grade,
            gradeLabel = emp.gradeLabel,
            offline = emp.offline
        }

        local goptions = {}
        for _, g in ipairs(grady or {}) do
            local gref = g
            table.insert(goptions, {
                title = gref.label .. ' (Grade ' .. gref.grade .. ')',
                onSelect = function()
                    local targetId = empref.offline and empref.identifier or empref.source
                    local ok, msg = lib.callback.await('dnj_bossmenu:promote', false, targetId, job, gref.grade, empref.offline)
                    notify(ok and 'success' or 'error', msg)
                end,
            })
        end

        local gradelabel = empref.gradeLabel or gradelabels[empref.grade] or ('Grade ' .. empref.grade)
        local desc = gradelabel .. ' · Grade ' .. empref.grade .. (empref.offline and ' ·  offline' or ' ·  online')
        local ctxid = empref.offline and ('menu_off_' .. empref.identifier) or ('menu_' .. empref.source)
        local gradesctxid = empref.offline and ('grades_off_' .. empref.identifier) or ('grades_' .. empref.source)

        local isu = (not empref.offline and empref.source == serverid)

        table.insert(options, {
            title = empref.name .. (isu and ' (Ty)' or ''),
            description = desc,
            icon = 'user',
            disabled = isu, 
            onSelect = function()
                if isu then return end 
                lib.registerContext({
                    id = ctxid,
                    title = empref.name,
                    menu = 'zamestnnanci',
                    options = {
                        {
                            title = 'Vyhodit',
                            icon = 'user-minus',
                            onSelect = function()
                                local targetId = empref.offline and empref.identifier or empref.source
                                local ok, msg = lib.callback.await('dnj_bossmenu:fire', false, targetId, job, empref.offline)
                                notify(ok and 'success' or 'error', msg)
                            end,
                        },
                        {
                            title = 'Změnit grade',
                            icon = 'arrow-up',
                            onSelect = function()
                                lib.registerContext({
                                    id = gradesctxid,
                                    title = 'Vyber grade — ' .. empref.name,
                                    menu = ctxid,
                                    options = goptions,
                                })
                                lib.showContext(gradesctxid)
                            end,
                        },
                    },
                })
                lib.showContext(ctxid)
            end,
        })
    end

    lib.registerContext({
        id = 'zamestnnanci',
        title = 'Zaměstnanci',
        menu = 'hl',
        options = options,
    })
    lib.showContext('zamestnnanci')
end

function hire(job)
    local input = lib.inputDialog('Nábor hráče', {
        { type = 'number', label = 'Server ID hráče', required = true },
    })
    if not input then return end
    local ok, msg = lib.callback.await('dnj_bossmenu:hire', false, tonumber(input[1]), job)
    notify(ok and 'success' or 'error', msg)
end

function salaries(job)
    local grady = lib.callback.await('dnj_bossmenu:getgrades', false, job)
    if not grady or #grady == 0 then
        notify('error', 'Nepodařilo se načíst grady.')
        return
    end

    local options = {}
    for _, g in ipairs(grady) do
        local gdata = g
        table.insert(options, {
            title = gdata.label,
            description = 'Aktuální plat: $' .. gdata.salary,
            icon = 'coins',
            onSelect = function()
                local input = lib.inputDialog('Nastavit plat — ' .. gdata.label, {
                    { type = 'number', label = ('Nový plat (max $%s)'):format(dnj.maxsalary), required = true, default = gdata.salary },
                })
                if not input then return end
                local ok, msg = lib.callback.await('dnj_bossmenu:setsalary', false, job, gdata.grade, math.floor(input[1]))
                notify(ok and 'success' or 'error', msg)
            end,
        })
    end

    lib.registerContext({
        id = 'platy',
        title = 'Správa platů',
        menu = 'hl',
        options = options,
    })
    lib.showContext('platy')
end

function kasa(job)
    local zustatek = lib.callback.await('dnj_bossmenu:getbalance', false, job)
    lib.registerContext({
        id = 'pokladna',
        title = 'Firemní pokladna',
        menu = 'hl',
        options = {
            {
                title = 'Zůstatek: $' .. (zustatek or 0),
                icon = 'wallet',
                disabled = true,
            },
            {
                title = 'Vybrat z pokladny',
                icon = 'arrow-up',
                onSelect = function()
                    local input = lib.inputDialog('Výběr z pokladny', {
                        { type = 'number', label = 'Částka ($)', required = true },
                    })
                    if not input then return end
                    local ok, msg = lib.callback.await('dnj_bossmenu:withdraw', false, job, math.floor(input[1]))
                    notify(ok and 'success' or 'error', msg)
                end,
            },
            {
                title = 'Vložit do pokladny',
                icon = 'arrow-down',
                onSelect = function()
                    local input = lib.inputDialog('Vklad do pokladny', {
                        { type = 'number', label = 'Částka ($)', required = true },
                    })
                    if not input then return end
                    local ok, msg = lib.callback.await('dnj_bossmenu:deposit', false, job, math.floor(input[1]))
                    notify(ok and 'success' or 'error', msg)
                end,
            },
        },
    })
    lib.showContext('pokladna')
end

AddEventHandler('esx:setJob', function(job)
    targetsupdate(job.name, job.grade)
end)

CreateThread(function()
    while true do
        local data = ESX.GetPlayerData()
        if data and data.job and data.job.name then break end
        Wait(100)
    end
    local data = ESX.GetPlayerData()
    targetsupdate(data.job.name, data.job.grade)
end)