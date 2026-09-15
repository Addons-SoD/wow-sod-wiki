/* 站点级公共逻辑（全部页面共用）-------------------------------------------------
 * 1) 版本号：唯一维护点是 assets/version.json（不再从样式表链接的 ?v= 里"抠"版本号）
 * 2) 数据文件：多源并行竞速 + 版本校验 + 旧数据兜底
 * 3) 图片资源：多 CDN 探测回退（bg.jpeg / logo.png）
 * 4) 页脚版本徽章：写入所有 [data-version] 元素
 *
 * 背景与成因：GitHub Pages 到国内线路对本站大文件极慢（实测 loot-data.json 压缩后
 * 539KB，60 秒仅下到 320KB 就断），而同一文件在 jsDelivr 的 gcore 节点 2.3 秒完成，
 * 图片同理。所以数据与图片一律「CDN 优先、同源兜底」。
 */
"use strict";

var SoDSite = (function () {
  var REPO = "Addons-SoD/wow-sod-wiki";

  /* CDN 引用用「具体 commit hash」而不是 @main：jsDelivr 对分支引用的解析有数小时延迟
     （purge 只清文件缓存，清不掉它内部的 分支→commit 映射），换成 hash 才能保证发版后
     CDN 立刻拿到新数据。发布脚本 publish.ps1 在提交数据后会替换下面这个 hash。 */
  var DATA_REF = "27e0085";

  /* 图片用 @main：图片不随每次发版变化，没必要跟着数据 hash 走。 */
  var IMG_REF = "main";

  var DATA_TIMEOUT = 15000;    /* 数据文件：每源最长等待 */
  var VERSION_TIMEOUT = 5000;  /* 版本号：每源最长等待 */
  var IMG_TIMEOUT = 6000;      /* 图片探测：每源最长等待 */
  var STALE_GRACE = 2500;      /* 拿到「版本略旧」的数据后，等版本正确源的宽限期 */

  /* 两个 jsDelivr 节点（实测 gcore 最快，主域作备用） */
  var CDN_HOSTS = ["gcore.jsdelivr.net", "cdn.jsdelivr.net"];

  function cdnRoot(host, ref) {
    return "https://" + host + "/gh/" + REPO + "@" + ref;
  }

  /* 数据文件的多源候选：两个 jsDelivr 节点（指向数据提交的 hash）+ 本站同源 */
  function dataUrls(file) {
    var out = [], i;
    for (i = 0; i < CDN_HOSTS.length; i++) out.push(cdnRoot(CDN_HOSTS[i], DATA_REF) + "/assets/" + file);
    out.push("assets/" + file);
    return out;
  }

  /* 静态图片的多源候选：两个 jsDelivr 节点 + 本站同源 */
  function imageUrls(rel) {
    var out = [], i;
    for (i = 0; i < CDN_HOSTS.length; i++) out.push(cdnRoot(CDN_HOSTS[i], IMG_REF) + "/" + rel);
    out.push(rel);
    return out;
  }

  function newCtrl() {
    return (typeof AbortController !== "undefined") ? new AbortController() : null;
  }

  function abortAll(list) {
    for (var i = 0; i < list.length; i++) { try { list[i].abort(); } catch (e) {} }
  }

  function fetchJson(url, ctrl) {
    return fetch(url, { cache: "no-store", signal: ctrl ? ctrl.signal : undefined })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); });
  }

  /* ---------- 版本号：读配置文件，结果缓存 ----------
     版本号代表「当前线上站点的版本」，所以同源优先：Pages 上的 version.json 永远对应最新
     提交，而页面本身已经从同源加载过 HTML/CSS/JS，连接已建立，这个请求是毫秒级的。
     CDN 的 @main 分支引用有数小时解析延迟、@DATA_REF 又只对应「数据那次提交」，
     两者都可能在发版后返回旧值，因此只作同源失败时的兜底。 */
  var verPromise = null;

  function siteVersionUrls() {
    var urls = ["assets/version.json"];
    for (var i = 0; i < CDN_HOSTS.length; i++) urls.push(cdnRoot(CDN_HOSTS[i], "main") + "/assets/version.json");
    return urls;
  }

  function version() {
    if (verPromise) return verPromise;
    verPromise = new Promise(function (resolve) {
      var urls = siteVersionUrls();
      var i = 0;
      (function next() {
        if (i >= urls.length) { resolve(""); return; }
        var url = urls[i++];
        var ctrl = newCtrl();
        var timer = setTimeout(function () { if (ctrl) ctrl.abort(); next(); }, VERSION_TIMEOUT);
        fetchJson(url, ctrl)
          .then(function (d) { clearTimeout(timer); resolve(d && d.version ? String(d.version) : ""); })
          .catch(function () { clearTimeout(timer); next(); });
      })();
    });
    return verPromise;
  }

  /* ---------- 数据文件：并行竞速 + 版本校验 + 旧数据兜底 ----------
     三个源同时发请求，第一个「版本校验通过」的胜出，其余立即中止。
     若所有源都失败、或版本都不符，则退回「版本不符但内容可用」的那一份，避免白屏
     （CDN 缓存更新有延迟，刚发版后的短时间内会走到这条兜底路径）。 */
  function loadData(file) {
    var ver = version();
    return new Promise(function (resolve, reject) {
      var urls = dataUrls(file);
      var pending = urls.length, settled = false, ctrls = [], stale = null;

      function win(d) {
        if (settled) return;
        settled = true;
        abortAll(ctrls);
        resolve(d);
      }
      function lose() {
        if (settled) return;
        if (--pending <= 0) {
          settled = true;
          if (stale) { resolve(stale); return; }   /* 兜底：旧数据也好过打不开 */
          reject(new Error("所有数据源均不可用"));
        }
      }

      urls.forEach(function (url) {
        var ctrl = newCtrl();
        if (ctrl) ctrls.push(ctrl);
        var timer = setTimeout(function () { if (ctrl) ctrl.abort(); lose(); }, DATA_TIMEOUT);
        fetchJson(url, ctrl)
          .then(function (d) {
            return ver.then(function (V) {
              clearTimeout(timer);
              var v = (d && d.meta && d.meta.wiki_version) || "";
              /* 只在数据自带版本号时校验：符文数据等历史文件没有该字段，不能误判成旧数据 */
              if (V && v && v !== V) {
                if (!stale) {
                  stale = d;
                  /* 已经拿到「版本略旧但可用」的数据。给版本正确的源一个宽限期：正常发版时
                     它们 2 秒级就胜出；若是「只改页面、没重出数据」的发版，宽限到期后直接用
                     这份数据，不让用户干等 15 秒超时。 */
                  setTimeout(function () {
                    if (settled || !stale) return;
                    settled = true;
                    abortAll(ctrls);
                    resolve(stale);
                  }, STALE_GRACE);
                }
                throw new Error("数据版本 " + v + " 与站点 " + V + " 不符");
              }
              win(d);
            });
          })
          .catch(function () { clearTimeout(timer); lose(); });
      });
    });
  }

  /* ---------- 图片：按候选顺序探测，第一个能解码的胜出 ---------- */
  function probeImage(urls, onWin) {
    var i = 0;
    (function next() {
      if (i >= urls.length) return;
      var url = urls[i++];
      var img = new Image();
      var done = false;
      var timer = setTimeout(function () { if (done) return; done = true; next(); }, IMG_TIMEOUT);
      img.onload = function () { if (done) return; done = true; clearTimeout(timer); onWin(url); };
      img.onerror = function () { if (done) return; done = true; clearTimeout(timer); next(); };
      img.src = url;
    })();
  }

  /* ---------- 页脚版本徽章 ---------- */
  function paintBadges(text) {
    var els = document.querySelectorAll("[data-version]");
    for (var i = 0; i < els.length; i++) els[i].textContent = text;
  }

  function initVersionBadge() {
    if (!document.querySelector("[data-version]")) return;
    paintBadges("v…");
    version().then(function (v) { paintBadges("v" + (v || "?")); });
  }

  /* ---------- 图标（favicon）：HTML 里写同源，CDN 可用时升级过去 ---------- */
  function initFavicon() {
    var link = document.querySelector('link[rel~="icon"]');
    if (!link) return;
    var urls = imageUrls("assets/logo.png");
    probeImage(urls.slice(0, urls.length - 1), function (url) { link.setAttribute("href", url); });
  }

  /* ---------- 背景图：主源已在 style.css 里指向 CDN，这里负责失败回退 ----------
     背景挂在 body::before 伪元素上，没法直接写内联样式，所以用 CSS 变量 --bg-image 覆盖。 */
  function initBackground() {
    probeImage(imageUrls("assets/bg.jpeg"), function (url) {
      document.documentElement.style.setProperty("--bg-image", 'url("' + url + '")');
    });
  }

  function init() {
    initVersionBadge();
    initFavicon();
    initBackground();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  return {
    DATA_REF: DATA_REF,
    version: version,
    loadData: loadData,
    dataUrls: dataUrls,
    imageUrls: imageUrls,
    probeImage: probeImage
  };
})();
