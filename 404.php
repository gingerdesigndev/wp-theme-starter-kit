<?php
/**
 * 找不到頁面。
 */
if (!defined('ABSPATH')) exit;

get_header();
?>
<div class="st-404">
  <div class="st-wrap st-measure">
    <h1 class="st-404__title">找不到這個頁面</h1>
    <p>網址可能已經變更或輸入有誤。你可以用下面的搜尋，或回到首頁。</p>
    <?php get_search_form(); ?>
    <p><a class="st-cta" href="<?php echo esc_url(home_url('/')); ?>">回首頁</a></p>
  </div>
</div>
<?php
get_footer();
