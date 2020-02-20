FROM busybox:latest

ARG MAGENTO_VERSION=2.3.4

RUN wget -q "https://github.com/magento/magento2/archive/${MAGENTO_VERSION}.tar.gz" -O "/tmp/magento.tar.gz"
RUN wget -q "https://github.com/magento/magento2-sample-data/archive/${MAGENTO_VERSION}.tar.gz" -O "/tmp/magento-sample.tar.gz"

RUN tar xzf /tmp/magento.tar.gz -C /var/www/ \
  && mv "/var/www/magento2-$MAGENTO_VERSION" /var/www/magento \
  && tar xzf /tmp/magento-sample.tar.gz -C /var/www/magento/ magento2-sample-data-$MAGENTO_VERSION/ \
  && cp -rp /var/www/magento/magento2-sample-data-$MAGENTO_VERSION/* /var/www/magento \
  && rm -rf /var/www/magento/magento2-sample-data-$MAGENTO_VERSION \
  && rm /tmp/magento-sample.tar.gz \
  && rm /tmp/magento.tar.gz

# RUN mkdir -p /data2 \
#   && rm -rf /data2/* \
#   && cp -r /var/www/magento3/* /data2/
# 
# CMD "tail" "-f" "/dev/null"

COPY start.sh start.sh
RUN chmod +x start.sh
# WORKDIR /var/www/magento

CMD "sh" "start.sh"
