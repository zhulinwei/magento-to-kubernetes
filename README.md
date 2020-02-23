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


## 结构设计

### PHP应用工作流程
要运行PHP应用程序，需要理解Nginx与PHP-FPM的工作机制。对于静态文件，作为Web服务器的Nginx可以直接处理；当涉及到动态文件，如index.php时，Nginx会启动PHP解析器，PHP解析器按照指定的协议如FastCGI，将处理后的结果按照格式返回，而PHP-FPM就是FastCGI协议的实现。笔者将整个Web请求简单地概览如下：
![PHP Web Flow](document/php_web_flow.png)

