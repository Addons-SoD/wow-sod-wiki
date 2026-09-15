/* 站点公共工具（loot.html / exchange.html / runes.html 共用）
 * 抽离自三个页面的重复内联代码：DOM 取值、HTML 转义、品质与职业映射、图标渲染、物品 tooltip。
 * 保留原有全局函数名，页面内的调用点无需改动。
 * 依赖页面在数据加载完成后设置的全局变量：ICON_TPL / ICON_TPL_NUM（图标地址模板）、DATA。
 */
"use strict";

var QUAL_ZH = { 0: "粗糙", 1: "普通", 2: "精良", 3: "稀有", 4: "史诗", 5: "传说", 6: "神器" };
var CLASS_ZH = {
  Warrior: "战士", Paladin: "圣骑士", Hunter: "猎人", Rogue: "潜行者", Priest: "牧师",
  Shaman: "萨满祭司", Mage: "法师", Warlock: "术士", Druid: "德鲁伊"
};

function $(id) { return document.getElementById(id); }

function esc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function qOf(q) { return q == null ? 1 : q; }

/* 图标地址模板由数据文件 meta 提供，页面加载数据后写入全局 ICON_TPL / ICON_TPL_NUM */
function iconUrl(it) {
  if (!it) return "";
  if (it.ic) return (window.ICON_TPL || "").replace("%s", it.ic);
  if (it.icn) return (window.ICON_TPL_NUM || "").replace("%s", it.icn);
  return "";
}

function clsZh(s) {
  if (!s) return "";
  return s.split(",").map(function (x) {
    x = x.trim();
    return CLASS_ZH[x] || x;
  }).join(" / ");
}

function iconImg(it, cls) {
  var u = iconUrl(it);
  if (!u) return '<span class="' + cls + '" style="display:inline-block"></span>';
  return '<img class="' + cls + ' q' + qOf(it.q) + '" src="' + esc(u) + '" alt="" loading="lazy" onerror="this.style.visibility=\'hidden\'" />';
}

function itemById(id) { return window.DATA.items[String(id)]; }

/* ---------- 物品 tooltip ---------- */
function buildTip(it, rate) {
  var q = qOf(it.q);
  var h = '<div class="ti">' + iconImg(it, "b" + q);
  h += '<div><div class="nm q' + q + '">' + esc(it.n) + '</div>';
  h += '<div class="qlabel q' + q + '">' + esc(QUAL_ZH[q] || "普通") + '</div></div></div>';
  if (it.bd) h += '<div class="row muted">' + esc(it.bd) + '</div>';
  if (it.cl) h += '<div class="row muted">职业：' + esc(clsZh(it.cl)) + '</div>';
  if (it.il) h += '<div class="row itemLevel">物品等级 ' + esc(it.il) + '</div>';
  h += '<div class="hr"></div>';
  var head = [it.sl, it.tp].filter(Boolean).join(" · ");
  if (head) h += '<div class="row muted">' + esc(head) + '</div>';
  if (it.wp) {
    // 伤害 / 速度 / 每秒伤害 分三行展示
    it.wp.split(" / ").forEach(function (seg) {
      if (!seg) return;
      var cls = seg.indexOf("每秒伤害") >= 0 ? "row muted" : "row";
      h += '<div class="' + cls + '">' + esc(seg) + '</div>';
    });
  }
  if (it.ar) h += '<div class="row">' + esc(it.ar) + '</div>';
  if (it.st && it.st.length) {
    h += '<div class="hr"></div>';
    it.st.forEach(function (s) { h += '<div class="row stat">' + esc(s) + '</div>'; });
  }
  if (it.ef && it.ef.length) {
    h += '<div class="hr"></div>';
    it.ef.forEach(function (s) { h += '<div class="row effect">' + esc(s) + '</div>'; });
  }
  if (it.sn || (it.se && it.se.length)) {
    // 套装：名称 + 各件数档位的组合效果（英雄榜用粉紫色）
    h += '<div class="hr"></div>';
    if (it.sn) h += '<div class="row spec">' + esc(it.sn) + '</div>';
    if (it.se) it.se.forEach(function (s) { h += '<div class="row spec">' + esc(s) + '</div>'; });
  }
  if (it.du) h += '<div class="row muted">' + esc(it.du) + '</div>';
  if (it.mk && it.mk.length) h += '<div class="row itemLevel">' + esc(it.mk.join(" · ")) + '</div>';
  if (it.rl) h += '<div class="row req">需要等级 ' + esc(it.rl) + '</div>';
  if (rate != null && rate !== "") h += '<div class="row muted">掉率：' + esc(rate) + '%</div>';
  if (it.sp) h += '<div class="row req">售价：' + esc(it.sp) + '</div>';
  if (it.ph) h += '<div class="row muted">' + esc(String(it.ph).replace("Phase", "阶段")) + '</div>';
  if (it.ds) h += '<div class="hr"></div><div class="row flavor">“' + esc(it.ds) + '”</div>';
  return h;
}

var tipEl = null, tipVisible = false, curX = 0, curY = 0;
var TIP_OFFSET = 16;

function getTip() {
  if (!tipEl) {
    tipEl = document.createElement("div");
    tipEl.className = "tooltip";
    document.body.appendChild(tipEl);
  }
  return tipEl;
}

function positionTip() {
  var el = tipEl;
  if (!el || !tipVisible) return;
  var r = el.getBoundingClientRect();
  var x = curX + TIP_OFFSET, y = curY + TIP_OFFSET;
  if (x + r.width > window.innerWidth - 8) x = curX - r.width - TIP_OFFSET;
  if (y + r.height > window.innerHeight - 8) y = curY - r.height - TIP_OFFSET;
  if (x < 8) x = 8;
  if (y < 8) y = 8;
  el.style.left = x + "px";
  el.style.top = y + "px";
}

function showTip(html, e) {
  var el = getTip();
  curX = e.clientX; curY = e.clientY;
  el.innerHTML = html;
  el.style.display = "block"; /* 注意：fixed 元素不能用 hidden 属性控制，会退回文档流 */
  el.style.left = "0px";
  el.style.top = "0px";
  tipVisible = true;
  positionTip();
}

function hideTip() {
  if (tipEl) tipEl.style.display = "none";
  tipVisible = false;
}
