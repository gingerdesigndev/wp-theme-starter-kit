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

/* ---------- 3) 安全讀值：版型檔一律走這支，不要直接呼叫 get_field() ---------- */
/**
 * 讀「網站設定」設定頁的欄位，附兩層保險。
 *
 * 1. ACF 被停用時 get_field() 根本不存在，直接呼叫會 fatal、整站白畫面。
 *    客戶站的外掛不是我們控制的，這層保險必須有。
 * 2. 值為空時回退 $fallback——acf-json 只把「欄位定義」帶進 git，欄位「值」
 *    存在各站自己的 wp_options。剛部署到新環境、還沒進後台填值時一律是空的。
 *
 * @param string $name     欄位名稱
 * @param mixed  $fallback 值為空時回傳什麼
 * @return mixed
 */
if (!function_exists('st_opt')) {
    function st_opt($name, $fallback = '') {
        if (!function_exists('get_field')) return $fallback;
        $value = get_field($name, 'option');
        return ($value === null || $value === false || $value === '') ? $fallback : $value;
    }
}

/* ---------- 4) ACF：註冊「網站設定」設定頁 ---------- */
/*
 * 為什麼用 PHP 註冊、不在後台點：
 * 設定頁面的「存在」屬於主題骨架，該跟主題一起進 git、一起 deploy。
 * 後台建的設定頁面存在 DB，換環境就得重設一次。
 *
 * 三層分工，別搞混：
 *   骨架（設定頁存在）→ 程式碼   ← 這裡
 *   欄位定義（有哪些欄位）→ acf-json/  ← 後台存檔自動同步，進 git
 *   欄位值（實際填了什麼）→ 各站自己的 DB，不進 git
 *
 * 掛 acf/init 而非 init：acf_add_options_page() 要等 ACF 載入後才存在。
 */
add_action('acf/init', function () {
    if (!function_exists('acf_add_options_page')) return;  // ACF 未啟用時安靜跳過，不讓後台掛掉

    acf_add_options_page([
        'page_title'  => '網站設定',
        'menu_title'  => '網站設定',
        'menu_slug'   => 'site-options',   // ← acf-json 的位置規則要對應這個 slug
        'capability'  => 'edit_posts',     // 編輯者就能改，不必開管理員權限給客戶
        'position'    => 30,
        'redirect'    => false,
    ]);
});

/* ---------- 5) 讓 ACF 欄位群組自動存進 acf-json/ ---------- */
/*
 * ACF 只要主題根有 acf-json/ 就會自動把欄位群組存成 JSON。
 * 目錄必須存在且可寫，否則會安靜地不同步——這是最常見的「欄位定義沒進 git」原因。
 */
add_filter('acf/settings/save_json', function () {
    return get_stylesheet_directory() . '/acf-json';
});
add_filter('acf/settings/load_json', function ($paths) {
    $paths[] = get_stylesheet_directory() . '/acf-json';
    return $paths;
});

/* ---------- 6) 共用判斷：卡片區要不要輸出 ---------- */
/**
 * 取首頁卡片區裡真正會被輸出的卡片（標題留白的列不算）。
 *
 * ⚠️ **這條判斷必須只有一份。** template-parts/section-cards-3col.php 用它決定
 * 整區輸不輸出，任何「要不要顯示卡片區」的地方都必須呼叫它，不可各自加條件。
 *
 * 曾在某個客戶的正式站踩過：兩處各判各的，本機（有資料）看起來完全正常，
 * 正式站（資料是空的）變成「連結指向一個根本沒被輸出的錨點」，點了沒反應。
 * 要改判斷條件請改這裡。
 *
 * @return array 過濾後的卡片列；空陣列代表這一區不會出現
 */
if (!function_exists('st_has_cards')) {
    function st_has_cards() {
        $items = st_opt('cards', []);
        if (!is_array($items)) return [];
        return array_values(array_filter($items, function ($row) {
            return is_array($row) && trim((string) ($row['title'] ?? '')) !== '';
        }));
    }
}
