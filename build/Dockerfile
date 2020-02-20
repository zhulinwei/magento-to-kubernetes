FROM magento/magento-cloud-docker-php:7.2-fpm

ENV PHP_MEMORY_LIMIT 2G
ENV MAGENTO_ROOT /magento

ARG MAGENTO_VERSION=2.3.2-p2

# set php.ini values 
RUN sed -i "s/!PHP_MEMORY_LIMIT!/${PHP_MEMORY_LIMIT}/" /usr/local/etc/php/conf.d/zz-magento.ini 
  # && sed -i "s/!MAGENTO_RUN_MODE!/${MAGENTO_RUN_MODE}/" /usr/local/etc/php-fpm.conf \
  # && pecl install -o -f libsodium \
  # && docker-php-ext-enable sodium

RUN wget -q "https://github.com/magento/magento2/archive/${MAGENTO_VERSION}.tar.gz" -O "/tmp/magento.tar.gz"
RUN wget -q "https://github.com/magento/magento2-sample-data/archive/${MAGENTO_VERSION}.tar.gz" -O "/tmp/magento-sample.tar.gz"

# extract magento tarball + sample data over the top
RUN tar xzf /tmp/magento.tar.gz -C /var/www/ \
  && mv "/var/www/magento2-$MAGENTO_VERSION" /var/www/magento \
  && tar xzf /tmp/magento-sample.tar.gz -C /var/www/magento/ magento2-sample-data-$MAGENTO_VERSION/ \
  && cp -rp /var/www/magento/magento2-sample-data-$MAGENTO_VERSION/* /var/www/magento \
  && rm -rf /var/www/magento/magento2-sample-data-$MAGENTO_VERSION \
  && rm /tmp/magento-sample.tar.gz \
  && rm /tmp/magento.tar.gz

# install composer
RUN curl -sS https://getcomposer.org/installer | php -dmemory_limit=-1 -- --install-dir=/usr/local/bin --filename=composer
# install composer deps
RUN cd /var/www/magento && /usr/local/bin/composer install

RUN echo "user = www-data" >> /usr/local/etc/php-fpm.conf
RUN echo "group = www-data" >> /usr/local/etc/php-fpm.conf

# RUN chown -R www-data:www-data /var/www/magento2
# CMD ["php-fpm", "-F"]
COPY start.sh start.sh
RUN chmod +x start.sh
CMD ["sh", "start.sh"]  
