# SoDShopDumper

魔兽世界探索赛季（classic era）**NPC 商店数据采集插件**，为 [wow-sod-wiki](https://github.com/Addons-SoD/wow-sod-wiki) 的装备兑换表收集真实兑换数据。

> 完全自包含：不依赖、不修改、不借道任何其它插件；只使用游戏自带的商店 API。

---

## 一、安装与确认

放到 `_classic_era_\Interface\AddOns\SoDShopDumper\`（已就位），进游戏在插件列表勾选启用。

登录后会看到：

```
[SoDShopDumper] 已加载。与商人对话打开商店即自动记录，输入 /sdd 查看。
```

---

## 二、怎么采集

**与商人对话、把商店窗口打开即可**，不需要点任何按钮。每打开一次商店就会：

- 读取商店里全部商品：物品 ID / 名称 / 链接 / 价格（铜）/ 堆叠 / 库存 / 是否可用
- 读取每件商品的兑换材料：`GetMerchantItemCostInfo` + `GetMerchantItemCostItem`（材料物品 ID、数量、名称）
- 按 **服务器 → 角色 → 商人** 三级归档

完成后聊天框会提示：

```
[SoDShopDumper] 已记录 格雷什卡#1234：共 12 条（新增 12 / 更新 0）
```

### 为什么要分角色

不同角色（职业 / 声望 / 任务进度）能买到的东西不同，所以数据按 **每个角色单独存一份**，互不覆盖。
同一角色重复访问同一个商人时是**合并**：已有条目更新字段、新条目追加，不会丢历史。

---

## 三、命令

| 命令 | 作用 |
|---|---|
| `/sdd` | 帮助 + 记录总览（各角色分别有多少商人、多少条目） |
| `/sdd here` | 打印**当前商人**已记录的内容 |
| `/sdd list` | 打印全部记录（紧凑清单，含价格与兑换材料） |
| `/sdd ui` | 打开导出窗口，显示全量数据（Lua 表），可 Ctrl+A → Ctrl+C 复制 |
| `/sdd api` | 诊断：列出本客户端各商店 API 的可用情况 |
| `/sdd clear yes` | 清空**当前角色**的记录 |

---

## 四、把数据交给数据侧

两种方式，任选：

1. **直接给文件**（推荐）
   ```
   _classic_era_\WTF\Account\<账号>\SavedVariables\SoDShopDumper.lua
   ```
   退出游戏后文件才会写入完整内容（或在游戏内 `/reload` 也会落盘）。

2. **游戏内复制**
   `/sdd ui` → 窗口里「全选」→ Ctrl+C → 粘贴给数据侧。

---

## 五、数据结构

```lua
SoDShopDumperDB = {
  schema = 1,
  realms = {
    ["服务器名"] = {
      ["角色名"] = {
        updated = 1699999999,
        npcs = {
          ["商人名#npcID"] = {
            npcID = 1234, npcName = "商人名", guid = "Creature-0-...",
            firstSeen = 1699999999, lastSeen = 1699999999, visits = 3, count = 12,
            items = {
              [21217] = {
                id = 21217, name = "其拉帝王披风", link = "|cff...|Hitem:21217...|h[...]|h|r",
                price = 0,          -- 铜币；0 表示不用钱买
                stack = 1, avail = -1, usable = true, extCost = 0,
                costs = {           -- 兑换所需材料
                  { itemID = 21217, count = 20, name = "其拉徽记", link = "...", isCurrency = false },
                },
                firstSeen = 1699999999, seen = 1699999999,
              },
            },
          },
        },
      },
    },
  },
}
```

---

## 六、已知边界

- 覆盖的是**商店框架**（`MERCHANT_SHOW` / `MERCHANT_UPDATE`）。若某个 NPC 的兑换是**纯对话选项**（不打开商店窗口），本版本不会记录——遇到的话告诉我，我再加 `GOSSIP_SHOW` 分支。
- 价格与材料以**客户端实际返回**为准；若某物品在游戏里显示「已学会/不可用」，记录里 `usable=false`，但数据仍会保留。
- 若 `/sdd api` 显示某些 API「缺失」，把截图或文本发我，我按实际客户端调整兼容层。
