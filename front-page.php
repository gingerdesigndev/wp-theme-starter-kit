<?php
/**
 * 首頁。區塊由 template-parts/ 組起來（Task 4 掛上）。
 *
 * 為什麼首頁不吃編輯器內容：本主題的首頁版面是設計稿切出來的固定結構，
 * 可變的只有文案與圖片，那些走 ACF。讓首頁吃編輯器內容會讓兩套版面打架。
 */
if (!defined('ABSPATH')) exit;

get_header();

// Task 4 會在這裡掛上 template-parts。

get_footer();
