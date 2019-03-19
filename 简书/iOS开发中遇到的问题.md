### 一.对NSNumber类型调用length方法导致的崩溃
```
@implementation NSNumber (SafeString)

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([NSString instancesRespondToSelector:aSelector]) {
        //number类型的特别容易用字符串来接，所以特别容易崩，批处理。
        return self.stringValue;
    }
    return nil;
}

@end
```
### 二.项目开发中使用UITextView，初始化时耗时比较长，尤其是在iOS8上

使用YYTextView替代，但是开启点击其它区域收回键盘时，点击YYTextView的编辑区域，键盘也收回。查看源码，可以通过如下方式处理
```
- (void)registerYYTextView{
//  接受编辑事件，注意编辑状态改变导致的键盘的弹出与收起
    IQKeyboardManager *keyBoardManager = [IQKeyboardManager sharedManager];
    [keyBoardManager registerTextFieldViewClass:[YYTextView class] didBeginEditingNotificationName:YYTextViewTextDidBeginEditingNotification didEndEditingNotificationName:YYTextViewTextDidEndEditingNotification];
//  处理键盘收回
    [keyBoardManager.touchResignedGestureIgnoreClasses addObject:[YYTextContainerView class]];
    [keyBoardManager.touchResignedGestureIgnoreClasses addObject:[YYTextView class]];
}
```
