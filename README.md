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
要运行PHP应用程序，需要理解Nginx与PHP-FPM的工作机制。对于静态文件，作为Web服务器的Nginx可以直接处理；当涉及到动态文件，Nginx会启动PHP解析器，解析器按照指定的协议如FastCGI，将处理后的结果按照格式返回，而PHP-FPM就是FastCGI协议的实现。整个Web请求简单地概览如下：

![PHP Web Flow](document/php_web_flow.png)

### 架构设计
我们先来看一下整个项目的架构设计，如图：

![PHP Container](document/php_container.png)

其中各个模块的作用如下：
- Gateway：网关，对外暴露端口提供服务
- Nginx Container：Nginx容器，作为Magento项目的Web服务器
- PHP-FPM Container：PHP-FPM容器，作为Magento项目的PHP解析器
- Code Container：代码容器，存放Magento项目代码
- Code Volume：代码存储卷，为Nginx容器和PHP-FPM容器提供代码文件
- MySQL Container：MySQL容器，为Magento项目提供数据存储能力
