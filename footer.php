<?php if (!defined('ABSPATH')) exit; ?>
</main><!-- /.site-main -->

<footer class="site-footer">
  <div class="st-wrap">
    <?php
    // 聯絡資訊走 ACF 設定頁（Task 3），未填值時整區不輸出——
    // 空殼區塊比沒有區塊更難看，而且會讓人以為壞掉了。
    $tel  = function_exists('st_opt') ? st_opt('contact_tel') : '';
    $addr = function_exists('st_opt') ? st_opt('contact_address') : '';
    if ($tel || $addr) :
    ?>
      <div class="site-footer__contact">
        <?php if ($tel) : ?>
          <a href="tel:<?php echo esc_attr(preg_replace('/[^0-9+]/', '', $tel)); ?>"><?php echo esc_html($tel); ?></a>
        <?php endif; ?>
        <?php if ($addr) : ?>
          <p><?php echo esc_html($addr); ?></p>
        <?php endif; ?>
      </div>
    <?php endif; ?>

    <p class="site-footer__copy">
      &copy; <?php echo esc_html(date('Y')); ?> <?php bloginfo('name'); ?>
    </p>
  </div>
</footer>

<?php wp_footer(); ?>
</body>
</html>
