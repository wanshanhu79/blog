PS：因为这是事后总结，具体的错误当时没有记录，有可能错误与解决方法不匹配。
# bad response Forbidden 403
![bad response Forbidden 403.png](http://upload-images.jianshu.io/upload_images/1388332-797c9cfacf7445ad.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
在 [GitHub-fastlane](https://github.com/fastlane/fastlane)的Issues上找到了答案：
jwt未安装，执行 `gem install jwt`

# Exit status: 错误

![Exit status.png](http://upload-images.jianshu.io/upload_images/1388332-17ddd88dd16ee297.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
关闭自动管理代码签名，手动设置，如下图

![NonAutoManageSign.png](http://upload-images.jianshu.io/upload_images/1388332-46f015ad3b0b108c.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

### 2017、8、4更新
使用 “自动管理代码签名” ：Exit status ： 70
找到官方文档，如下配置

![4A06EAA3-6B3A-411D-B9C4-3257D081CEDC.png](http://upload-images.jianshu.io/upload_images/1388332-1b263d498c0d76eb.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
* 1、`$(XXXXXX)`,XXXXXX 为配置文件的名字
* 2、在 Fastfile 中如下配置
```
//还需深刻领悟，用的不好
//desc "Deploy a new version to the App Store"
  //match
  //disable_automatic_code_signing(path: "my_project.xcodeproj")
  //gym
  //enable_automatic_code_signing(path: "my_project.xcodeproj")
  //pilot
//end
```

# increment_version_number 未有效设置版本
*$(PROJECT_DIR)/XXXXXX/Info.plist*找不到
方案：Info.plist File 修改为 *XXXXXX/Info.plist*

# 命令行设置version、build
```
 lane :release do |op|
    increment_version_number(version_number: op[:version])
    increment_build_number(build_number: op[:build])
  end
```
输入`fastlane release version:4.3.0`，版本号为4.3.0，build在当前基础上自增加
输入`fastlane release version:4.3.0 build:71`，版本号为4.3.0，build为71
输入`fastlane release，版本号、build在当前基础上自增加
