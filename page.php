<?php
/**
 * 一般頁面。吃編輯器內容，套文章寬度（.st-measure）。
 */
if (!defined('ABSPATH')) exit;

get_header();
?>
<article class="st-page">
  <div class="st-wrap">
    <h1 class="st-page__title"><?php the_title(); ?></h1>
    <div class="st-page__body st-measure">
      <?php
      while (have_posts()) {
          the_post();
          the_content();
      }
      ?>
    </div>
  </div>
</article>
<?php
get_footer();
