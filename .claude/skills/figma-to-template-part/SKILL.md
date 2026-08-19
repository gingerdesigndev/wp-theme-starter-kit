---
name: figma-to-template-part
description: 把 Figma 設計稿切成古典 PHP 主題的 template-part（PHP + ACF）。當使用者說「切版」、「切這塊」、「把這個 Figma 切出來」、「新增區塊」、「照設計稿做一個 XXX 區」，或貼出 Figma Dev Mode 連結時使用。即使只丟一個連結說「這塊幫我做」而沒提到切版，只要意圖是「把設計稿變成主題的版面區塊」就應觸發。不適用於頁面建構器拉版、純 CSS 微調、開站與部署。
---

# Figma → template-part 切版

**正文在 `docs/01-切版SOP.md`，動手前完整讀一遍。**

這支 skill 只負責觸發；所有判準、流程、踩坑都在那份文件裡，
不要在這裡重複——重複兩份一定會漂移。

## 開始前先確認

- 讀過 `design-system.md`（知道有哪些 token）
- 手上有 Figma Dev Mode link
