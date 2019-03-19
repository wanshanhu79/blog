# 问题---Undefined symbols for architecture armv7
这两天有点时间更新cocoapods到了1.0.1版本，然后就出问题了，一台电脑报：Undefined symbols for architecture armv7，还有一台报：Undefined symbols for architecture arm64。各种方法尝试，都不成功，下班后，继续折腾，在自己的电脑上居然可以，没有报错。但公司的两台电脑动用各种手段，都不行，没法子只能重新clone。
公司另一个项目执行pod install后报同样的错误，经过一段时间的仔细排查，找到了问题根源。
# 解决
通过对比（编译成功的项目与编译失败的项目）发现，有地方不一样

![3B13F4C9-8B5A-400B-AF44-C1E934BA1768.png](http://upload-images.jianshu.io/upload_images/1388332-3d5d6d4e948d1dac.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
备注：选中pods-项目名.a 即可在xcode右方找到上图信息，准确的说，我是发现上方的“type”和“location”不一样，修改无效，才注意到下方的差异的。
##.xcodeproj->project.pbxproj差异
在Xcode中找不到修改“location”的地方，想到是不是.xcodeproj->project.pbxproj关于pods的设置 有地方一样呢，经过仔细排查，果然
D725BCEBCC34F364839742F2 /* libPods-SecondaryMarket.a */ = {isa = PBXFileReference; explicitFileType = archive.ar; includeInIndex = 0; path = "libPods-SecondaryMarket.a"; sourceTree = BUILT_PRODUCTS_DIR; };

这一样中没有“path=”，有个“name=xxxx/xxxxx/xxxxx/libPods-SecondaryMarket.a”，修改一直后，编译通过，解决。
#问题---Undefined symbols for architecture arm64
要记得清除“/Library/Developer/Xcode/DerivedData/”下和这个项目有关的文件夹。
