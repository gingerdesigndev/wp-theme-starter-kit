<?php
/**
 * 單篇文章。
 */
if (!defined('ABSPATH')) exit;

get_header();
?>
<article class="st-single">
  <div class="st-wrap">
    <?php while (have_posts()) : the_post(); ?>
      <h1 class="st-single__title"><?php the_title(); ?></h1>
      <p class="st-single__meta"><time datetime="<?php echo esc_attr(get_the_date('c')); ?>"><?php echo esc_html(get_the_date()); ?></time></p>
      <?php if (has_post_thumbnail()) the_post_thumbnail('large', ['class' => 'st-single__thumb']); ?>
      <div class="st-single__body st-measure"><?php the_content(); ?></div>
    <?php endwhile; ?>
  </div>
</article>
<?php
get_footer();
