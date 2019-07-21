## 需求
在控制器A中实现了webview的一些协议方法，控制器Aa继承了控制器A，并且也需要重写一些webview的协议方法，做一些特殊的事情，为了不影响原有的逻辑，需要判断，如果父类实现了这些方法，就需要调用父类的方法实现。通过`[super method]`可以做到调用，但要先判断父类中是否有实现，然后再调用，如果子类中重写了很多方法，这就有大量的重复代码。有没有优雅的实现呢?

## OC中调用一个方法或者函数的几种方式
#### 1.方法直接调用
`[a method]`
当这是一个私有方法，在类的实现外就没法用这种方式调用

#### 2. performSelector
`[self performSelector:<#(SEL)#> withObject:<#(id)#>]`
有参数限制，最多两个。
因为编译器不知道怎么管理它的内存，会报编译警告。

#### 3.NSInvocation
```
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
```
无参数限制

#### 4.直接调用objc_msgSend
定义
```
#if !OBJC_OLD_DISPATCH_PROTOTYPES
OBJC_EXPORT void objc_msgSend(void /* id self, SEL op, ... */ )
#else
OBJC_EXPORT id objc_msgSend(id self, SEL op, ...)
#end
```

具体调用
```
#import <objc/runtime.h>
#import <objc/message.h>
((id (*)(id, SEL, id, id))objc_msgSend)(self, sel, webView, navigation); 
```
在Target -> BuildSetting ->Enable Strict Checking of objc_msgSend Calls 设为NO后，就不要强转函数指针了
```
objc_msgSend(self, sel, webView, navigation);
```
PS:实际上这也是平常所写的OC方法调用编译后的实现，
#### 5.直接调用IMP
定义
```
/// A pointer to the function of a method implementation.  指向一个方法实现的指针
typedef id (*IMP)(id, SEL, ...); 
```

使用如下：
```
//直接调用，比较复杂
 IMP imp = [self  instanceMethodForSelector:sel];
 ((id(*)(id, SEL, id, id))imp)(self, sel, webView, navigation)
```
无参数限制。
需要强转函数指针，不好理解与使用。
比较偏底层，在项目中实际使用不多

objc_msgSend发送消息，在运行时找到方法对应的实现（IMP），然后调用实现（IMP）。
## 在子类中调用父类方法
在OC中，调用一个方法的逻辑是
* 1.先在当前类对象的方法缓存中查找对应的方法
* 2.没找到则在当前类对象的方法列表查找
* 3.没找到则在父类中重复以上两个动作
* 4.还没找到则走增加动态解析、备用消息接受者、完整转发
* 5.还没则抛出异常

怎么在子类中调用父类方法呢，从OC方法调用逻辑中，发现有两个思路，直接调用super，找到父类方法的IMP直接调用。那么上面所说的在OC中调用方法的几种方式还能用吗，先看个例子。

### 判断父类有没有实现某个方法？
```
@interface NSObject <NSObject> 
......
+ (BOOL)instancesRespondToSelector:(SEL)aSelector;
+ (BOOL)conformsToProtocol:(Protocol *)protocol;
- (IMP)methodForSelector:(SEL)aSelector;
+ (IMP)instanceMethodForSelector:(SEL)aSelector;
....
@end
```
根据NSObject提供的方法，有两种简单的方式
```
 //1. 是否为YES
 BOOL res = [[super class] instancesRespondToSelector:sel];
 //2. 找到方法的实现，不为NULL
 IMP imp1 =  [super methodForSelector:sel];
```
两种方式都达不到预期，因为实际响应的都是子类。为什么呢，因为super它实际上只是一个“编译器标示符”，它负责告诉编译器，当调用方法时，去调用父类的方法，而不是本类中的方法，但消息的实际响应者还是自己。

正确的调用方式应该是
```
 //1. 是否为YES
BOOL res = [[[self class] superclass] instancesRespondToSelector:sel];
 //2. 找到方法的实现，不为NULL
IMP imp1 =  [[[self class] superclass] instanceMethodForSelector:sel];
```

### 在子类中调用父类方法
先不说编译器能不能编译通过，用`[super performSelector]`和`[invocation invokeWithTarget:super];`的这种思路，但从上面的实践中就知道这条路行不通。实际上，编译器会编译失败，*Use of undeclared identifier 'super'*。

#### 1.直接方法调用
```
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {

    if ([[[self class] superclass] instancesRespondToSelector:_cmd]) {
        [super webView:webView didFailProvisionalNavigation:navigation withError:error];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation {
    if ([[[self class] superclass] instancesRespondToSelector:_cmd]) {
        [super webView:webView didFinishNavigation:navigation];
    }
    
}
```
如果一个页面中有太多这样的代码，看着会比较塞心，不够优雅。

#### 2.objc_msgSend
```
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {

    if ([[[self class] superclass] instancesRespondToSelector:_cmd]) {
        struct objc_super superReceiver = {
            self,
            [self superclass]
        };
        objc_msgSendSuper(&superReceiver, _cmd, webView, navigation, error);
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation {
    if ([[[self class] superclass] instancesRespondToSelector:_cmd]) {
        struct objc_super superReceiver = {
            self,
            [self superclass]
        };
        objc_msgSendSuper(&superReceiver, _cmd, webView, navigation);
    }
    
}
```
objc_msgSendSuper是objc_msgSend调用父类方法时的实现，即[super method]编译后就成了objc_msgSendSuper

PS：这是Target -> BuildSetting ->Enable Strict Checking of objc_msgSend Calls 设为NO后的调用
#### 3.IMP
```
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {

    IMP imp = [[[self class]superclass] instanceMethodForSelector:_cmd];
    if (imp) {
        imp(self, _cmd, webView, navigation, error);
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation {
    IMP imp = [[[self class]superclass] instanceMethodForSelector:_cmd];
    if (imp) {
        imp(self, _cmd, webView, navigation);
    }
}
```
发现后两者的方法实现里，大部分代码是相同的，仅有的不同是方法参数的实现。很容易想到宏，它支持可变参数，并且可向内传递。具体实现如下
```
#define ZLLCallSuper(self, _cmd, format, ...) \
if ([[super class] instancesRespondToSelector:_cmd]) {\
struct objc_super superReceiver = {\
    self,\
    [self superclass]\
};\
objc_msgSendSuper(&superReceiver, _cmd, __VA_ARGS__);\
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error {

    ZLLCallSuper(self, _cmd, webView, navigation, error)
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(null_unspecified WKNavigation *)navigation {
   ZLLCallSuper(self, _cmd, webView, navigation)
}
```

PS：这是Target -> BuildSetting ->Enable Strict Checking of objc_msgSend Calls 设为NO后的调用

但宏不支持类型检测，从内心深处是拒绝的，但如果直接定义可变参数的OC方法，没办法（或者说我还不知道）传递可变参数。
这种方式要改Xcode的配置，不然强制指针转换时宏替换编译不通过，最终的方式还是有瑕疵，还得改。

#### 2019.3.13更新
默认情况下，系统的IMP定义，直接调用，会有编译错误*Too many arguments to function call, expected 0, have n*
```
typedef id (*IMP)(id, SEL, ...); 
```
我们重新定义IMP，对系统的强转，然后直接调用
```
typedef void(*ZLLIMP) (id, SEL, ...);
ZLLIMP imp = (ZLLIMP)[[[super class] superclass] instanceMethodForSelector:_cmd];
if (imp) {
      imp(self, _cmd, webView, navigation, error);
}
```
结合上面的宏，就可以比较优雅的实现在子类中调用父类方法了，但还是要有宏，还是有点不完美，继续探索。

PS:为什么直接用IMP会有编译错误，而我们自己定义的没有呢。从Xcode6之后，苹果不希望我们直接调用这些方法，取消了参数提示功能。可以通过Target -> BuildSetting ->Enable Strict Checking of objc_msgSend Calls 设为NO后的修改，打开参数提示功能
