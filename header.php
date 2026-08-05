<?php if (!defined('ABSPATH')) exit; ?>
<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
  <meta charset="<?php bloginfo('charset'); ?>">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>

<header class="site-header">
  <a class="site-logo" href="<?php echo esc_url(home_url('/')); ?>">
    <?php
    // Logo 走 ACF（Task 3 接上），還沒填值時退回站名文字，
    // 確保剛部署到新環境、後台什麼都還沒填時，header 仍是可用的。
    $logo = function_exists('st_opt') ? st_opt('site_logo') : '';
    if (!empty($logo['url'])) :
    ?>
      <img src="<?php echo esc_url($logo['url']); ?>"
           alt="<?php echo esc_attr(get_bloginfo('name')); ?>"
           width="<?php echo esc_attr($logo['width'] ?? 200); ?>"
           height="<?php echo esc_attr($logo['height'] ?? 60); ?>" />
    <?php else : ?>
      <span class="site-logo__text"><?php echo esc_html(get_bloginfo('name')); ?></span>
    <?php endif; ?>
  </a>

  <?php wp_nav_menu([
    'theme_location'  => 'primary',
    'container'       => 'nav',
    'container_class' => 'site-nav',
    'menu_class'      => 'site-menu',
    'fallback_cb'     => false,   // 沒指派選單時什麼都不輸出，不要用 WP 的頁面清單湊
    'depth'           => 2,
  ]); ?>
</header>

<main class="site-main">
