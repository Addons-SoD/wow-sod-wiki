# SoDShopDumper（数据采集插件 · 已归档）

用于采集《魔兽世界》探索赛季（classic era）**NPC 商店的商品与兑换材料**，
为 [装备兑换表](../../exchange.html) 提供真实的套装兑换数据。

> 采集工作已完成（AQ20 / AQ40 / Naxx T3 共 304 件），插件已从游戏插件目录移出并归档在此。

---

## 目录内容

| 路径 | 说明 |
|---|---|
| `SoDShopDumper.toc` / `SoDShopDumper.lua` | 插件本体（Interface 11509） |
| `README.md` | 插件使用说明（原始版） |
| `dump/account-*.lua` | 各账号的 `SavedVariables` 原始落盘数据 |
| `dump/exchange-cost-map.json` | 合并整理后的兑换数据（装备 itemID → 材料 itemID + 数量） |

## 插件做了什么

与 NPC 商人对话、**商店窗口一打开就自动记录**：

- 商品：itemID / 名称 / 链接 / 价格（铜）/ 堆叠 / 库存 / 是否可用
- 兑换材料：走 `GetMerchantItemCostInfo` + `GetMerchantItemCostItem`，记材料 ID、数量、名称
- 归档：**服务器 → 角色 → 商人** 三级隔离，重复访问只合并、不覆盖

命令：`/sdd`（总览）、`/sdd here`、`/sdd list`、`/sdd ui`（导出窗口）、`/sdd api`（诊断）、`/sdd clear yes`。

设计上**完全自包含**：不依赖、不修改、不借道任何其它插件。

## 数据如何回流到站点

1. 退出游戏（或 `/reload`）后，`WTF\Account\<账号>\SavedVariables\SoDShopDumper.lua` 落盘
2. 解析多个账号的落盘文件 → 按装备 itemID 合并兑换材料（跨账号跨角色校验一致性）
3. 结果写入 `exchange.html` 的 `EXCHANGE_COST` 表，按「副本 → 套装」分组

当前已接入：**纳克萨玛斯 T3 20/23 套、安其拉神殿 AQ40 20/23 套、安其拉废墟 AQ20 8/9 套**。
尚缺的均为圣骑士套装（需圣骑士角色采集）。

## 如何恢复使用

把本目录下的 `SoDShopDumper.toc` 与 `SoDShopDumper.lua` 复制回：

```
<WoW 安装目录>\_classic_era_\Interface\AddOns\SoDShopDumper\
```

进游戏勾选启用即可（原有存档数据在 `dump/` 里，插件本身的 `SavedVariables` 也会重新生成）。
