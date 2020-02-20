#!/bin/bash
mkdir -p /magento
cp -a /var/www/magento/* /magento
chown -R www-data:www-data /magento
php-fpm -F
