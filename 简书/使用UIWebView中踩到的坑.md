# iOS7上UIWebView可以左右滑动
- 经过无数尝试发现，只要UIWebView的宽比屏幕的宽小一些，1个点左右，但这样能看到UIWebView不是全屏，想让宽度差更小些，经过几次实验，我的最小值为0.5，左右各。25个点。
- 在iOS8之后的系统上，UIWebView的宽等于屏幕宽也不会左右滑动。
# WebActionDisablingCALayerDelegate类找不到相应的方法实现
- 在加载UIWebView过程中，发现有时会崩溃，找不到WebActionDisablingCALayerDelegate类的一些方法实现。
- 自己动手加，写了一个UIWebView的category，.m代码如下：


    + (void)load{
    //  "v@:"
    Class class = NSClassFromString(@"WebActionDisablingCALayerDelegate");
    class_addMethod(class, @selector(setBeingRemoved), setBeingRemoved, "v@:");
    class_addMethod(class, @selector(willBeRemoved), willBeRemoved, "v@:");
    
    class_addMethod(class, @selector(removeFromSuperview), willBeRemoved, "v@:");
     }

    id setBeingRemoved(id self, SEL selector, ...)
    {
       return nil;
    }

    id willBeRemoved(id self, SEL selector, ...)
    {
      return nil;
    }

#修正
为 WebActionDisablingCALayerDelegate 这个私有类添加方法，在后面的一次提交审核过程中，ipa文件提交失败：引用私有API（还是私有类，记不得了）。所以建议不要采用。
