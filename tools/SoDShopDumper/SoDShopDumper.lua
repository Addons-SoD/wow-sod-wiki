--[[----------------------------------------------------------------------------
    SoDShopDumper  ·  魔兽世界探索赛季（classic era）商店数据采集
    ----------------------------------------------------------------------------
    用途：与 NPC 商人对话打开商店时，自动记录【商品 + 价格 + 兑换材料】。
          数据按 服务器 → 角色 → NPC 三级隔离存放，重复访问只合并不覆盖。

    设计约束（按需求）：
      * 完全自包含：不依赖、不修改、不借道任何其它插件
      * 所有商店 API 都做存在性判断 + pcall 保护，缺某个 API 也不会报错中断
      * 兼容 classic era 1.15.x（Interface 11509）与向后移植的新式 API

    命令：/sdd            —— 帮助与统计
          /sdd api        —— 显示本客户端各商店 API 的可用情况（诊断用）
          /sdd here       —— 打印当前商人已记录的内容
          /sdd list       —— 打印全部记录（紧凑清单）
          /sdd ui         —— 打开导出窗口（全量 Lua 表，可 Ctrl+A / Ctrl+C）
          /sdd clear      —— 清空【当前角色】的记录（需输入 /sdd clear yes 确认）
----------------------------------------------------------------------------]]

local ADDON, SCHEMA = "SoDShopDumper", 1

local type, tonumber, tostring, pairs, ipairs, select, time =
      type, tonumber, tostring, pairs, ipairs, select, time
local strsplit, format, match = strsplit, string.format, string.match
local tinsert, tsort = table.insert, table.sort

----------------------------------------------------------------------
-- 兼容层：新旧 API 双路径
----------------------------------------------------------------------
local C_Item_ = _G.C_Item
local C_MF     = _G.C_MerchantFrame

local api = {
    GetItemInfo      = _G.GetItemInfo      or (C_Item_ and C_Item_.GetItemInfo),
    GetItemInfoInstant = _G.GetItemInfoInstant or (C_Item_ and C_Item_.GetItemInfoInstant),
    GetRealmName     = _G.GetRealmName,
    UnitName         = _G.UnitName,
    UnitGUID         = _G.UnitGUID,
    NumItems         = _G.GetMerchantNumItems  or (C_MF and C_MF.GetNumItems),
    ItemInfo         = _G.GetMerchantItemInfo  or (C_MF and C_MF.GetItemInfo),
    ItemLink         = _G.GetMerchantItemLink  or (C_MF and C_MF.GetItemLink),
    ItemID           = _G.GetMerchantItemID    or (C_MF and C_MF.GetItemID),
    CostInfo         = _G.GetMerchantItemCostInfo or (C_MF and C_MF.GetItemCostInfo),
    CostItem         = _G.GetMerchantItemCostItem or (C_MF and C_MF.GetItemCostItem),
}

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

local function itemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(match(link, "item:(%d+)"))
end

----------------------------------------------------------------------
-- 数据存取
----------------------------------------------------------------------
local function charKey()
    local realm = (safe(api.GetRealmName) or "未知服务器")
    local name  = (safe(api.UnitName, "player") or "未知角色")
    return realm, name
end

local function ensureDB()
    if type(_G.SoDShopDumperDB) ~= "table" then _G.SoDShopDumperDB = {} end
    local db = _G.SoDShopDumperDB
    db.schema = SCHEMA
    db.realms = db.realms or {}
    local realm, char = charKey()
    db.realms[realm] = db.realms[realm] or {}
    local c = db.realms[realm][char]
    if type(c) ~= "table" then
        c = {}
        db.realms[realm][char] = c
    end
    c.npcs = c.npcs or {}
    c.updated = time()
    return c, realm, char
end

-- 当前商人标识
local function merchantKey()
    local guid = safe(api.UnitGUID, "npc")
    local npcID = 0
    if type(guid) == "string" then
        local seg = { strsplit("-", guid) }
        npcID = tonumber(seg[6]) or 0
    end
    local npcName = safe(api.UnitName, "npc") or "未知商人"
    return npcName, npcID, guid, format("%s#%d", npcName, npcID)
end

-- 读取单个商品
local function readItem(index)
    local itemID = safe(api.ItemID, index)
    local link   = safe(api.ItemLink, index)
    if not itemID then itemID = itemIDFromLink(link) end
    if not itemID then return nil end

    -- 返回值个数随客户端版本不同（7~10 个），多余变量为 nil，安全
    local name, texture, price, stack, avail, usable, extCost =
        safe(api.ItemInfo, index)

    -- 兑换材料
    local costs = {}
    local nCost = safe(api.CostInfo, index)
    nCost = tonumber(nCost) or 0
    for c = 1, nCost do
        local cTex, cValue, cLink, cName = safe(api.CostItem, index, c)
        cValue = tonumber(cValue) or 0
        if cValue > 0 then
            local cID = itemIDFromLink(cLink)
            -- 物品兑换时第四个返回值（货币名）通常为空，从链接里补出名称
            local cNm = cName
            if (not cNm or cNm == "") and type(cLink) == "string" then
                cNm = match(cLink, "%[(.-)%]")
            end
            tinsert(costs, {
                itemID = cID,          -- nil 表示虚拟货币
                count  = cValue,
                link   = cLink,
                name   = cNm,
                isCurrency = (cID == nil),
            })
        end
    end

    local rec = {
        id      = itemID,
        name    = name,
        link    = link,
        price   = tonumber(price) or 0,   -- 铜币；0 表示不用钱
        stack   = tonumber(stack),
        avail   = tonumber(avail),
        usable  = usable,
        extCost = tonumber(extCost) or 0,
        costs   = costs,
        seen    = time(),
    }
    return rec
end

----------------------------------------------------------------------
-- 抓取当前商店
----------------------------------------------------------------------
local function capture(isShow)
    if type(api.NumItems) ~= "function" then
        return 0, 0, "缺少 GetMerchantNumItems（请用 /sdd api 诊断）", nil
    end
    local n = tonumber(safe(api.NumItems)) or 0
    if n <= 0 then return 0, 0, "商店为空", nil end

    local charDB = ensureDB()
    local npcName, npcID, guid, key = merchantKey()

    local node = charDB.npcs[key]
    if type(node) ~= "table" then
        node = { npcID = npcID, npcName = npcName, firstSeen = time(), items = {} }
        charDB.npcs[key] = node
    end
    node.npcID, node.npcName, node.guid = npcID, npcName, guid
    node.lastSeen = time()
    -- 只在真正打开商店时计一次「访问」；MERCHANT_UPDATE 会频繁触发，不计入
    if isShow then
        node.visits = (node.visits or 0) + 1
    end

    local added, updated, failed = 0, 0, 0
    for i = 1, n do
        local ok, rec = pcall(readItem, i)
        if ok and rec then
            local old = node.items[rec.id]
            if old then
                rec.firstSeen = old.firstSeen or old.seen
                updated = updated + 1
            else
                rec.firstSeen = rec.seen
                added = added + 1
            end
            node.items[rec.id] = rec
        else
            failed = failed + 1
        end
    end

    node.count = 0
    for _ in pairs(node.items) do node.count = node.count + 1 end

    return added, updated, nil, { key = key, npcName = npcName, npcID = npcID,
                                  total = node.count, failed = failed }
end

----------------------------------------------------------------------
-- 统计 / 打印
----------------------------------------------------------------------
local function moneyText(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return "0" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = {}
    if g > 0 then tinsert(out, g .. "g") end
    if s > 0 then tinsert(out, s .. "s") end
    if c > 0 then tinsert(out, c .. "c") end
    return table.concat(out, " ")
end

local function costText(costs)
    if type(costs) ~= "table" or #costs == 0 then return "—" end
    local out = {}
    for _, c in ipairs(costs) do
        local nm = c.name or (c.link and match(c.link, "%[(.-)%]")) or ("#" .. tostring(c.itemID or "?"))
        tinsert(out, format("%s×%d", nm, c.count or 0))
    end
    return table.concat(out, " + ")
end

local function printStats()
    local db = _G.SoDShopDumperDB
    if type(db) ~= "table" or type(db.realms) ~= "table" then
        print("|cffc8a24b[SoDShopDumper]|r 还没有任何记录。与商人对话打开商店即可自动采集。")
        return
    end
    local realm, char = charKey()
    print("|cffc8a24b[SoDShopDumper]|r 记录总览：")
    for r, chars in pairs(db.realms) do
        for ch, c in pairs(chars) do
            local npcN, itemN = 0, 0
            for _, node in pairs(c.npcs or {}) do
                npcN = npcN + 1
                itemN = itemN + (node.count or 0)
            end
            local mark = (r == realm and ch == char) and "  ←当前" or ""
            print(format("   %s / %s ：%d 个商人，%d 条商品%s", r, ch, npcN, itemN, mark))
        end
    end
end

local function printHere()
    local charDB = ensureDB()
    local npcName, npcID, _, key = merchantKey()
    local node = charDB.npcs[key]
    if not node then
        print(format("|cffc8a24b[SoDShopDumper]|r 当前商人 %s 还没有记录，打开一次商店即可。", key))
        return
    end
    print(format("|cffc8a24b[SoDShopDumper]|r %s（共 %d 条，访问 %d 次）",
        key, node.count or 0, node.visits or 0))
    local ids = {}
    for id in pairs(node.items) do tinsert(ids, id) end
    tsort(ids)
    for _, id in ipairs(ids) do
        local it = node.items[id]
        local nm = it.name or (it.link and match(it.link, "%[(.-)%]")) or "?"
        print(format("   [%s] %s ｜ 价格 %s ｜ 兑换 %s",
            tostring(id), nm, moneyText(it.price), costText(it.costs)))
    end
end

local function printList()
    local db = _G.SoDShopDumperDB
    if type(db) ~= "table" or type(db.realms) ~= "table" then
        print("|cffc8a24b[SoDShopDumper]|r 暂无记录。")
        return
    end
    for r, chars in pairs(db.realms) do
        for ch, c in pairs(chars) do
            print(format("|cffc8a24b[%s / %s]|r", r, ch))
            local keys = {}
            for k in pairs(c.npcs or {}) do tinsert(keys, k) end
            tsort(keys)
            for _, k in ipairs(keys) do
                local node = c.npcs[k]
                print(format("  ▸ %s（%d 条）", k, node.count or 0))
                local ids = {}
                for id in pairs(node.items or {}) do tinsert(ids, id) end
                tsort(ids)
                for _, id in ipairs(ids) do
                    local it = node.items[id]
                    local nm = it.name or (it.link and match(it.link, "%[(.-)%]")) or "?"
                    print(format("      [%s] %s ｜ %s ｜ %s",
                        tostring(id), nm, moneyText(it.price), costText(it.costs)))
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- 序列化（导出成可直接阅读/解析的 Lua 表）
----------------------------------------------------------------------
local function escStr(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "")
    return s
end

local function serialize(v, indent, out)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local t = type(v)
    if t == "table" then
        -- 数组 or 字典
        local isArr, n = true, 0
        for k in pairs(v) do
            n = n + 1
            if type(k) ~= "number" then
                isArr = false
                break
            end
        end
        tinsert(out, "{")
        if isArr and n > 0 then
            for _, item in ipairs(v) do
                local buf = {}
                serialize(item, indent + 1, buf)
                tinsert(out, pad .. "  " .. table.concat(buf))
            end
        else
            local keys = {}
            for k in pairs(v) do tinsert(keys, k) end
            tsort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local buf = {}
                serialize(v[k], indent + 1, buf)
                local keyTxt
                if type(k) == "number" then keyTxt = "[" .. k .. "]"
                else keyTxt = '["' .. escStr(k) .. '"]' end
                tinsert(out, pad .. "  " .. keyTxt .. " = " .. table.concat(buf) .. ",")
            end
        end
        tinsert(out, pad .. "}")
    elseif t == "string" then
        tinsert(out, '"' .. escStr(v) .. '"')
    elseif t == "number" or t == "boolean" then
        tinsert(out, tostring(v))
    else
        tinsert(out, "nil")
    end
end

local function buildExport()
    local out = {}
    tinsert(out, "-- SoDShopDumper 导出（" .. date("%Y-%m-%d %H:%M:%S") .. "）")
    tinsert(out, "-- 结构：realms[服务器][角色].npcs[商人名#npcID].items[itemID]")
    serialize(_G.SoDShopDumperDB or {}, 0, out)
    return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- 导出窗口
----------------------------------------------------------------------
local ui
local function showUI()
    local text = buildExport()
    if not ui then
        ui = CreateFrame("Frame", "SoDShopDumperUI", UIParent)
        ui:SetSize(760, 560)
        ui:SetPoint("CENTER")
        ui:SetFrameStrata("DIALOG")
        ui:EnableMouse(true)
        ui:SetMovable(true)
        ui:RegisterForDrag("LeftButton")
        ui:SetScript("OnDragStart", function(self) self:StartMoving() end)
        ui:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if ui.SetBackdrop then
            ui:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 8, right = 8, top = 8, bottom = 8 },
            })
        end

        local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("SoDShopDumper 导出（Ctrl+A 全选 → Ctrl+C 复制）")

        local hint = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
        hint:SetText("也可直接把 WTF\\Account\\<账号>\\SavedVariables\\SoDShopDumper.lua 交给数据侧")

        local sf = CreateFrame("ScrollFrame", "SoDShopDumperScroll", ui, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 20, -70)
        sf:SetPoint("BOTTOMRIGHT", -34, 44)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(680)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(eb)
        ui.edit = eb

        local btn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
        btn:SetSize(100, 24)
        btn:SetPoint("BOTTOMRIGHT", -20, 14)
        btn:SetText("关闭")
        btn:SetScript("OnClick", function() ui:Hide() end)

        local btn2 = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
        btn2:SetSize(120, 24)
        btn2:SetPoint("RIGHT", btn, "LEFT", -8, 0)
        btn2:SetText("全选")
        btn2:SetScript("OnClick", function()
            ui.edit:SetFocus()
            ui.edit:HighlightText()
        end)
    end
    ui.edit:SetText(text)
    ui:Show()
end

----------------------------------------------------------------------
-- 命令
----------------------------------------------------------------------
local function printHelp()
    print("|cffc8a24b[SoDShopDumper]|r 商店数据采集（与商人对话自动记录）")
    print("   /sdd        统计总览")
    print("   /sdd here   当前商人记录")
    print("   /sdd list   全部记录（紧凑）")
    print("   /sdd ui     打开导出窗口（可复制全量数据）")
    print("   /sdd api    诊断：本客户端商店 API 可用情况")
    print("   /sdd clear yes   清空【当前角色】记录")
end

local function cmd(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "help" then
        printHelp()
        printStats()
    elseif msg == "api" then
        print("|cffc8a24b[SoDShopDumper]|r API 可用情况：")
        local names = {}
        for k in pairs(api) do tinsert(names, k) end
        tsort(names)
        for _, k in ipairs(names) do
            print(format("   %-20s %s", k, type(api[k]) == "function" and "可用" or "缺失"))
        end
        print("   C_MerchantFrame: " .. (C_MF and "存在" or "不存在"))
        print("   C_Item: " .. (C_Item_ and "存在" or "不存在"))
    elseif msg == "here" then
        printHere()
    elseif msg == "list" then
        printList()
    elseif msg == "ui" or msg == "export" then
        showUI()
    elseif msg == "clear yes" then
        local db = _G.SoDShopDumperDB
        local realm, char = charKey()
        if type(db) == "table" and db.realms and db.realms[realm] then
            db.realms[realm][char] = { npcs = {}, updated = time() }
            print(format("|cffc8a24b[SoDShopDumper]|r 已清空 %s / %s 的记录。", realm, char))
        else
            print("|cffc8a24b[SoDShopDumper]|r 当前角色没有记录。")
        end
    elseif msg == "clear" then
        print("|cffc8a24b[SoDShopDumper]|r 这会清空【当前角色】的全部记录。确认请输入： /sdd clear yes")
    else
        print("|cffc8a24b[SoDShopDumper]|r 未知命令：" .. msg)
        printHelp()
    end
end

SLASH_SDDSHOPDUMPER1 = "/sdd"
SLASH_SDDSHOPDUMPER2 = "/shopdump"
SlashCmdList["SDDSHOPDUMPER"] = cmd

----------------------------------------------------------------------
-- 事件
----------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_UPDATE")

local pending = false
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            ensureDB()
            print("|cffc8a24b[SoDShopDumper]|r 已加载。与商人对话打开商店即自动记录，输入 |cffffd100/sdd|r 查看。")
        end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
        -- MERCHANT_UPDATE 会被频繁触发，做个极短的合并，避免重复打印
        if pending then return end
        pending = true
        local ok, added, updated, err, info = pcall(capture, event == "MERCHANT_SHOW")
        pending = false
        if not ok then
            print("|cffc8a24b[SoDShopDumper]|r 采集出错：" .. tostring(added))
            return
        end
        if err then
            if event == "MERCHANT_SHOW" then
                print("|cffc8a24b[SoDShopDumper]|r " .. tostring(err))
            end
            return
        end
        if info and event == "MERCHANT_SHOW" then
            print(format("|cffc8a24b[SoDShopDumper]|r 已记录 %s：共 %d 条（新增 %d / 更新 %d）%s",
                info.key, info.total, added, updated,
                info.failed > 0 and format("，%d 条读取失败", info.failed) or ""))
        end
    end
end)
