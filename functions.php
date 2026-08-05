<?php
/**
 * starter-theme — functions.php
 *
 * 這支檔案只做「每個站都需要」的四件事，不放任何業務邏輯：
 *  1) theme support 與選單註冊
 *  2) 載入 style.css
 *  3) ACF 設定頁註冊        （Task 3）
 *  4) 安全讀值函式          （Task 3）
 *
 * 區塊級的版面請寫在 template-parts/，不要往這裡塞。
 */

if (!defined('ABSPATH')) exit; // 安全：禁止直接存取

/* ---------- 1) Theme Support ---------- */
add_action('after_setup_theme', function () {
    add_theme_support('title-tag');
    add_theme_support('post-thumbnails');
    add_theme_support('html5', ['gallery', 'caption', 'style', 'script']);

    register_nav_menus(['primary' => '主選單']);
});

/* ---------- 2) 載入前台樣式 ---------- */
add_action('wp_enqueue_scripts', function () {
    // 版號用 style.css 的 mtime，不用主題 Version：
    // Version 寫死時改了 CSS 版號不變，瀏覽器會一直吃快取，
    // 開發時會產生「明明改了卻沒生效」的誤判，很耗時間。
    $css_path = get_theme_file_path('style.css');
    $css_ver  = file_exists($css_path) ? filemtime($css_path) : wp_get_theme()->get('Version');
    wp_enqueue_style('starter-theme', get_stylesheet_uri(), [], $css_ver);
});
