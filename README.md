# magento-to-kubernetes

## 前言
[Magento](https://magento.com)是一款国外流行的，基于PHP实现的电子商务平台，任何人都开源使用它免费的创建自己的在线商店。本教程将展示如何将Magento容器化并在Kubernetes上运行。

### 基本要求
- 对Nginx语法的基本了解
- 对PHP工作流程的基本了解
- 对Dockerfile指令的基本了解
- 对Kubernetes对象的基本了解


### 先决条件
- 拥有DockerHub账号，用于存放Docker镜像
- 拥有Kubernetes集群，用于编排容器和部署应用

### 可选条件
- 集群部署Istio组件，本教程仅使用Istio功能中的网关服务（没有安装Istio也可以通过ip:port的形式访问服务）

## 设计方案

### 工作流程
> 要运行PHP应用程序，首先需要理解Nginx与PHP-FPM的工作机制

对于静态文件，作为Web服务器的Nginx可以直接处理； 当涉及到动态文件，Nginx会启动PHP解析器，解析器按照指定的协议如FastCGI，将处理后的结果按照格式返回，而PHP-FPM就是FastCGI协议的实现。

整个Web请求简单地概览如下：

![PHP Web Flow](document/php_web_flow.png)

### 架构设计
我们来看一下整个项目的架构设计，如图：

![PHP Container](document/php_container.png)

其中各个模块的作用如下：
- Gateway：网关，对外暴露端口提供服务
- Nginx Container：Nginx容器，作为Magento项目的Web服务器
- PHP-FPM Container：PHP-FPM容器，作为Magento项目的PHP解析器
- Code Container：代码容器，存放Magento项目代码
- Code Volume：代码存储卷，为Nginx容器和PHP-FPM容器提供代码文件
- MySQL Container：MySQL容器，为Magento项目提供数据存储能力

上图为了清晰地展示架构，将项目代码放在Code Container中，但在实际的工作中，我们其实可以将项目代码文件放入Nginx Container或者PHP-FPM Container中，减少打包构建工作。

## 实践过程

### 构建PHP-PFM镜像

我们在这里为了方便起见，采用Magento官方提供的fpm镜像，并将Magento项目代码和fpm打包在同一个镜像中，镜像构建文件Dockerfile如下：

```dockerfile
FROM magento/magento-cloud-docker-php:7.2-fpm
# 设置项目内存限制
ENV PHP_MEMORY_LIMIT 2G
# 设置Magento工作目录
ENV MAGENTO_ROOT /magento
# 设置Magento项目版本
ARG MAGENTO_VERSION=2.3.2-p2

# 设置php.ini参数
RUN sed -i "s/!PHP_MEMORY_LIMIT!/${PHP_MEMORY_LIMIT}/" /usr/local/etc/php/conf.d/zz-magento.ini 

# 拉取Magento项目代码和Sample数据
RUN wget -q "https://github.com/magento/magento2/archive/${MAGENTO_VERSION}.tar.gz" -O "/tmp/magento.tar.gz"
RUN wget -q "https://github.com/magento/magento2-sample-data/archive/${MAGENTO_VERSION}.tar.gz" -O "/tmp/magento-sample.tar.gz"

# 解压并删除压缩包
RUN tar xzf /tmp/magento.tar.gz -C /var/www/ \
  && mv "/var/www/magento2-$MAGENTO_VERSION" /var/www/magento \
  && tar xzf /tmp/magento-sample.tar.gz -C /var/www/magento/ magento2-sample-data-$MAGENTO_VERSION/ \
  && cp -rp /var/www/magento/magento2-sample-data-$MAGENTO_VERSION/* /var/www/magento \
  && rm -rf /var/www/magento/magento2-sample-data-$MAGENTO_VERSION \
  && rm /tmp/magento-sample.tar.gz \
  && rm /tmp/magento.tar.gz

# 安装composer
RUN curl -sS https://getcomposer.org/installer | php -dmemory_limit=-1 -- --install-dir=/usr/local/bin --filename=composer
# 安装项目依赖
RUN cd /var/www/magento && /usr/local/bin/composer install

# 设置用户与分组
RUN echo "user = www-data" >> /usr/local/etc/php-fpm.conf
RUN echo "group = www-data" >> /usr/local/etc/php-fpm.conf

COPY start.sh start.sh
RUN chmod +x start.sh
CMD ["sh", "start.sh"]  
```
为了能让后续Kubernetes提供挂载能力，将项目拷贝到挂载文件夹，故将以下内容放置start.sh脚本中，内容如下：
```shell
#!/bin/bash
mkdir -p /magento
# 将Magento项目文件拷贝到挂载文件夹中
cp -a /var/www/magento/* /magento
# 授权
chown -R www-data:www-data /magento
# 启动php-fpm
php-fpm -F
```
**注意这个/magento文件夹，就是我们上图中提到的Code Volume，后续还会再强调**

使用Docker进行打包和并将镜像推送到仓库中，命令如下：
```shell
docker build -t magento:latest build/
docker tag magento:latest <your_docker_register_path>:<tag>
docker push <your_docker_register_path>:<tag>
```

### 编写Nginx配置
我们使用Magento官方提供的magento-cloud-docker-nginx作为我们的nginx镜像，但是配置还是需要提供的，包括nginx.conf和vhost.conf两个文件，我们都放在configmap中，内容如下：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: magento-nginx-config
  namespace: magento
data:
  nginx.conf: |
    worker_processes 2;
    error_log /var/log/nginx/error.log debug;
    pid /var/run/nginx.pid;
    events {
      # this should be equal to value of "ulimit -n"
      # reference: https://www.digitalocean.com/community/tutorials/how-to-optimize-nginx-configuration
      worker_connections 1048576;
    }
    http {
      include /etc/nginx/mime.types;
      default_type application/octet-stream;
      log_format main
        '$remote_addr - $remote_user [$time_local] "$request" '
        '$status $body_bytes_sent "$http_referer" '
        '"$http_user_agent" "$http_x_forwarded_for"';
      access_log /var/log/nginx/access.log main;
      sendfile on;
      #tcp_nopush on;
      keepalive_timeout 65;
      #gzip on;
      client_max_body_size 20M;
      include /etc/nginx/conf.d/*.conf;
    }
  vhost.conf: |
    map $cookie_XDEBUG_SESSION $my_fastcgi_pass {
      "" fastcgi_backend;
      # default fastcgi_backend_xdebug;
      default fastcgi_backend;
    }
    upstream fastcgi_backend {
      # server magento-app:9000;
      server 127.0.0.1:9000;
    }
    # upstream fastcgi_backend_xdebug {
    #   server !XDEBUG_HOST!:!FPM_PORT!; # Variables: XDEBUG_HOST FPM_PORT
    # }
    server {
      listen 80;
      listen 443 ssl;
      server_name localhost;
      set $MAGE_ROOT /magento;
      # MAGE_MODE options: production or developer
      set $MAGE_MODE developer;
      # MFTF_UTILS options: 0 or !0
      set $MFTF_UTILS 1;
      # Support for SSL termination.
      set $my_http "http";
      set $my_ssl "off";
      set $my_port "80";
      if ($http_x_forwarded_proto = "https") {
        set $my_http "https";
        set $my_ssl "on";
        set $my_port "443";
      }
      ssl_certificate /etc/nginx/ssl/magento.crt;
      ssl_certificate_key /etc/nginx/ssl/magento.key;
      root $MAGE_ROOT/pub;
      index index.php;
      autoindex off;
      charset UTF-8;
      client_max_body_size 64m;
      error_page 404 403 = /errors/404.php;
      #add_header "X-UA-Compatible" "IE=Edge";
     
      location ~* ^/setup($|/) {
        root $MAGE_ROOT;
        location ~ ^/setup/index.php {
          fastcgi_pass   $my_fastcgi_pass;
      
          fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
          fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=600";
          fastcgi_read_timeout 600s;
          fastcgi_connect_timeout 600s;
      
          fastcgi_index  index.php;
          fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
          include        fastcgi_params;
        }
      
        location ~ ^/setup/(?!pub/). {
          deny all;
        }
      
        location ~ ^/setup/pub/ {
          add_header X-Frame-Options "SAMEORIGIN";
        }
      }
      
      # Deny access to sensitive files
      location /.user.ini {
        deny all;
      }
      location / {
        try_files $uri $uri/ /index.php$is_args$args;
      }
      location /pub/ {
        location ~ ^/pub/media/(downloadable|customer|import|theme_customization/.*\.xml) {
          deny all;
        }
        alias $MAGE_ROOT/pub/;
        add_header X-Frame-Options "SAMEORIGIN";
      }
      location /static/ {
        if ($MAGE_MODE = "production") {
          expires max;
        }
        # Remove signature of the static files that is used to overcome the browser cache
        location ~ ^/static/version {
          rewrite ^/static/(version\d*/)?(.*)$ /static/$2 last;
        }
        location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2|json)$ {
          add_header Cache-Control "public";
          add_header X-Frame-Options "SAMEORIGIN";
          expires +1y;
          if (!-f $request_filename) {
            rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=$2 last;
          }
        }
        location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
          add_header Cache-Control "no-store";
          add_header X-Frame-Options "SAMEORIGIN";
          expires    off;
          if (!-f $request_filename) {
            rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=$2 last;
          }
        }
        if (!-f $request_filename) {
          rewrite ^/static/(version\d*/)?(.*)$ /static.php?resource=$2 last;
        }
        add_header X-Frame-Options "SAMEORIGIN";
      }
      location /media/ {
        try_files $uri $uri/ /get.php$is_args$args;
        location ~ ^/media/theme_customization/.*\.xml {
          deny all;
        }
        location ~* \.(ico|jpg|jpeg|png|gif|svg|js|css|swf|eot|ttf|otf|woff|woff2)$ {
          add_header Cache-Control "public";
          add_header X-Frame-Options "SAMEORIGIN";
          expires +1y;
          try_files $uri $uri/ /get.php$is_args$args;
        }
        location ~* \.(zip|gz|gzip|bz2|csv|xml)$ {
          add_header Cache-Control "no-store";
          add_header X-Frame-Options "SAMEORIGIN";
          expires    off;
          try_files $uri $uri/ /get.php$is_args$args;
        }
        add_header X-Frame-Options "SAMEORIGIN";
      }
      location /media/customer/ {
        deny all;
      }
      location /media/downloadable/ {
        deny all;
      }
      location /media/import/ {
        deny all;
      }
      
      location /errors/ {
        location ~* \.xml$ {
          deny all;
        }
      }
      # PHP entry point for main application
      location ~ ^/(index|get|static|errors/report|errors/404|errors/503|health_check)\.php$ {
        try_files $uri =404;
        fastcgi_pass   $my_fastcgi_pass;
        fastcgi_buffers 1024 4k;
        fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
        fastcgi_param  PHP_VALUE "memory_limit=768M \n max_execution_time=18000";
        fastcgi_read_timeout 600s;
        fastcgi_connect_timeout 600s;
        fastcgi_param  MAGE_MODE $MAGE_MODE;
        # Magento uses the HTTPS env var to detrimine if it is using SSL or not.
        fastcgi_param  HTTPS $my_ssl;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
        include        fastcgi_params;
      }
      location ~* ^/dev/tests/acceptance/utils($|/) {
        root $MAGE_ROOT;
        location ~ ^/dev/tests/acceptance/utils/command.php {
          if ($MFTF_UTILS = 0) {
              return 405;
          }
          fastcgi_pass   $my_fastcgi_pass;
          fastcgi_index  index.php;
          fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
          include        fastcgi_params;
        }
      }
      gzip on;
      gzip_disable "msie6";
      gzip_comp_level 6;
      gzip_min_length 1100;
      gzip_buffers 16 8k;
      gzip_proxied any;
      gzip_types
        text/plain
        text/css
        text/js
        text/xml
        text/javascript
        application/javascript
        application/x-javascript
        application/json
        application/xml
        application/xml+rss
        image/svg+xml;
      gzip_vary on;
      # Banned locations (only reached if the earlier PHP entry point regexes don't match)
      location ~* (\.php$|\.htaccess$|\.git) {
        deny all;
      }
    }
```
关于Nginx配置不做过多解释，详情自行学习[Nginx语法](https://www.nginx.com)，这里需要强调的是如果是在Web端初始化Magento项目，setup的配置不可缺：
```yaml
location ~* ^/setup($|/) {
  root $MAGE_ROOT;
  location ~ ^/setup/index.php {
    fastcgi_pass   $my_fastcgi_pass;

    fastcgi_param  PHP_FLAG  "session.auto_start=off \n suhosin.session.cryptua=off";
    fastcgi_param  PHP_VALUE "memory_limit=756M \n max_execution_time=600";
    fastcgi_read_timeout 600s;
    fastcgi_connect_timeout 600s;

    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
    include        fastcgi_params;
  }

  location ~ ^/setup/(?!pub/). {
    deny all;
  }

  location ~ ^/setup/pub/ {
    add_header X-Frame-Options "SAMEORIGIN";
  }
}
```
执行以下命令创建configmap：
```shell
kubectl apply -f deploy/nginx/configmap.yaml
```

### 部署Magento应用

我们将PHP-FMP镜像和Nginx镜像部署在同一个POD中，挂载Nginx配置和共享文件夹，内容如下：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: magento-app
  namespace: magento
  labels:
    app: magento-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: magento-app
  template:
    metadata:
      labels:
        app: magento-app
    spec:
      containers:
      - name: magento-app
        image: <your_magento_image>
        volumeMounts:
        - name: magento-app-stroage
          mountPath: /magento
      - name: magento-nginx
        image: magento/magento-cloud-docker-nginx
        ports:
        - containerPort: 80
        volumeMounts:
        - name: magento-nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: magento-nginx-config
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: vhost.conf
        - name: magento-app-stroage
          mountPath: /magento
      volumes:
      - name: magento-app-stroage
        emptyDir: {}
      - name: magento-nginx-config
        configMap:
          name: magento-nginx-config
```
这里我们使用Kubernetes Volumes中的emptyDir作为挂载卷，并将/magento设置为挂载的路径。emptyDir存储卷虽然不具备数据的持久存储，但非常适合Pod中多个容器共享文件的这种场景。

执行以下命令部署应用：
```shell
kubectl apply -f deploy/magento/deployment.yaml
```

#### 暴露Magento应用端口
```yaml
apiVersion: v1
kind: Service
metadata:
  name: magento-app
  namespace: magento
  labels:
    app: magento-app
spec:
  selector:
    app: magento-app
  ports:
  - name: magento-nginx-port
    port: 80
    protocol: TCP
  type: NodePort
```
执行以下命令部署应用：
```shell
kubectl apply -f deploy/magento/service.yaml
```

### 部署MySQL数据库
> 如果你已经有MySQL数据库并且能提供服务的话，可以跳过该节

#### 存储敏感数据
将MySQL的敏感信息存储于secret对象中，stringData参数包含在创建或更新期间自动编码的未编码数据，并且在检索Secrets时不输出数据，内容如下：

```yaml
apiVersion: v1
kind: Secret
metadata: 
name: magento-mysql-secret
namespace: magento
type: Opaque
stringData: 
  MYSQL_USER: magento-user
  MYSQL_PASSWORD: magento-password
  MYSQL_DATABASE: magento-databse
  MYSQL_ROOT_PASSWORD: magento-root-password
```
执行以下命令创建secrtet对象：
```shell
kubectl apply -f deploy/mysql/secret.yaml
```

#### 部署MySQL应用
我们选取mysql:5.6作为镜像，将MySQL的敏感数据作为变量注入，挂载外部卷作为数据的存储位置并设置POD使用资源的上下限，内容如下：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: 
  name: magento-mysql
  namespace: magento
spec:
  selector:
    matchLabels:
      app: magento-mysql
  template:
    metadata:
      labels:
        app: magento-mysql
    spec:
      containers:
      - name: magento-mysql
        image: mysql:5.6
        ports:
        - name: default-port
          containerPort: 3306
        args: ["--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci"]
        env:
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              key: MYSQL_DATABASE
              name: magento-mysql-secret
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              key: MYSQL_USER
              name: magento-mysql-secret
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              key: MYSQL_PASSWORD
              name: magento-mysql-secret
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              key: MYSQL_ROOT_PASSWORD
              name: magento-mysql-secret
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            cpu: 1000m
            memory: 2000Mi
        volumeMounts:
        - name: magento-mysql-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: magento-mysql-storage
        persistentVolumeClaim:
          claimName: magento-mysql-pvc
```
执行以下命令部署MySQL应用：
```shell
kubectl apply -f deploy/mysql/deploy.yaml
```

#### 暴露MySQL端口
我们暴露3306端口以供外部使用，内容如下：
```yaml
apiVersion: v1
kind: Service
metadata:
  name: magento-mysql-service
  namespace: magento
  labels:
    app: magento-mysql
spec:
  selector:
    app: magento-mysql
  ports: 
  - name: default-port
    port: 3306
    protocol: TCP
  type: NodePort
```
执行以下命令暴露MySQL端口：
```shell
kubectl apply -f deploy/mysql/service.yaml
```

### 配置网关
> 如果你的集群没有安装Istio组件，可以跳过该节

假如你自定义的域名是**your_sample.com**，你希望它能指向你的Magento应用，则需要配置Istio Gateway和Istio VirtualService文件，内容如下：

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: magento-app-gateway
  namespace: magento
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "your_sample.com"
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: magento-app
  namespace: magento
spec:
  host: magento-app
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 2048
      http:
        idleTimeout: 6m
        http1MaxPendingRequests: 2048
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: magento-app
  namespace: magento
spec:
  hosts:
  - "your_sample.com"
  gateways:
  - magento-app-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        port:
          number: 80
        host: magento-app
```
```
执行以下命令配置网关：
```shell
kubectl apply -f deploy/magento/gateway.yaml
```
### 初始化Magento项目

**如果初始化的时间较长，别怕，正常，笔者花了六个小时才等到Magento初始化完成!**

如果你配置了网关，可以在浏览器中输入你自定义的域名your_sample.com；如果没有配置网关，则直接输入集群机器IP，看到以下页面则代表应用部署成功：
![magento](document/magento.png)

点击『Agree and Setup Mangeto』进入下一步，输出MySQL数据库的配置完成项目初始化安装吧
