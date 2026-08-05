<?php
/**
 * 版型回退檔。WordPress 規定主題必須有這支。
 * 實際情境各有專屬版型（front-page / page / single / archive / 404），
 * 走到這裡代表是沒被上述版型接住的情況。
 */
if (!defined('ABSPATH')) exit;

get_header();
?>
<div class="st-wrap">
  <?php if (have_posts()) : while (have_posts()) : the_post(); ?>
    <article <?php post_class(); ?>>
      <h2><a href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
      <?php the_excerpt(); ?>
    </article>
  <?php endwhile; else : ?>
    <p>目前沒有內容。</p>
  <?php endif; ?>
</div>
<?php
get_footer();
