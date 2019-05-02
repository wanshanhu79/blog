//
//  UIScrollView+VerticalScroll.m
//  WeakProxy
//
//  Created by llzhang on 2019/5/1.
//  Copyright © 2019 zll. All rights reserved.
//

#import "UIScrollView+VerticalScroll.h"
#import <objc/runtime.h>

/// 上下滑动时的通知
NSString * _Nullable const ZLLverticalScrollNotification = @"ZLLverticalScrollNotification";
/// 上下滑动时的通知的userInfo 中滑动距离的key
NSString * _Nullable const ZLLverticalScrollDistanceKey = @"ZLLverticalScrollDistanceKey";
/// 上下滑动时的通知的userInfo 中滑动视图的key
NSString * _Nullable const ZLLverticalScrollViewKey = @"ZLLverticalScrollViewKey";
#pragma mark - 类声明 -
#pragma mark - 拦截者 声明
@class ZLLVerticalScrollProxy;
@interface ZLLIntercept : NSObject <UIScrollViewDelegate>

/// 需要转发事件，所以需要拿到
@property(nonatomic, readonly, weak) ZLLVerticalScrollProxy *proxy;
+ (instancetype)intercepWithProxy:(ZLLVerticalScrollProxy *)proxy;

/// 是否手动滑动
@property (nonatomic, assign, getter=isManuallyMoving) BOOL manuallyMoving;
/// 上一次y的位置，滑动距离
@property (nonatomic, assign) CGFloat startOffsetY;

@end
#pragma mark - 消息转发的类 声明
@class ZLLIntercept;
///模仿 YYKit中的写法
@interface ZLLVerticalScrollProxy : NSProxy

/// 原来的delegate
@property(nonatomic, weak) id<UIScrollViewDelegate> originDelegate;
/// 拦截的delegate
@property(nonatomic, readonly, strong) id<UIScrollViewDelegate> interceptDelegate;

@end
#pragma mark - 类实现 -
#pragma mark - 拦截者 实现
@implementation ZLLIntercept

+ (instancetype)intercepWithProxy:(ZLLVerticalScrollProxy *)proxy {
    return [[self alloc] initWithProxy:proxy];
}

- (instancetype)initWithProxy:(ZLLVerticalScrollProxy *)proxy {
    self = [super init];
    if (self) {
        _proxy = proxy;
    }
    return self;
}

#pragma mark - 拦截的方法

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    self.manuallyMoving = NO;
    ///转发，调用原有响应者
    if ([self.proxy.originDelegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [self.proxy.originDelegate scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
    }
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.manuallyMoving = YES;
    self.startOffsetY = scrollView.contentOffset.y;
    ///转发，调用原有响应者
    if ([self.proxy.originDelegate respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
        [self.proxy.originDelegate scrollViewWillBeginDragging:scrollView];
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (self.isManuallyMoving) {
        ///发送通知
        [[NSNotificationCenter defaultCenter] postNotificationName:ZLLverticalScrollNotification
                                                            object:nil
                                                          userInfo:@{ZLLverticalScrollDistanceKey : @(scrollView.contentOffset.y  - self.startOffsetY),
                                                                     ZLLverticalScrollViewKey : scrollView
                                                                     }];
    }
    self.startOffsetY = scrollView.contentOffset.y;
    ///转发，调用原有响应者
    if ([self.proxy.originDelegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
        [self.proxy.originDelegate scrollViewDidScroll:scrollView];
    }
}

@end
#pragma mark - 消息转发的类 实现

@implementation ZLLVerticalScrollProxy
+ (id)VerticalScrollProxy {
    return [[ZLLVerticalScrollProxy alloc] initWithIntercept];
}
- (id)initWithIntercept {
    _interceptDelegate = [ZLLIntercept intercepWithProxy:self];
    return self;
}

#pragma mark - 关键方法
/// 判断是不是要拦截的方法
- (BOOL)interceptionSelector:(SEL)sel {
    return  sel == @selector(scrollViewDidScroll:) || sel == @selector(scrollViewDidEndDragging:willDecelerate:) || sel == @selector(scrollViewWillBeginDragging:);
}
/// 这个方法一定要重写，不然forwardingTargetForSelector方法不走
- (BOOL)respondsToSelector:(SEL)aSelector {
 //这个地方不能加self.judgeDelegate是否存在判断，如果刚开始没有后面有了，是否响应scrollViewDidScroll方法不会再判断，有缓存
    if ([self interceptionSelector:aSelector]) {
        return YES;
    }
    return [_originDelegate respondsToSelector:aSelector];
}
/// 判断响应者
- (id)forwardingTargetForSelector:(SEL)selector {
    /// 如果是拦截者存在且是要拦截的方法，拦截者优先处理
    if (_interceptDelegate && [self interceptionSelector:selector]) {
        return _interceptDelegate;
    }
    if ([_originDelegate respondsToSelector:selector]) {
        return _originDelegate;
    }
    return nil;
}
#pragma mark - 复制过来的方法，用来隐藏proxy类和安全

- (void)forwardInvocation:(NSInvocation *)invocation {
    void *null = NULL;
    [invocation setReturnValue:&null];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [NSObject instanceMethodSignatureForSelector:@selector(init)];
}

- (BOOL)isEqual:(id)object {
    return [_originDelegate isEqual:object];
}

- (NSUInteger)hash {
    return [_originDelegate hash];
}

- (Class)superclass {
    return [_originDelegate superclass];
}

- (Class)class {
    return [_originDelegate class];
}

- (BOOL)isKindOfClass:(Class)aClass {
    return [_originDelegate isKindOfClass:aClass];
}

- (BOOL)isMemberOfClass:(Class)aClass {
    return [_originDelegate isMemberOfClass:aClass];
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    return [_originDelegate conformsToProtocol:aProtocol];
}

- (BOOL)isProxy {
    return YES;
}

- (NSString *)description {
    return [_originDelegate description];
}

- (NSString *)debugDescription {
    return [_originDelegate debugDescription];
}

@end

#pragma mark - 分类 交换方法实现 -
@implementation UIScrollView (VerticalScrollHook)
static const void *kZLLVerticalScrollHookKey = &kZLLVerticalScrollHookKey;
#pragma mark - 保存值，建立关联
- (ZLLVerticalScrollProxy *)zll_vertScrollProxy {
    return  objc_getAssociatedObject(self, kZLLVerticalScrollHookKey);
}

#pragma mark - 实现方法
- (void)zll_beginObserverVerticalScroll {
    ZLLVerticalScrollProxy *proxy = [self zll_vertScrollProxy];
    ///判断 避免多次创建
    if (proxy == nil) {
        proxy = [ZLLVerticalScrollProxy VerticalScrollProxy];
        //也可以通过下面的方式，保留以前的值
      //  proxy.originDelegate = [self delegate];
        objc_setAssociatedObject(self, kZLLVerticalScrollHookKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    //避免在交换方法之前已经设置有了delegate了，
    id<UIScrollViewDelegate> originDelegate = [self delegate];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ///UIScrollView 只需要拦截UIScrollViewDelegate协议，setter与getter是一对方法，要成对处理
        swizzleIMP([UIScrollView class], @selector(setDelegate:), (IMP)ZLLNewSetDelegateIMP, (IMP *)&ZLLOriginSetDelegateIMP);
        swizzleIMP([UIScrollView class], @selector(delegate), (IMP)ZLLNewDelegateIMP, (IMP *)&ZLLOriginDelegateIMP);
    });
    /// 之前已经有值触发事件拦截
    self.delegate = originDelegate;

}
#pragma mark - 辅助

//static void ZLLNewDelegateIMP(id self, SEL _cmd, __weak id<UIScrollViewDelegate> delegate);
/// 指向原始的实现，格式必须是这样，告诉编译器是个指针，不需要找它的实现
static void (*ZLLOriginSetDelegateIMP)(id self, SEL _cmd,__weak id<UIScrollViewDelegate> delegate);

/// 新的设置delegate的函数
static void ZLLNewSetDelegateIMP(id self, SEL _cmd, id<UIScrollViewDelegate> delegate) {
    ///
    if ([self isKindOfClass:[UIScrollView class]]) {
      
        ZLLVerticalScrollProxy *proxy = [self zll_vertScrollProxy];
        if (proxy) {
            proxy.originDelegate = delegate;
            delegate = (id<UIScrollViewDelegate>)proxy;
        }
    }
   
    ZLLOriginSetDelegateIMP(self, _cmd, delegate);

}
static id<UIScrollViewDelegate> (*ZLLOriginDelegateIMP)(id self, SEL _cmd);

/// 新的获取delegate的函数
static id<UIScrollViewDelegate>  ZLLNewDelegateIMP(id self, SEL _cmd) {
    /// 当delegate存在时再更改，不然直接清空
    if ([self isKindOfClass:[UIScrollView class]]) {
        
        ZLLVerticalScrollProxy *proxy = [self zll_vertScrollProxy];
        if (proxy) {
            return proxy.originDelegate;
        }
    }
    
   return ZLLOriginDelegateIMP(self, _cmd);
    
}

/// 交换方法函数
static void swizzleIMP(id self, SEL originSel, IMP newIMP, IMP *oldIMPPointer) {
    
    IMP oldIMP = NULL;
    Method method = class_getInstanceMethod(self, originSel);
    if (method) {
        oldIMP = class_replaceMethod(self, originSel, newIMP, method_getTypeEncoding(method));
        if (NULL == oldIMP) {
            oldIMP = method_getImplementation(method);
        }
    }
    *oldIMPPointer = oldIMP;
}

@end

#pragma mark - 分类 isa 派生子类 -
#import <objc/message.h>
@implementation UIScrollView (VerticalScrollDerive)
static const void *kZLLVerticalScrollDeriveKey = &kZLLVerticalScrollDeriveKey;
#pragma mark - 保存值，建立关联
- (ZLLVerticalScrollProxy *)zll_verticalScrollProxy {
    return  objc_getAssociatedObject(self, kZLLVerticalScrollDeriveKey);
}


#pragma mark - 实现方法
- (void)zll_beginObserverVerticalScroll1 {
    ZLLVerticalScrollProxy *proxy = [self zll_verticalScrollProxy];
    if (proxy == nil) {
        proxy = [ZLLVerticalScrollProxy VerticalScrollProxy];
        proxy.originDelegate = self.delegate;

        objc_setAssociatedObject(self, kZLLVerticalScrollDeriveKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    //把proxy设置为delegate
    struct objc_super objcSuper = {.super_class = [self class], .receiver = self};
    ((void (*)(void *, SEL, id))objc_msgSendSuper)(&objcSuper, @selector(setDelegate:), proxy);
    //获取派生类，并注册
    Class aopClass = makeSubclass([self class]);
    
    if (![[self class] isSubclassOfClass:aopClass]) {
        ///必不可少，如果在这之前已经添加了KVO的话，不然之前添加的无效
        resetKVOInfo(self, aopClass);
    }
}
#pragma mark - 辅助
///KVO用的也是派生一个子类，重设元类的方法，故要特殊处理，不然在调用之前添加的KVO会失效
static void resetKVOInfo(UIScrollView *scrollView, Class aopClass) {
    id observationInfo = [scrollView observationInfo];
    NSArray *observanceArray = [observationInfo valueForKey:@"_observances"];
    ///移除旧的KVO
    for (id observance in observanceArray) {
        NSString *keyPath = [observance valueForKeyPath:@"_property._keyPath"];
        id observer = [observance valueForKey:@"_observer"];
        if (keyPath && observer) {
            [scrollView removeObserver:observer forKeyPath:keyPath];
        }
    }
    /// 修改isa指针，即修改元类
    object_setClass(scrollView, aopClass);
    ///添加新的KVO
    for (id observance in observanceArray) {
        NSString *keyPath = [observance valueForKeyPath:@"_property._keyPath"];
        id observer = [observance valueForKey:@"_observer"];
        if (observer && keyPath) {
            void *context = NULL;
            NSUInteger options = 0;
            @try {
                Ivar _civar = class_getInstanceVariable([observance class], "_context");
                if (_civar) {
                    context = ((void *(*)(id, Ivar))(void *)object_getIvar)(observance, _civar);
                }
                Ivar _oivar = class_getInstanceVariable([observance class], "_options");
                if (_oivar) {
                    options = ((NSUInteger(*)(id, Ivar))(void *)object_getIvar)(observance, _oivar);
                }
                /// iOS11 返回的值会填充8个字节
                if (options >= 128) {
                    options -= 128;
                }
                
            } @catch (NSException *exception) {
                
            }
            if (options == 0) {
                options = (NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew);
            }
            [scrollView addObserver:observer forKeyPath:keyPath options:options context:context];
        }
    }
}

static Class makeSubclass(Class origClass) {
    NSString *className = NSStringFromClass(origClass);
    NSString *aopClassName = [@"ZLLAOP_" stringByAppendingString:className];
    Class aopClass = NSClassFromString(aopClassName);
    
    /// 注册过的类，通过字符串可以获得这个类在内存中的地址
    if (aopClass) {
        return aopClass;
    }
    /// 创建一个类，要有父类，和子类名，返回创建好的类的内存地址
    aopClass = objc_allocateClassPair(origClass, aopClassName.UTF8String, 0);
    /// 添加方法 setter与getter是一对方法，要成对处理
    addOverriMethod(@selector(setDelegate:), origClass, aopClass, (IMP)ZLLNewSetDelegate);
    addOverriMethod(@selector(delegate), origClass, aopClass, (IMP)ZLLNewDelegate);
    /// 向runtime注册这个类
    objc_registerClassPair(aopClass);
   
    return aopClass;
}
/// 添加方法实现
static void addOverriMethod(SEL sel, Class origClass, Class aopClass, IMP newIMP) {
    Method method = class_getInstanceMethod(origClass, sel);
    const char *types = method_getTypeEncoding(method);
   class_addMethod(aopClass, sel, newIMP, types);
}

/// 新的设置delegate的函数
static void ZLLNewSetDelegate(id self, SEL _cmd, id<UIScrollViewDelegate> delegate) {
     ZLLVerticalScrollProxy *proxy = [self zll_verticalScrollProxy];
 /// 告诉编译器，去调用父类的IMP，这相当于[super setDelegate:delegate]，是它编译后的实现形式
    if (proxy) {
        struct objc_super objcSuper = {
            .super_class = [self superclass], .receiver = self,
        };
        proxy.originDelegate = delegate;
        ((void (*)(void *, SEL, id))(void *)objc_msgSendSuper)(&objcSuper, _cmd, proxy);
    }else{
        struct objc_super objcSuper = {.super_class = [self class], .receiver = self};
        ((void (*)(void *, SEL, id))objc_msgSendSuper)(&objcSuper, @selector(setDelegate:), delegate);
    }
}

/// 新的获取delegate的函数
static id<UIScrollViewDelegate>  ZLLNewDelegate(id self, SEL _cmd) {
    ZLLVerticalScrollProxy *proxy = [self zll_verticalScrollProxy];
    
    if (proxy) {
        return proxy.originDelegate;
    }else{
        struct objc_super objcSuper = {.super_class = [self class], .receiver = self};
        return ((id(*)(void *, SEL))(void *)objc_msgSendSuper)(&objcSuper, _cmd);
    }
}


@end
