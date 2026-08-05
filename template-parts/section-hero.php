<?php
/**
 * 區塊：首頁 Hero
 *
 * 結構：滿版底圖 + 標題 + 副標 + CTA 按鈕
 * 沿用：.st-wrap（內容開版）、.st-cta（按鈕）
 * 維護：文案與圖片都在後台「網站設定 → 首頁 Hero」，改字不用動程式碼
 * TODO：Figma 上的裝飾線條尚未實作（刻意略過，非漏做）
 *
 * ── 紀律示範 1：ACF 讀值一律走 st_opt()，不直接呼叫 get_field()
 * ── 紀律示範 2：沒有標題就整區不輸出（空殼區塊比沒有區塊更糟）
 */
if (!defined('ABSPATH')) exit;

$title = st_opt('hero_title');
$sub   = st_opt('hero_subtitle');
$image = st_opt('hero_image');
$cta_t = st_opt('hero_cta_text');
$cta_u = st_opt('hero_cta_url');

// 標題是這一區的必要條件；沒有它，整區不輸出。
if (!$title) return;
?>
<section class="st-hero" <?php if (!empty($image['url'])) : ?>style="background-image:url('<?php echo esc_url($image['url']); ?>')"<?php endif; ?>>
  <div class="st-wrap">
    <h1 class="st-hero__title"><?php echo esc_html($title); ?></h1>
    <?php if ($sub) : ?>
      <p class="st-hero__sub"><?php echo esc_html($sub); ?></p>
    <?php endif; ?>
    <?php if ($cta_t && $cta_u) : ?>
      <a class="st-cta" href="<?php echo esc_url($cta_u); ?>"><?php echo esc_html($cta_t); ?></a>
    <?php endif; ?>
  </div>
</section>
