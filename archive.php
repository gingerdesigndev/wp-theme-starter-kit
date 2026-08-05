<?php
/**
 * 彙整頁（分類／標籤／日期）。
 *
 * 分類清單一律讀 WordPress 的真實分類，不要硬編設計稿上那份。
 * 曾有案例踩過：設計稿列了 12 個分類，站上實際只有 4 個對得上，
 * 硬編會產生一半是死連結的 tab。
 */
if (!defined('ABSPATH')) exit;

get_header();
?>
<div class="st-archive">
  <div class="st-wrap">
    <h1 class="st-archive__title"><?php the_archive_title(); ?></h1>
    <div class="st-archive__grid">
      <?php if (have_posts()) : while (have_posts()) : the_post(); ?>
        <article class="st-card">
          <a href="<?php the_permalink(); ?>">
            <?php if (has_post_thumbnail()) the_post_thumbnail('medium', ['class' => 'st-card__thumb']); ?>
            <h2 class="st-card__title"><?php the_title(); ?></h2>
          </a>
        </article>
      <?php endwhile; else : ?>
        <p>這個分類還沒有文章。</p>
      <?php endif; ?>
    </div>
    <?php the_posts_pagination(['mid_size' => 1]); ?>
  </div>
</div>
<?php
get_footer();
