<?php
/**
 * 區塊：三欄卡片
 *
 * 結構：區塊標題 + 卡片網格（欄數由 auto-fit 自己降，不開 media query）
 * 沿用：.st-wrap、.st-card
 * 維護：卡片內容在後台「網站設定 → 卡片區」，可自由增減列數
 *
 * ── 紀律示範 3：「要不要顯示」的判斷只呼叫 st_has_cards()，不在這裡另外加條件
 */
if (!defined('ABSPATH')) exit;

$items = st_has_cards();
if (!$items) return;   // 沒有任何有標題的卡片 → 整區不輸出

$heading = st_opt('cards_heading');
?>
<section class="st-cards">
  <div class="st-wrap">
    <?php if ($heading) : ?>
      <h2 class="st-cards__heading"><?php echo esc_html($heading); ?></h2>
    <?php endif; ?>
    <div class="st-cards__grid">
      <?php foreach ($items as $item) : ?>
        <article class="st-card">
          <?php if (!empty($item['image']['url'])) : ?>
            <img class="st-card__thumb"
                 src="<?php echo esc_url($item['image']['url']); ?>"
                 alt="<?php echo esc_attr($item['title']); ?>"
                 width="400" height="300" loading="lazy" />
          <?php endif; ?>
          <h3 class="st-card__title"><?php echo esc_html($item['title']); ?></h3>
          <?php if (!empty($item['body'])) : ?>
            <p class="st-card__body"><?php echo esc_html($item['body']); ?></p>
          <?php endif; ?>
        </article>
      <?php endforeach; ?>
    </div>
  </div>
</section>
