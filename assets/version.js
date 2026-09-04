/* 版本号加载器
 * 版本号唯一维护点：assets/version.json（{"version": "x.y.z"}）
 * 本脚本每次以 cache: "no-store" 强制拉取最新版本，避免浏览器缓存旧值，
 * 并将 "v版本号" 写入页面上所有带 data-version 的元素（页脚徽章）。
 * 升版只需修改 version.json，页面无需改动。
 */
(function () {
  var els = document.querySelectorAll("[data-version]");
  if (!els.length) return;
  function set(text) {
    for (var i = 0; i < els.length; i++) {
      els[i].textContent = text;
    }
  }
  set("v…");
  fetch("assets/version.json", { cache: "no-store" })
    .then(function (r) { return r.json(); })
    .then(function (d) { set("v" + (d && d.version ? d.version : "?")); })
    .catch(function () { set("v?"); });
})();
