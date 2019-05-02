[MeetYouDevs/IMYAOPTableView](https://github.com/MeetYouDevs/IMYAOPTableView)

主要是针对在数据流中接入广告的应用场景。

原理：其实和我们平常的做法一致，就是把广告和数据流整合在一起，返回总数，然后根据不同的位置调用不同的方法。不过这个框架把这种思路，用切面的思路实现了，在广告和数据流层下添加了一个处理层，将判断的代码抽取，通过row与section的对比，不需要在原代码里大量的if / else判断。

### 类

#### 1.IMYAOPTableViewRawModel

继承自`IMYAOPBaseRawModel` ，数据流数据model，主要用在以下协议，功能扩展中

```
///需要 tableView.dataSource 实现 tableView:modelForRowAtIndexPath: 协议中的方法
- (NSArray<IMYAOPTableViewRawModel *> *)allModels;

///需要 tableView.dataSource 实现 IMYAOPTableViewGetModelProtocol 协议中的方法
- (nullable id)modelForRowAtIndexPath:(NSIndexPath *)indexPath;
```

#### 2.IMYAOPTableViewInsertBody 

继承自 `IMYAOPBaseInsertBody`，管理插入的广告的model，插入的数据要这样包装下

#### 3.IMYAOPCallProxy

代理类，这个类会将所有的方法直接调用父类的方法

```
- (void)forwardInvocation:(NSInvocation *)invocation {
    id target = self.target;
    if (!target) {
        ///设置返回值为nil
        [invocation setReturnValue:&target];
        return;
    }

    Class invokeClass = self.invokeClass;
    NSString *selectorName = NSStringFromSelector(invocation.selector);
    NSString *superSelectorName = [NSString stringWithFormat:@"IMYSuper_%@_%@", NSStringFromClass(invokeClass), selectorName];
    SEL superSelector = NSSelectorFromString(superSelectorName);
	//通过这个，为父类动态添加方法实现来实现，这个地方没法用消息发送到super
    if ([invokeClass instancesRespondToSelector:superSelector] == NO) {
        Method superMethod = class_getInstanceMethod(invokeClass, invocation.selector);
        if (superMethod == NULL) {
            IMYLog(@"class:%@ undefine funcation: %@ ", NSStringFromClass(invokeClass), selectorName);
            return;
        }
        IMP superIMP = method_getImplementation(superMethod);
        class_addMethod(invokeClass, superSelector, superIMP, method_getTypeEncoding(superMethod));
    }
    invocation.selector = superSelector;
    [invocation invokeWithTarget:target];
}
```



### 4.IMYAOPBaseUtils

提供了一些IndexPath方法，转化为对应的数据流对应的IndexPath，广告的未转化，

不支持常见的初始化方法

```
#pragma mark - 注入 aop class

- (void)injectFeedsView:(UIView *)feedsView {
    struct objc_super objcSuper = {.super_class = [self msgSendSuperClass], .receiver = feedsView};
    ((void (*)(void *, SEL, id))(void *)objc_msgSendSuper)(&objcSuper, @selector(setDelegate:), self);
    ((void (*)(void *, SEL, id))(void *)objc_msgSendSuper)(&objcSuper, @selector(setDataSource:), self);

    self.origViewClass = [feedsView class];
    Class aopClass = [self makeSubclassWithClass:self.origViewClass];
    if (![self.origViewClass isSubclassOfClass:aopClass]) {
        [self bindingFeedsView:feedsView aopClass:aopClass];
    }
}

- (void)bindingFeedsView:(UIView *)feedsView aopClass:(Class)aopClass {
    id observationInfo = [feedsView observationInfo];
    NSArray *observanceArray = [observationInfo valueForKey:@"_observances"];
    ///移除旧的KVO
    for (id observance in observanceArray) {
        NSString *keyPath = [observance valueForKeyPath:@"_property._keyPath"];
        id observer = [observance valueForKey:@"_observer"];
        if (keyPath && observer) {
            [feedsView removeObserver:observer forKeyPath:keyPath];
        }
    }
    object_setClass(feedsView, aopClass);
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
                /// 不知道为什么，iOS11 返回的值 会填充8个字节。。 128
                if (options >= 128) {
                    options -= 128;
                }
            } @catch (NSException *exception) {
                IMYLog(@"%@", exception.debugDescription);
            }
            if (options == 0) {
                options = (NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew);
            }
            [feedsView addObserver:observer forKeyPath:keyPath options:options context:context];
        }
    }
}

#pragma mark - install aop method
- (Class)makeSubclassWithClass:(Class)origClass {
    NSString *className = NSStringFromClass(origClass);
    NSString *aopClassName = [kAOPFeedsViewPrefix stringByAppendingString:className];
    Class aopClass = NSClassFromString(aopClassName);

    if (aopClass) {
        return aopClass;
    }
    aopClass = objc_allocateClassPair(origClass, aopClassName.UTF8String, 0);

    [self setupAopClass:aopClass];

    objc_registerClassPair(aopClass);
    return aopClass;
}
```



#### 5.IMYAOPTableViewUtils 

继承自 `IMYAOPBaseUtils`，要通过TableView 的 aop_utils 方法，获取该实例。可以设置AOP TableView的回调(主要用来做一些数据统计之类的事)



核心方法，在IMYAOPBaseUtils类中



**1）IMYAOPTableViewUtils (UITableViewDelegate)**

实现UITableViewDelegate协议的所有方法并进行转发

**2）IMYAOPTableViewUtils (UITableViewDataSource)**

实现UITableViewDataSource协议的所有方法并进行转发

**3）IMYAOPTableViewUtils (InsertedProxy)**

获取插入数据的代理方法

**4）IMYAOPTableViewUtils (TableViewProxy)**

对TableView执行原始数据的操作, 不进行AOP的处理，借助`IMYAOPCallProxy`

**5）IMYAOPTableViewUtils (Models)**

获取数据model，需要datasorce实现特定的方法

#### 6._IMYAOPTableView

实现了TableView.h 文件中的所有方法，但方法前加了 `aop_`。

中间层，转发直接调用TableView.h文件中的方法 

个人理解：是为了与系统方法区别，获取时方便操作



### 使用

#### 1.创建一个类，有个弱属性IMYAOPTableViewUtils

####2.实现数据插入

需要数据统计的话，要设置广告回调

插入新数据前，记得清空历史数据

插入的广告数据，要用IMYAOPTableViewInsertBody包装下，最好是继承它实现各子类，把广告数据模型传进去，不然后续获取数据不方便

section数据要配合row

插入完记得刷新

#### 3.类实现相应协议

```
IMYAOPTableViewDelegate(<UITableViewDelegate>), IMYAOPTableViewDataSource, IMYAOPTableViewGetModelProtocol
```

主要是UITableView 回调方法，比如说cell样式 高度，选中事件等等。

#### 4.获取要插入广告的UITableView，和广告类关联

```
UITableView *feedsTableView;
self.aopDemo = [IMYAOPTableDemo new];
self.aopDemo.aopUtils = feedsTableView.aop_utils;
```



### 实现

#### 1.保存业务的Delegate/DataSource

#### 2.TableView的delegate/dataSource为IMYAOPTableViewUtils 

​	这个类的分类里实现了tableView的delegate和datasource里的所有方法，并进行section和row的处理判断，看是数据流的还是广告的，分别调用相应的方法。

#### 3.动态派生一个TableView的子类

个人理解：动态派生是为了解决自定义的tableView接入的问题。根据广告数据改变section和row，是为了无感，就是不影响原有的数据流。

#### 4.设置业务流的tableview的isa指针，指向派生的类

#### 5.设置动态创建TableView的子类的aop方法

动态派生的类里面根据runtime API添加UITableView.h文件中方法的实现，实现是在一个继承自tableview的类中写好的。实现中，会根据广告数据改变section和row，然后调用super的实现。



[参考](https://juejin.im/post/5cc183c7e51d456e3b7018c8)

collectionview的与tableview的类似。