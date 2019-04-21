最近再用cocoapod来取代码时，发现速度很慢。需要为终端配置HTTP代理来解决这个问题。
只需要为Shell设置两个环境变量
```
$:export HTTP_PROXY=代理地址
$:export HTTPS_PROXY=代理地址
```
首页要有VPN，才能访问受限的网站，VPN修改操作系统的网络代理指向它自己，所以上面命令的作用是
终端的网络代理指向VPN，代理地址要去自己的VPN中找。

### 自动启动
我们每次启动VPN时，它会自动修改操作系统的网络代理指向它自己。不需要手动配置，很是方便。
我们让终端也实现这样的功能

#### 打开终端启动
把代理服务器地址写入shell配置文件`.bashrc`或者`.zshrc`，这样再次打开终端后就自动写入了。

#### 开机启动
写入shell配置文件`.bash_profile`

####  Shell 函数启动
需要函数定义在主目录下的 `.profile`文件，这样可以从终端调用函数，每次登录后，在命令提示符后面输入
函数名字就可以调用
```
# http proxy util
hp() {
  if [ "$1" = "enable" ]
  then
    PORT="51350"
    if [ -n "$2" ]
    then
      PORT="$2"
    fi

    export HTTP_PROXY=http://127.0.0.1:$PORT
    export HTTPS_PROXY=http://127.0.0.1:$PORT
  else
    export HTTP_PROXY=""
    export HTTPS_PROXY=""
  fi
}
```
需要开启的时候执行`hp enable`即可，也可指定代理端口号`hp enable 51353`，关闭执行`hp`即可。

### MAC 设置环境变量PATH
mac系统环境变量，加载顺序为：
`/etc/profile  ->  /etc/paths  ->  ~/.bash_profile  ->  ~/.bash_login  ->  ~/.profile  ->  ~/.bashrc`

前两个是系统级别的，系统启动就会加载，后面几个是当前用户级的环境变量。后面三个按照从前往后的顺序去读，
如果`/.bash_profile`文件存在，则后面的几个文件就会被忽略不读了，如果`/.bash_profile`文件
不存在，才会依次类推读取后面的文件。`~/.bashrc`没有上述规则，它是bash shell打开的时候载入的。

PATH的语法如下：
```
export PATH=$PATH:<PATH:1>:<PATH 2>:<PATH 3>:------:<PATH N>
```
etc下的配置是针对系统,~下的主要是针对用户
* /etc/profile （建议不修改这个文件）
全局（公有）配置，不管是哪个用户，登录时都会读取该文件
* /etc/paths （全局建议修改这个文件）
编辑paths，将环境变量添加到paths文件中，一行一个路径
* /etc/bashrc （一般在这个文件中添加系统级环境变量）
全局（共有）配置，bash shell执行时，不管是何种方式，都会读取此文件
* ./bash_profile
该文件包含专用于登录用户的bash shell的bash信息，当登录时以及每次打开新的shell时，
该文件被读取。**需要重启才会生效**
* .profile
文件为系统的每个用户设置环境信息，当用户第一次登录时，该文件被执行，并从`/etc/profile.d`
目录的配置文件中搜集shel的设置。
**使用注意**：如果对`/etc/profile`有修改的话必须得重启修改才生效，此修改对每个用户有效
* ./bashrc
每一个运行bash shell的用户执行此文件，当bash shell被打开时，此文件被读取。
**修改这个文件不用重启，重新打开一个bash shell即生效**

`source ./.bash_profile` 或者 ``./.profile` 环境信息生效

### Shell
操作系统可以分成核心（kernel）和shell（外壳）两部分，其中shell是操作系统与外部的主要接口
，位于操作系统的外层，为用户提供与操作系统核心沟通的图层。Shell是一个命令解释器（也是一种应用程序），
处于内核和用户之间，负责把用户的指令传递给内核并且把执行结果回显给内核。
Shell分为图形界面shell和命令行shell，不同的操作系统有不同的shell。

#### bash
是shell的一种实现。

### 参考资料
[利用蓝灯为命令行配置HTTP代理](https://loveky.github.io/2018/07/05/config-lantern-as-shell-proxy/)
[让终端走代理的几种方法](https://blog.fazero.me/2015/09/15/%E8%AE%A9%E7%BB%88%E7%AB%AF%E8%B5%B0%E4%BB%A3%E7%90%86%E7%9A%84%E5%87%A0%E7%A7%8D%E6%96%B9%E6%B3%95/)
[MAC 设置环境变量PATH 和 查看PATH](https://www.jianshu.com/p/acb1f062a925)
[shell，cmd，dos，脚本语言之间的关系](https://juejin.im/post/59f1a8186fb9a0452935fd29)
