-- Who a player is and what they can pay, on Qbox, QBCore or ESX.
-- Framework.player(src) returns
--   { id = citizenid or identifier, name, job, grade, duty, gang, gangGrade }

Framework = {}

local function started(name) return GetResourceState(name) == 'started' end

local kind, core

function Framework.name()
    if kind == nil then
        kind = started('qbx_core') and 'qbx' or started('qb-core') and 'qb' or started('es_extended') and 'esx' or false
    end
    return kind or nil
end

function Framework.reset() kind, core = nil, nil end

local function qbPlayer(src)
    if kind == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    core = core or exports['qb-core']:GetCoreObject()
    return core.Functions.GetPlayer(src)
end

local function esxPlayer(src)
    core = core or exports.es_extended:getSharedObject()
    return core.GetPlayerFromId(src)
end

function Framework.player(src)
    local fw = Framework.name()
    if not fw or not src or src <= 0 then return end

    if fw == 'esx' then
        local x = esxPlayer(src)
        if not x then return end
        local job = x.getJob and x.getJob() or x.job or {}
        return {
            id = x.identifier,
            name = x.getName and x.getName() or GetPlayerName(src),
            job = job.name,
            grade = tonumber(job.grade) or 0,
            duty = job.onDuty ~= false,
        }
    end

    local p = qbPlayer(src)
    local d = p and p.PlayerData
    if not d then return end
    local job, gang, info = d.job or {}, d.gang or {}, d.charinfo or {}
    return {
        id = d.citizenid,
        license = d.license,
        name = info.firstname and ('%s %s'):format(info.firstname, info.lastname or '') or GetPlayerName(src),
        job = job.name,
        grade = tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or 0,
        duty = job.onduty ~= false,
        gang = gang.name ~= 'none' and gang.name or nil,
        gangGrade = tonumber(type(gang.grade) == 'table' and gang.grade.level or gang.grade) or 0,
    }
end

local esxAccount = { cash = 'money' }

-- Takes the money and returns the account it came from, or false. Nothing is
-- taken from a player who can't pay the whole amount from one account.
function Framework.pay(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 'none' end
    local fw = Framework.name()
    if not fw then return false end

    for _, account in ipairs(Config.payWith) do
        if fw == 'esx' then
            local x = esxPlayer(src)
            local name = esxAccount[account] or account
            local acc = x and x.getAccount(name)
            if acc and (acc.money or 0) >= amount then
                x.removeAccountMoney(name, amount, reason)
                return account
            end
        else
            local p = qbPlayer(src)
            local have = p and p.PlayerData.money and p.PlayerData.money[account] or 0
            if have >= amount and p.Functions.RemoveMoney(account, amount, reason) ~= false then
                return account
            end
        end
    end
    return false
end

-- When a spawn fails after the fee was taken.
function Framework.refund(src, account, amount, reason)
    if not account or account == 'none' then return end
    if Framework.name() == 'esx' then
        local x = esxPlayer(src)
        if x then x.addAccountMoney(esxAccount[account] or account, amount, reason) end
    else
        local p = qbPlayer(src)
        if p then p.Functions.AddMoney(account, amount, reason) end
    end
end

-- The client only uses this to decide what to show. Every action checks again.
function Framework.sync(src)
    local p = Framework.player(src)
    Player(src).state:set('fivegarage', p and {
        job = p.job, grade = p.grade, duty = p.duty, gang = p.gang, gangGrade = p.gangGrade,
    } or nil, true)
end

local function later(src) SetTimeout(500, function() if GetPlayerName(src) then Framework.sync(src) end end) end

AddEventHandler('QBCore:Server:PlayerLoaded', function(p) later(p.PlayerData.source) end)
AddEventHandler('QBCore:Server:OnJobUpdate', later)
AddEventHandler('QBCore:Server:OnGangUpdate', later)
AddEventHandler('QBCore:Server:SetDuty', later)
AddEventHandler('esx:playerLoaded', later)
AddEventHandler('esx:setJob', later)
