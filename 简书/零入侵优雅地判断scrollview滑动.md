### 一、需求
之前遇到一个需求是，要求在scrollview在上下滑动时，scrollview显示区域高度变化。向上滑动时——拉高，向下滑动时——恢复。

### 二、项目中的实现
由于项目中要实现的几个页面都用到了自定义的SITableView，刚好就在自定义的SITableView中实现了

#### 1.向外传递滑动
有以下两种方案
* 1）协议 如果是多级或者是跨层的，不好要拿到响应者，同时如果视图层级改变的话，也需要改变赋值响应者的代码。可以精准的传递事件给需要改变的视图，也可以自定义滑动距离，虽然实际用处不大。本次实现用的是协议。

还有一种思路是，定义一个BOOL值，标识是否开启滑动改变传递，然后向上查找第一个能响应协议的responder，把它记录为委托者。
* 2）通知
传递数据方便，但不能自定义滑动距离。并且如果多个界面都注册了的话，接受到通知要进行判断，判断要调整大小的视图是不是在屏幕上。如果页面复用过程中，导致某个视图加载完成后，视图层级中有父视图和子视图都能响应通知，会出现问题，虽然出现的可能性不大。

协议的代码如下：
```
@class SITableView;
@protocol SITableViewUpDownScrollProtocol <NSObject>
//告诉外部对象，是向上还是向下滑动
- (void)tableView:(SITableView *)tableView updownScroll:(BOOL)isUp;
@optional
// 是否要自定义判断移动的距离
- (CGFloat)tableViewMinMoveDistance:(SITableView *)tableView;

@end
```
滑动方向是向上还是向下，应该用枚举的，偷懒了
#### 2.SITableView中的主要变动
在`scrollViewDidScroll :`方法中，判断contentOffset.y的变化，与前一刻的差值作为上下的依据。
要考虑以下几个问题：
> 1.只有当用户手动滑动时，才改变视图高度。需要记录是不是手动拖拽，虽然，scrollview有dragging，但不够精确，在手松开减速时依然是YES，不符合要求
> 2.需要记录初始值，来做参考
    3.要移动一定距离，才能判断是否执行回调，避免有时手触碰屏幕引起的误操作
    4.拦截的方法，不能影响原方法的调用

* 1.增加私有属性，协助判断
```
//是不是手动移动
@property (nonatomic, assign, getter=isManuallyMoving) BOOL manuallyMoving;
//开始手动移动时contentOffset.y值
@property (nonatomic, assign) CGFloat startOffsetY;
//tableview的新的delegate，用来判断是否要拦截
@property (nonatomic, strong) SITableViewWeakProxy *weakProxy;
//默认最小移动距离 5
@property (nonatomic, assign) CGFloat minMoveDistance;
```
* 2.实现
```
#pragma mark - 上下滑动回调
//调用有参无返回值的方法
- (void)callTableViewUpDownScrollProtocol:(BOOL)isUp {
    
    if (self.upDownScrollDelegate == nil) {
        return;
    }
    // 1. 根据方法创建签名对象sig
    NSMethodSignature *sig = [self.upDownScrollDelegate methodSignatureForSelector:@selector(tableView:updownScroll:)];
    
    // 2. 根据签名对象创建调用对象invocation
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
    
    // 3. 设置调用对象的相关信息
    invocation.target = self.upDownScrollDelegate;
    invocation.selector = @selector(tableView:updownScroll:);
 
    SITableView *tempSelf = self;
    // 参数必须从第2个索引开始，因为前两个已经被target和selector使用
    [invocation setArgument:&tempSelf atIndex:2];
    [invocation setArgument:&isUp atIndex:3];
    
    // 4. 调用方法
    [invocation invoke];
    
}
#pragma mark - 拦截的协议方法

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    self.manuallyMoving = NO;
    //不影响原有的逻辑，回调原来delegate的方法
    if ([self.weakProxy.originTarget respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [self.weakProxy.originTarget scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
    }
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.manuallyMoving = YES;
    self.startOffsetY = scrollView.contentOffset.y;

    //不影响原有的逻辑，回调原来delegate的方法
    if ([self.weakProxy.originTarget respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
        [self.weakProxy.originTarget scrollViewWillBeginDragging:scrollView];
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (self.isManuallyMoving) {
        if (self.startOffsetY < scrollView.contentOffset.y - self.minMoveDistance) {
          
            [self callTableViewUpDownScrollProtocol:YES];
        }
        if (self.startOffsetY > scrollView.contentOffset.y + self.minMoveDistance) {
      
            [self callTableViewUpDownScrollProtocol:NO];
        }
    }
    self.startOffsetY = scrollView.contentOffset.y;
    
    //不影响原有的逻辑，回调原来delegate的方法
    if ([self.weakProxy.originTarget respondsToSelector:@selector(scrollViewDidScroll:)]) {
        [self.weakProxy.originTarget scrollViewDidScroll:scrollView];
    }
}
#pragma mark - setter与getter
- (void)setDelegate:(id<UITableViewDelegate>)delegate {
    self.weakProxy.originTarget = delegate;
    [super setDelegate:self.weakProxy];
}

- (void)setUpDownScrollDelegate:(id<SITableViewUpDownScrollProtocol>)upDownScrollDelegate {
    if (upDownScrollDelegate && [upDownScrollDelegate conformsToProtocol:@protocol(SITableViewUpDownScrollProtocol)] && [upDownScrollDelegate respondsToSelector:@selector(tableView:updownScroll:)]) {
        _upDownScrollDelegate = upDownScrollDelegate;
        
        if ([upDownScrollDelegate respondsToSelector:@selector(tableViewMinMoveDistance:)]) {
            self.minMoveDistance = [upDownScrollDelegate tableViewMinMoveDistance:self];
        }
    }
    if (upDownScrollDelegate == nil) {
        _upDownScrollDelegate = upDownScrollDelegate;
    }
}
- (SITableViewWeakProxy *)weakProxy {
    if (_weakProxy == nil) {
        _weakProxy = [SITableViewWeakProxy alloc];
        _weakProxy.interceptionTarget = self;
    }
    return _weakProxy;
}
```

**注意** `[SITableViewWeakProxy alloc];`这样写没有错，它没有init方法。
#### 3.SITableViewWeakProxy的实现
为什么要做的这样复杂，
不直接把delegate设为自己，用一个属性记录原始的delegate呢？如果这样做了，tableview的UITableViewDelegate协议中的其他方法呢，怎么把协议中的方法传递给原始的delegate呢。实现所有的方法，在里面判断原始的delegate是否实现了，原始未实现的但方法需要返回值的你怎么操作。如果里面后面新增了方法怎么办，一个个版本维护更新？
走消息转发，UITableViewDelegate协议中的很多方法是optional，会调用respondsToSelector来判断是否协议中某个方法，这个地方的响应者是SITableView的实例，它明显没有实现协议中的其他方法，就无法调用了。当然也可以重写respondsToSelector，但怎么判断这个sel是UITableViewDelegate协议中的方法，一个个列出来

使用SITableViewWeakProxy，是实例不会在方法列表中查找，而是直接走消息转发，效率高，也安全，不用担心其他的影响。包括respondsToSelector方法也是走的消息转发，所以在具体的实现中，要特殊处理，判断这个方法的参数，如果是要拦截的三个方法，就要拦截。
```
@interface SITableViewWeakProxy : NSProxy <UITableViewDelegate>

@property (nonatomic, weak) NSObject<UITableViewDelegate> *originTarget;
@property (nonatomic, weak) NSObject *interceptionTarget;

@end

@implementation SITableViewWeakProxy

//- (id)forwardingTargetForSelector:(SEL)selector {
//    NSLog(@"%@...%@", self, NSStringFromSelector(selector));
//    for (NSString *interceptionSEL in self.interceptionSELS) {
//        if (NSSelectorFromString(interceptionSEL) == selector) {
//            return _interceptionTarget;
//        }
//    }
//    return _originTarget;
//}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [self.originTarget methodSignatureForSelector:sel];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    //这个很重要，SITableViewWeakProxy不能响应respondsToSelector方法，只是做转发，所以需要特殊判断下
    if (self.interceptionTarget && invocation.selector == @selector(respondsToSelector:)) {
        SEL parameterSel;
        [invocation getArgument:&parameterSel atIndex:2];
        
        if ([self interceptionSelector:parameterSel]) {
            [invocation invokeWithTarget:self.interceptionTarget];
            return;
        }
      
    }else if (self.interceptionTarget && [self interceptionSelector:invocation.selector]) {
        [invocation invokeWithTarget:self.interceptionTarget];
        return;
    }
    //不需要拦截，直接调用原来的delegate
    [invocation invokeWithTarget:self.originTarget];
}
//只需要拦截这三个方法，不需其他方法
- (BOOL)interceptionSelector:(SEL)sel {
    return  sel == @selector(scrollViewDidScroll:) || sel == @selector(scrollViewDidEndDragging:willDecelerate:) || sel == @selector(scrollViewWillBeginDragging:);
}

@end
```
### 三、scrollview分类的实现

` @selector(setDelegate:)` `@selector(delegate)` 是**一个属性的set与get方法，它们是一个整体，不能拆分开来，需要都hook**，之前思虑不周全，没考虑到这一点。比如说，不断的调用get方法然后再重新赋值给set方法，之前的实现就会有问题，改变了原有的实现，虽然一般不会这么做，但程序要严谨，不留漏洞。



分类方式的实现没有采用协议的方式，主要是考虑到几点：

* 如果有协议回调、又有通知可以选，那么在开启监听方法设计不够优雅
* 这样在组件化使用中更加方便，耦合性比协议小
* 不在实现中统一判断最小滑动距离，而是直接传递，由使用者自行判断，灵活性更大；之前的最小滑动距离设定不好操作也是一方面

**实现方案说明：**

1. 通知的userInfo中，有两个key，一直是滑动的距离（当前位置减去上一次的位置），还有一个就是哪一个scrollView滑动发出的通知，来解决使用通知引起的多点触发，不知道该不该响应的问题。
2. 消息转发者与拦截方法判断分别在两个类实现，虽然职责分开了，但是之间互相耦合，没有通过接口（协议）编程。消息转发类的实现参考了YYKit里面的实现。
3. 两种实现方式，实际上大同小异
   		* 通过函数指针的方式，hook方法的实现。这里替换的是`UIScrollView`这个类的`delegate`属性对应的两个方法，使用GCD确保只会进行一次
   		* 通过派生一个子类，类似KVO模式。调用方法使用的是编译后的方法`objc_msgSendSuper` ，还要处理如果之前这个类添加过KVO的情况，并且处理的用的是KVC，如果有变动，不会知道。如果有其他类也使用这种方案，将互相冲突抵消掉。思路与实现参考了[IMYAOPTableView](https://github.com/MeetYouDevs/IMYAOPTableView)
4. 测试中分了两种情况：在开启监听之前delegate有值；开启监听之后才设置delegate。通过宏来进行不同情况测试。两种实现方式也是通过宏来控制切换。



 对于参考与借鉴的源码在这里一并表示感谢！欢迎斧正！