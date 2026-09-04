/* 全站版本号 —— 唯一维护点
   每次发布更新后，手动把 VERSION 递增（语义化版本）：
   - 内容/修复类小改动：0.0.x 递增
   - 新增页面/栏目等小版本：0.x.0
   - 大改版：x.0.0
   所有页面页脚统一显示此版本号，便于确认刷新是否已加载新版本。 */
(function () {
  var VERSION = "0.0.2";
  var el = document.getElementById("site-version");
  if (el) {
    el.textContent = "v" + VERSION;
  }
})();
