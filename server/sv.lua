local ESX = exports['es_extended']:getSharedObject()

local function socacc(job)
    MySQL.update.await(
        'INSERT IGNORE INTO addon_account (name, label, shared, money) VALUES (?, ?, 0, 0)',
        { 'society_' .. job, dnj.jobs[job].label .. ' pokladna' }
    )
end

local function isboss(source, job)
    local xpl = ESX.GetPlayerFromId(source)
    if not xpl then return false end
    local cfg = dnj.jobs[job]
    if not cfg then return false end
    if xpl.getJob().name ~= job then return false end
    for _, g in ipairs(cfg.boss_grades) do
        if xpl.getJob().grade == g then return true end
    end
    return false
end

local function socbalance(job)
    return MySQL.scalar.await('SELECT money FROM addon_account WHERE name = ?', { 'society_' .. job }) or 0
end

local function addsocmoney(job, amount)
    MySQL.update.await('UPDATE addon_account SET money = money + ? WHERE name = ?', { amount, 'society_' .. job })
end

local function remsocmoney(job, amount)
    MySQL.update.await('UPDATE addon_account SET money = money - ? WHERE name = ?', { amount, 'society_' .. job })
end

lib.callback.register('dnj_bossmenu:getemployees', function(source, job)
    if type(job) ~= 'string' then return nil end
    if not isboss(source, job) then return nil end

    local online = {}
    local onlineids = {}
    for _, pid in ipairs(ESX.GetPlayers()) do
        local xp = ESX.GetPlayerFromId(pid)
        if xp and xp.getJob().name == job then
            local ident = xp.getIdentifier()
            onlineids[ident] = true
            table.insert(online, {
                source = pid,
                identifier = ident,
                name = xp.getName(),
                grade = xp.getJob().grade,
                gradeLabel = xp.getJob().grade_label,
                offline = false,
            })
        end
    end

    local rows = MySQL.query.await("SELECT identifier, CONCAT(firstname, ' ', lastname) AS name, job_grade FROM users WHERE job = ?", { job })
    local result = {}
    for _, v in ipairs(online) do table.insert(result, v) end
    for _, row in ipairs(rows or {}) do
        if not onlineids[row.identifier] then
            table.insert(result, {
                source = -1,
                identifier = row.identifier,
                name = row.name,
                grade = row.job_grade,
                gradeLabel = nil,
                offline = true,
            })
        end
    end
    return result
end)

lib.callback.register('dnj_bossmenu:getgrades', function(source, job)
    if type(job) ~= 'string' then return nil end
    if not isboss(source, job) then return nil end
    return MySQL.query.await('SELECT grade, label, salary FROM job_grades WHERE job_name = ? ORDER BY grade ASC', { job }) or {}
end)

lib.callback.register('dnj_bossmenu:getbalance', function(source, job)
    if type(job) ~= 'string' then return nil end
    if not isboss(source, job) then return nil end
    return socbalance(job)
end)

lib.callback.register('dnj_bossmenu:hire', function(source, tid, job)
    if type(tid) ~= 'number' or type(job) ~= 'string' then return false, 'Neplatné parametry.' end
    if not isboss(source, job) then return false, 'Nemáš oprávnění.' end

    local xtarget = ESX.GetPlayerFromId(tid)
    if not xtarget then return false, 'Hráč nenalezen.' end
    if xtarget.source == source then return false, 'Nemůžeš zaměstnat sám sebe.' end
    if xtarget.getJob().name ~= 'unemployed' then return false, 'Hráč už má práci.' end

    xtarget.setJob(job, 0)
    TriggerClientEvent('ox_lib:notify', xtarget.source, { type = 'success', description = ('Byl jsi zaměstnán: %s'):format(dnj.jobs[job].label) })
    return true, ('Zaměstnán: %s'):format(xtarget.getName())
end)

lib.callback.register('dnj_bossmenu:fire', function(source, targetsrc, job, isoffline)
    if type(job) ~= 'string' then return false, 'Neplatné parametry.' end
    if not isboss(source, job) then return false, 'Nemáš oprávnění.' end

    if not isoffline then
        if type(targetsrc) ~= 'number' then return false, 'Neplatné parametry.' end
        if targetsrc == source then return false, 'Nemůžeš vyhodit sám sebe.' end
        local xtarget = ESX.GetPlayerFromId(targetsrc)
        if not xtarget then return false, 'Hráč nenalezen.' end
        if xtarget.getJob().name ~= job then return false, 'Hráč není ve tvé firmě.' end
        local meno = xtarget.getName()
        xtarget.setJob('unemployed', 0)
        TriggerClientEvent('ox_lib:notify', xtarget.source, { type = 'warning', description = 'Byl jsi vyhozen z práce.' })
        return true, ('Vyhozen: %s'):format(meno)
    else
        if type(targetsrc) ~= 'string' then return false, 'Neplatné parametry.' end
        local row = MySQL.single.await("SELECT CONCAT(firstname, ' ', lastname) AS name, job FROM users WHERE identifier = ?", { targetsrc })
        if not row then return false, 'Hráč nenalezen v DB.' end
        if row.job ~= job then return false, 'Hráč není ve tvé firmě.' end
        MySQL.update.await('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', { 'unemployed', 0, targetsrc })
        return true, ('Vyhozen (offline): %s'):format(row.name)
    end
end)

lib.callback.register('dnj_bossmenu:promote', function(source, targetsrc, job, newgrade, isoffline)
    if type(job) ~= 'string' or type(newgrade) ~= 'number' then return false, 'Neplatné parametry.' end
    if not isboss(source, job) then return false, 'Nemáš oprávnění.' end

    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM job_grades WHERE job_name = ? AND grade = ?', { job, newgrade })
    if not exists or exists == 0 then return false, 'Grade neexistuje.' end

    if not isoffline then
        if type(targetsrc) ~= 'number' then return false, 'Neplatné parametry.' end
        if targetsrc == source then return false, 'Nemůžeš změnit grade sám sobě.' end
        local xtarget = ESX.GetPlayerFromId(targetsrc)
        if not xtarget then return false, 'Hráč nenalezen.' end
        if xtarget.getJob().name ~= job then return false, 'Hráč není ve tvé firmě.' end
        xtarget.setJob(job, newgrade)
        TriggerClientEvent('ox_lib:notify', xtarget.source, { type = 'success', description = ('Byl jsi povýšen na grade %s'):format(newgrade) })
        return true, ('Povýšen na grade %s'):format(newgrade)
    else
        if type(targetsrc) ~= 'string' then return false, 'Neplatné parametry.' end
        local row = MySQL.single.await("SELECT CONCAT(firstname, ' ', lastname) AS name, job FROM users WHERE identifier = ?", { targetsrc })
        if not row then return false, 'Hráč nenalezen v DB.' end
        if row.job ~= job then return false, 'Hráč není ve tvé firmě.' end
        MySQL.update.await('UPDATE users SET job_grade = ? WHERE identifier = ?', { newgrade, targetsrc })
        return true, ('Povýšen (offline): %s na grade %s'):format(row.name, newgrade)
    end
end)

lib.callback.register('dnj_bossmenu:setsalary', function(source, job, grade, amount)
    if type(job) ~= 'string' or type(grade) ~= 'number' or type(amount) ~= 'number' then return false, 'Neplatné parametry.' end
    if not isboss(source, job) then return false, 'Nemáš oprávnění.' end
    if amount < 0 then return false, 'Plat nemůže být záporný.' end
    if amount > dnj.maxsalary then return false, ('Maximum je $%s.'):format(dnj.maxsalary) end

    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM job_grades WHERE job_name = ? AND grade = ?', { job, grade })
    if not exists or exists == 0 then return false, 'Grade neexistuje.' end

    MySQL.update.await('UPDATE job_grades SET salary = ? WHERE job_name = ? AND grade = ?', { amount, job, grade })
    return true, ('Plat grade %s nastaven na $%s'):format(grade, amount)
end)

lib.callback.register('dnj_bossmenu:withdraw', function(source, job, amount)
    if type(job) ~= 'string' or type(amount) ~= 'number' then return false, 'Neplatné parametry.' end
    if not isboss(source, job) then return false, 'Nemáš oprávnění.' end
    if amount <= 0 then return false, 'Částka musí být kladná.' end

    local balance = socbalance(job)
    if balance < amount then return false, 'Nedostatek prostředků v pokladně.' end

    remsocmoney(job, amount)
    exports.ox_inventory:AddItem(source, 'money', amount)
    return true, ('Vybráno $%s z pokladny.'):format(amount)
end)

lib.callback.register('dnj_bossmenu:deposit', function(source, job, amount)
    if type(job) ~= 'string' or type(amount) ~= 'number' then return false, 'Neplatné parametry.' end
    if not isboss(source, job) then return false, 'Nemáš oprávnění.' end
    if amount <= 0 then return false, 'Částka musí být kladná.' end

    local xpl = ESX.GetPlayerFromId(source)
    if xpl.getMoney() < amount then return false, 'Nemáš dostatek hotovosti.' end

    exports.ox_inventory:RemoveItem(source, 'money', amount)
    addsocmoney(job, amount)
    return true, ('Vloženo $%s do pokladny.'):format(amount)
end)

local function salariespay()
    for jobname, cfg in pairs(dnj.jobs) do
        local grades = MySQL.query.await('SELECT grade, salary FROM job_grades WHERE job_name = ?', { jobname })
        if not grades then goto continue end

        local gsalary = {}
        for _, g in ipairs(grades) do gsalary[g.grade] = g.salary end

        for _, pid in ipairs(ESX.GetPlayers()) do
            local xp = ESX.GetPlayerFromId(pid)
            if xp and xp.getJob().name == jobname then
                local salary = gsalary[xp.getJob().grade] or 0
                if salary <= 0 then goto nextplayer end

                if cfg.salary_from_void then
                    exports.ox_inventory:AddItem(pid, 'money', salary)
                    TriggerClientEvent('ox_lib:notify', pid, { type = 'success', description = ('Výplata: $%s'):format(salary) })
                else
                    local balance = socbalance(jobname)
                    if balance >= salary then
                        remsocmoney(jobname, salary)
                        exports.ox_inventory:AddItem(pid, 'money', salary)
                        TriggerClientEvent('ox_lib:notify', pid, { type = 'success', description = ('Výplata: $%s'):format(salary) })
                    else
                        TriggerClientEvent('ox_lib:notify', pid, { type = 'error', description = 'Firma nemá dostatek prostředků na výplatu.' })
                    end
                end
                ::nextplayer::
            end
        end
        ::continue::
    end
end

AddEventHandler('onResourceStart', function(rsname)
    if rsname ~= GetCurrentResourceName() then return end
    for job in pairs(dnj.jobs) do socacc(job) end
end)

CreateThread(function()
    while true do
        Wait(dnj.salaryinterval * 60 * 1000)
        salariespay()
    end
end)