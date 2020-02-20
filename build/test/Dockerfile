FROM magento/magento-cloud-docker-php:7.2-fpm

ARG MAGENTO_VERSION=2.3.4
RUN sed -i "s/!PHP_MEMORY_LIMIT!/${PHP_MEMORY_LIMIT}/" /usr/local/etc/php/conf.d/zz-magento.ini

COPY start.sh start.sh
RUN chmod +x start.sh
CMD ["sh", "start.sh"]  
