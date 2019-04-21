## 前言
最近重看[神经病院Objective-C Runtime出院第三天——如何正确使用Runtime](https://www.jianshu.com/p/db6dc23834e3)，里面有部分对应到了面试中曾经被问到的**使用Method swizzling的注意事项**，着重的学习了下，并用代码实际验证了下。发现之前对Method swizzling的理解不够深，写的Method swizzling代码有很大漏洞，对于复杂业务场景考虑有很多不足，记录下自己的收获。

## 一、准备知识
__OBJC2__ 部分源码
```
//SEL
typedef struct objc_selector *SEL;
//IMP
#if !OBJC_OLD_DISPATCH_PROTOTYPES
typedef void (*IMP)(void /* id, SEL, ... */ );
#else
typedef id _Nullable (*IMP)(id _Nonnull, SEL _Nonnull, ...);
#endifÂ
//Method
typedef struct method_t *Method;
struct method_t {
    SEL name;
    const char *types;
    IMP imp;

    struct SortBySELAddress :
        public std::binary_function<const method_t&,
                                    const method_t&, bool>
    {
        bool operator() (const method_t& lhs,
                         const method_t& rhs)
        { return lhs.name < rhs.name; }
    };
};
```
### SEL
SEL又叫选择器，是表示一个方法的`selector`的指针，是一个方法的编号。  用于表示运行时方法的名字，Objective-C在编译时，会依据每一个方法的名字、参数序列，生成一个唯一的标识，这个标识就是SEL。
工程中的所有的SEL组成一个Set集合，SEL是唯一的。只要方法名一样（参数类型可以不一致），它的值就是一样的，不管这个方法定义于哪个类，是不是实例方法。  
不同的类可以拥有相同的selector，不同类的实例对象performSelector相同的selector时，会在各自的方法链表中根据 selector 去查找具体的方法实现IMP, 然后用这个方法实现去执行具体的实现代码。
### IMP
`IMP`指向方法实现的首地址，类似C语言的函数指针。IMP是消息最终调用的执行代码，是方法真正的实现代码 。

### Method
主要包含三部分
* 方法名：方法名为此方法的签名，有着相同函数名和参数名的方法有着相同的方法名。
* 方法类型：方法类型描述了参数的类型。
* IMP: IMP即函数指针，为方法具体实现代码块的地址，可像普通C函数调用一样使用IMP。

实际上相当于在SEL和IMP之间作了一个映射。有了SEL，我们便可以找到对应的IMP。

### Method Swizzling
Method Swizzling是一种改变一个selector的实际实现的技术。通过这一技术，我们可以在运行时通过修改类的分发表中selector对应的函数，来修改方法的实现。基于Runtime一系列强大的函数。

主要用到的函数如下：
```
OBJC_EXPORT BOOL
/**
如果本类中包含一个同名的实现，则函数返回为NO
*/
class_addMethod(Class _Nullable cls, SEL _Nonnull name, IMP _Nonnull imp,
                const char * _Nullable types) ;

OBJC_EXPORT IMP _Nullable
class_replaceMethod(Class _Nullable cls, SEL _Nonnull name, IMP _Nonnull imp,
                    const char * _Nullable types);

OBJC_EXPORT void
method_exchangeImplementations(Method _Nonnull m1, Method _Nonnull m2);
```
## 二、swizzling的方式

~~Swizzle的方式分为三种~~：
### 1.新的方法实现写在这个类的分类中
有个前提新的方法实现不是继承来的，继承来的没有测试。新方法有两种思路，仅考虑实现，先不评说优劣。
* 仅影响当前类及其子类的方法实现，较为常见

```
@interface NSObject (zll_Swizzle)
/// 交换方法实现，仅影响当前类，不影响父类
+ (void)swizzleIMPAffectSelfFromSel:(SEL)fromSel toSel:(SEL)toSel;
@end
@implementation NSObject (zll_Swizzle)

+ (void)swizzleIMPAffectSelfFromSel:(SEL)fromSel toSel:(SEL)toSel {

    Method fromMethod = class_getInstanceMethod(self, fromSel);
    Method toMethod= class_getInstanceMethod(self, toSel);


    if (fromMethod == NULL || toMethod == NULL) {
        return;
    }

    if (class_addMethod(self, fromSel, method_getImplementation(toMethod), method_getTypeEncoding(toMethod))) {
         //如果当前类未实现fromSel方法，而是从父类继承过来的方法实现，class_addMethod为YES
        class_replaceMethod(self, toSel, method_getImplementation(fromMethod), method_getTypeEncoding(fromMethod));
    }else{
        //当前类有自己的实现
        method_exchangeImplementations(fromMethod, toMethod);
    }
}

@end
```

这个实现中最关键的一句是 class_addMethod 这个，因为有可能类没有方法实现 fromSel，而是从父类中继承来的，如果直接替换，相当于交换了父类这个方法的实现，但这个新的实现是在子类中的，父类的实例调用这个方法时，会 crash。  
class_addMethod 这句话的作用是如果当前类中没有待交换方法的实现，则把父类中的方法实现添加到当前类中。

* 父类中添加方法  
向上查找，直到找到实现待替换方法的类，然后把新方法的 IMP 加到找到的类

```
+ (void)swizzleIMPAffectSuperFromSel:(SEL)fromSel toSel:(SEL)toSel
{

    IMP classIMP = NULL;
    IMP superclassIMP = NULL;
    Class superClass = NULL;
    Class currentClass = self;

    //找到真正实现fromSel的方法，而不是继承来的
    while (class_getInstanceMethod(currentClass, fromSel) ) {

        superClass = [currentClass superclass];
        classIMP = method_getImplementation(class_getInstanceMethod(currentClass, fromSel));
        superclassIMP = method_getImplementation(class_getInstanceMethod(superClass, fromSel));

        /*
         如果self未实现fromSel方法，而是继承自父类，直接swizzle，修改了父类方法fromSel的IMP，父类调用方法fromSel时，实际执行的是子类方法toSel的实现IMP，toSel中调用了toSel方法去执行fromSel的实现IMP，在方法列表中从父类中开始查找，因为实现是在子类，会找不到，故crash。
         */
        if (classIMP != superclassIMP) {


                /*
                 如果self未实现而是调用的父类的实现，则在实现这个方法的父类中添加toSel，实现为fromSel的实现，即只简单的更换了Method
                 */
                Method fromMethod = class_getInstanceMethod(self, fromSel);
                class_addMethod(currentClass, toSel, method_getImplementation(fromMethod), method_getTypeEncoding(fromMethod));

                method_exchangeImplementations(fromMethod, class_getInstanceMethod(self, toSel));

            break;
        }

        currentClass = superClass;
    }
}

@end
```
method_exchangeImplementations(fromMethod, class_getInstanceMethod(self, toSel)) 中 class_getInstanceMethod 的 self 是关键点，不能是currentClassvc，不然这个方法不能使用了，会是一个死循环。

ps：不过这种操作，修改了父类的实现，有可能父类的其他子类不需要呢，故不适用。还有就是在子类的中的新的实现中访问了子类特有的方法、属性或者实例变量，会crash。

### 2.Swizzle的方法实现写在其他类中
以AFN 3.2.0中的一端代码为例，也是从中受到的启发。
```
static inline void af_swizzleSelector(Class theClass, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(theClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(theClass, swizzledSelector);
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

static inline BOOL af_addMethod(Class theClass, SEL selector, Method method) {
    return class_addMethod(theClass, selector,  method_getImplementation(method),  method_getTypeEncoding(method));
}

@interface _AFURLSessionTaskSwizzling : NSObject

@end

@implementation _AFURLSessionTaskSwizzling

+ (void)load {
    if (NSClassFromString(@"NSURLSessionTask")) {

        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession * session = [NSURLSession sessionWithConfiguration:configuration];
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wnonnull"
        NSURLSessionDataTask *localDataTask = [session dataTaskWithURL:nil];
#pragma clang diagnostic pop
        IMP originalAFResumeIMP = method_getImplementation(class_getInstanceMethod([self class], @selector(af_resume)));
        Class currentClass = [localDataTask class];

        while (class_getInstanceMethod(currentClass, @selector(resume))) {
            Class superClass = [currentClass superclass];
            IMP classResumeIMP = method_getImplementation(class_getInstanceMethod(currentClass, @selector(resume)));
            IMP superclassResumeIMP = method_getImplementation(class_getInstanceMethod(superClass, @selector(resume)));
            if (classResumeIMP != superclassResumeIMP &&
                originalAFResumeIMP != classResumeIMP) {
                [self swizzleResumeAndSuspendMethodForClass:currentClass];
            }
            currentClass = [currentClass superclass];
        }

        [localDataTask cancel];
        [session finishTasksAndInvalidate];
    }
}

+ (void)swizzleResumeAndSuspendMethodForClass:(Class)theClass {
    Method afResumeMethod = class_getInstanceMethod(self, @selector(af_resume));
    Method afSuspendMethod = class_getInstanceMethod(self, @selector(af_suspend));

    if (af_addMethod(theClass, @selector(af_resume), afResumeMethod)) {
        af_swizzleSelector(theClass, @selector(resume), @selector(af_resume));
    }

    if (af_addMethod(theClass, @selector(af_suspend), afSuspendMethod)) {
        af_swizzleSelector(theClass, @selector(suspend), @selector(af_suspend));
    }
}
```
和上面类似，也有两种思路：
* 当前类增加方法

```
- (void)swizzleImpFromSel:(SEL)fromSel
                    toSel:(SEL)toSel
                 forClass:(Class)theClass
{

    Method fromMethod = class_getInstanceMethod(theClass, fromSel);
    Method toImpMethod= class_getInstanceMethod([self class], toSel);

    if (class_addMethod(theClass, toSel, method_getImplementation(toImpMethod), method_getTypeEncoding(toImpMethod))) {

        //如果当前类未实现fromSel方法，而是从父类继承过来的方法实现，class_addMethod为YES
        if (class_addMethod(theClass, fromSel, method_getImplementation(toImpMethod), method_getTypeEncoding(toImpMethod))) {

            class_replaceMethod(theClass, toSel, method_getImplementation(fromMethod), method_getTypeEncoding(fromMethod));
        }else{

            //这个地方一定注意，exchange的是theClass的两个方法
           Method toMethod= class_getInstanceMethod(theClass, toSel);
            method_exchangeImplementations(fromMethod, toMethod);
        }
    }

}
```

* 父类中添加方法

```
- (void)swizzleImpFromSel:(SEL)fromSel
                    toSel:(SEL)toSel
                 forClass:(Class)theClass
{
    IMP theClassIMP = NULL;
    IMP superclassIMP = NULL;
    Class superClass = NULL;
    //找到方法fromSel真正实现的类
    while (class_getInstanceMethod(theClass, fromSel) ) {
        superClass = [theClass superclass];
        theClassIMP = method_getImplementation(class_getInstanceMethod(theClass, fromSel));
        superclassIMP = method_getImplementation(class_getInstanceMethod(superClass, fromSel));
        //把toSel添加到真正实现了fromSel方法的类上面，避免在toSel方法实现中调用toSel方法，父类无法响应toSel方法
        if (theClassIMP != superclassIMP) {
             Method method = class_getInstanceMethod([self class], toSel);
            [self swizzleImpFromSel:fromSel toSel:toSel toMethod:method forClass:theClass];
            break;
        }
        theClass = superClass;
    }
}
- (void)swizzleImpFromSel:(SEL)fromSel
                    toSel:(SEL)toSel
                 toMethod:(Method)toMethod
                 forClass:(Class)theClass{
    if (class_addMethod(theClass, toSel, method_getImplementation(toMethod), method_getTypeEncoding(toMethod))) {
        Method fromMethod = class_getInstanceMethod(theClass, fromSel);
        Method toMethod = class_getInstanceMethod(theClass, toSel);
        method_exchangeImplementations(fromMethod, toMethod);
    }
}
```

### 3.直接使用函数指针

```
@implementation NSObject (Swizzle)
+ (void)swizzlleImpFromSel:(SEL)fromSel
                     toImp:(IMP)toImp
                     store:(IMP *)oldIMPPointer {
    IMP oldImp = NULL;
    Method method = class_getInstanceMethod(self, fromSel);
    if (method) {
        oldImp = class_replaceMethod(self, fromSel, toImp, method_getTypeEncoding(method));
        if (!oldImp) {
            oldImp = method_getImplementation(method);
        }
    }
    *oldIMPPointer = oldImp;
}
@end
//使用
static void MySetFrame(id self, SEL _cmd, CGRect frame);
static void (*SetFrameIMP)(id self, SEL _cmd, CGRect frame);

static void MySetFrame(id self, SEL _cmd, CGRect frame) {
    // do custom work
    NSLog(@"MySetFrame:%@", NSStringFromSelector(_cmd));
    SetFrameIMP(self, _cmd, frame);
}
- (void)viewDidLoad {
    [super viewDidLoad];
     [NSView swizzlle:@selector(setFrame:) with:(IMP)MySetFrame store:(IMP *)&SetFrameIMP];
}
```
方案的缺点是 没有直接用方法一目了然，需要两个声明，一个函数指针。如果要swizzling的方法比较多，写着会比较麻烦。

### Aspects的实现 - 在 forwardInvocation 中做文章
[Aspects](https://github.com/steipete/Aspects)，不会因子类未实现方法对它进行 `hook` 引起父类调用时crash。

对于待 `hook` 的 `selector`，新生成一个方法 `aliasSelector` 指向原来的`IMP`，原来的 `IMP` 替换为 `objc_msgForward / _objc_msgForward_stret`（这样当你直接调用原来方法时，就会执行消息转发的IMP，最终走到forwardInvocation方法，并携带相关参数）。hook`forwardInvocation`方法，添加自己的实现（在这里调用aliasSelector）。
```
static IMP aspect_getMsgForwardIMP(NSObject *self, SEL selector) {
    IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
    Method method = class_getInstanceMethod(self.class, selector);
    const char *encoding = method_getTypeEncoding(method);
    BOOL methodReturnsStructValue = encoding[0] == _C_STRUCT_B;
    if (methodReturnsStructValue) {
        @try {
            NSUInteger valueSize = 0;
            NSGetSizeAndAlignment(encoding, &valueSize, NULL);

            if (valueSize == 1 || valueSize == 2 || valueSize == 4 || valueSize == 8) {
                methodReturnsStructValue = NO;
            }
        } @catch (__unused NSException *e) {}
    }
    if (methodReturnsStructValue) {
        msgForwardIMP = (IMP)_objc_msgForward_stret;
    }
#endif
    return msgForwardIMP;
}

static void aspect_prepareClassAndHookSelector(NSObject *self, SEL selector, NSError **error) {
    NSCParameterAssert(selector);
    Class klass = aspect_hookClass(self, error);
    Method targetMethod = class_getInstanceMethod(klass, selector);
    IMP targetMethodIMP = method_getImplementation(targetMethod);
    if (!aspect_isMsgForwardIMP(targetMethodIMP)) {
        // Make a method alias for the existing method implementation, it not already copied.
        const char *typeEncoding = method_getTypeEncoding(targetMethod);
        SEL aliasSelector = aspect_aliasForSelector(selector);
        if (![klass instancesRespondToSelector:aliasSelector]) {
            __unused BOOL addedAlias = class_addMethod(klass, aliasSelector, method_getImplementation(targetMethod), typeEncoding);
            NSCAssert(addedAlias, @"Original implementation for %@ is already copied to %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(aliasSelector), klass);
        }

        // We use forwardInvocation to hook in.
        class_replaceMethod(klass, selector, aspect_getMsgForwardIMP(self, selector), typeEncoding);
        AspectLog(@"Aspects: Installed hook for -[%@ %@].", klass, NSStringFromSelector(selector));
    }
}
```

对于对象实例而言，实现的方式类似KVO的实现，派生一个当前类的子类，并将当期对象与子类关联，还要重写 `subclass` 以及其 `subclass metaclass` 的 `class` 方法,使他返回当前对象的 `class`。所有的 `swizzling` 操作都发生在子类，不需要改变对象本身的类。
```
static Class aspect_hookClass(NSObject *self, NSError **error) {

  ........
    // Default case. Create dynamic subclass.
	const char *subclassName = [className stringByAppendingString:AspectsSubclassSuffix].UTF8String;
	Class subclass = objc_getClass(subclassName);

	if (subclass == nil) {
		subclass = objc_allocateClassPair(baseClass, subclassName, 0);
		if (subclass == nil) {
            NSString *errrorDesc = [NSString stringWithFormat:@"objc_allocateClassPair failed to allocate class %s.", subclassName];
            AspectError(AspectErrorFailedToAllocateClassPair, errrorDesc);
            return nil;
        }

		aspect_swizzleForwardInvocation(subclass);
		aspect_hookedGetClass(subclass, statedClass);
		aspect_hookedGetClass(object_getClass(subclass), statedClass);
		objc_registerClassPair(subclass);
	}

	object_setClass(self, subclass);
	return subclass;
}
```
使用时根据hook的方法的参数和返回值调整传入的block的参数和返回值保持一致，当这个block的编码类型与hook的方法的编码类型不一致时报错。

但是如果有个框架跟 `Aspects` 的实现思路相似，比如 `JSPatch`，如果 `JSPatch` 在 `Aspects` 之前 `hook` 了相关方法，`Aspects` 不做判断直接 `hook` 相关方法则会导致新生成的 `aliasSelector` 方法指向已经替换为 `objc_msgForward / _objc_msgForward_stret`的实现，调用时重走 `forwardInvocation`，但 `invocation` 的 `selector` 已经变化为 `aliasSelector`，类没有实现这个不能响应，crash。
```
static void aspect_prepareClassAndHookSelector(NSObject *self, SEL selector, NSError **error) {
    NSCParameterAssert(selector);
    Class klass = aspect_hookClass(self, error);
    Method targetMethod = class_getInstanceMethod(klass, selector);
    IMP targetMethodIMP = method_getImplementation(targetMethod);
   if (!aspect_isMsgForwardIMP(targetMethodIMP)) {//这是很关键的一步，避免陷入循环
        // Make a method alias for the existing method implementation, it not already copied.
        const char *typeEncoding = method_getTypeEncoding(targetMethod);
        SEL aliasSelector = aspect_aliasForSelector(selector);
        if (![klass instancesRespondToSelector:aliasSelector]) {
            __unused BOOL addedAlias = class_addMethod(klass, aliasSelector, method_getImplementation(targetMethod), typeEncoding);
            NSCAssert(addedAlias, @"Original implementation for %@ is already copied to %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(aliasSelector), klass);
        }

        // We use forwardInvocation to hook in.
        class_replaceMethod(klass, selector, aspect_getMsgForwardIMP(self, selector), typeEncoding);
        AspectLog(@"Aspects: Installed hook for -[%@ %@].", klass, NSStringFromSelector(selector));
   }
}
```

参考:[面向切面编程之 Aspects 源码解析及应用](https://wereadteam.github.io/2016/06/30/Aspects/)
## 三、危险
[# [What are the Dangers of Method Swizzling in Objective C?](https://stackoverflow.com/questions/5339276/what-are-the-dangers-of-method-swizzling-in-objective-c)
](https://stackoverflow.com/questions/5339276/what-are-the-dangers-of-method-swizzling-in-objective-c)


### 1.Method swizzling is not atomic（不是线程安全）
Method swizzling 不是原子性操作。如果在+load方法里面写，是没有问题的，但是如果写在+initialize方法中就会出现一些奇怪的问题。
### 2.Changes behavior of un-owned code（改变了代码本来的行为）
 如果你在一个类中重写一个方法，并且不调用super方法，你可能会导致一些问题出现。在大多数情况下，super方法是期望被调用的（除非有特殊说明）。如果你是用同样的思想来进行Swizzling，可能就会引起很多问题。如果你不调用原始的方法实现，那么你Swizzling改变的越多就越不安全。
### 3.Possible naming conflicts（命名冲突）
命名冲突是程序开发中经常遇到的一个问题。我们经常在类别中的前缀类名称和方法名称。不幸的是，命名冲突是在我们程序中的像一种瘟疫。一般我们用**方案一**的方式来写Method Swizzling

```
@interface NSView : NSObject
- (void)setFrame:(CGRect)frame;
@end

@implementation NSView
- (void)setFrame:(CGRect)frame {
    NSLog(@"setFrame:%@", NSStringFromSelector(_cmd));
}

- (void)my_viewSetFrame:(CGRect)frame {
    NSLog(@"%@..my_viewSetFrame", self);
    [self my_viewSetFrame:frame];
}
+ (void)load {
    [self swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_setFrame:)];
}
@end

```

但是如果程序的其他地方也定义了`my_viewSetFrame :`呢，那么会造成命名冲突的问题。  
最好的方式是使用方案三，能有效的避免命名冲突的问题。原则上来说，其实上述做法更加符合标准化的Swizzling方法。
### 4.Swizzling changes the method's arguments（改变了参数 \_cmd）

标准的Method Swizzling是不会改变方法参数的。使用Swizzling中，会改变传递给原来的一个函数实现的参数，例如：
`[self my_setFrame:frame];`
转换成
`objc_msgSend(self, @selector(my_setFrame:), frame);`

objc_msgSend会去查找my_setFrame对应的IMP。一旦IMP找到，会把相同的参数传递进去。这里会找到最原始的setFrame:方法，调用执行它。但是这里的_cmd参数并不是setFrame:，现在是my_setFrame:。原始的方法就被一个它不期待的接收参数调用了。

用方案三，用函数指针去实现。参数就不会变了。
### 5.The order of swizzles matters（顺序，因为继承、分类引起的）
调用顺序对于Swizzling来说，很重要。
以方案一为例

```
@interface NSView : NSObject
- (void)setFrame:(CGRect)frame;
@end

@implementation NSView
- (void)setFrame:(CGRect)frame {
    NSLog(@"setFrame:%@", NSStringFromSelector(_cmd));
}

- (void)my_viewSetFrame:(CGRect)frame {
    NSLog(@"%@..my_viewSetFrame", self);
    [self my_viewSetFrame:frame];
}

@end

@interface NSContol : NSView

@end

@implementation NSContol
- (void)my_controlSetFrame:(CGRect)frame
{
    NSLog(@"%@..my_controlSetFrame", self);
    [self my_controlSetFrame:frame];
}

@end

@interface NSButton : NSContol
@end

@implementation NSButton
- (void)my_buttonSetFrame:(CGRect)frame
{
    NSLog(@"%@..my_buttonSetFrame", self);
    [self my_buttonSetFrame:frame];
}
@end
#pragma mark - 调用
- (void)viewDidLoad {
    [super viewDidLoad];
      [NSButton swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_buttonSetFrame:)];
    [NSContol swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_controlSetFrame:)];
    [NSView swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_viewSetFrame:)];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    NSButton *btn = [[NSButton alloc] init];
    btn.frame = CGRectMake(0, 0, 100, 200);

    NSContol *con = [[NSContol alloc] init];
    con.frame = CGRectMake(0, 0, 100, 200);

    NSView *view = [[NSView alloc] init];
    view.frame = CGRectMake(0, 0, 100, 200);
}
#pragma mark - 打印顺序一
     [NSButton swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_buttonSetFrame:)];
     [NSContol swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_controlSetFrame:)];
      [NSView swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_viewSetFrame:)];
//打印结果
<NSButton: 0x60c000005820>..my_buttonSetFrame
setFrame:my_buttonSetFrame:
<NSContol: 0x60c000005990>..my_controlSetFrame
setFrame:my_controlSetFrame:
<NSView: 0x604000005730>..my_viewSetFrame
setFrame:my_viewSetFrame:

#pragma mark - 打印顺序二
  [NSView swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_viewSetFrame:)];
  [NSContol swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_controlSetFrame:)];
  [NSButton swizzleImpFromSel:@selector(setFrame:) toSel:@selector(my_buttonSetFrame:)];
//打印结果
<NSButton: 0x6040000189a0>..my_buttonSetFrame
<NSButton: 0x6040000189a0>..my_controlSetFrame
<NSButton: 0x6040000189a0>..my_viewSetFrame
setFrame:my_viewSetFrame:
<NSContol: 0x60c000018740>..my_controlSetFrame
<NSContol: 0x60c000018740>..my_viewSetFrame
setFrame:my_viewSetFrame:
<NSView: 0x604000202ee0>..my_viewSetFrame
setFrame:my_viewSetFrame:
```

在load方法中加载swizzle，可以保证swizzle的顺序。load方法能保证父类会在其任何子类加载方法之前，加载相应的方法。但父类中Category的load方法加载在子类之后，

### 6.Difficult to understand (难以理解)
看着传统定义的swizzled method，我认为很难去预测会发生什么。但是对比上面标准的swizzling（方案三），还是很容易明白。这一点已经被解决了。
### 7.Difficult to debug（难以调试）
在调试中，会出现奇怪的堆栈调用信息，尤其是swizzled的命名很混乱，一切方法调用都是混乱的。对比标准的swizzled方式，你会在堆栈中看到清晰的命名方法。swizzling还有一个比较难调试的一点， 在于你很难记住当前确切的哪个方法已经被swizzling了。

假设这样一种场景，父类A中实现了 `foo` 方法，在扩展中的 `＋load` 中进行了 `swizzle` ，`swizzling` 方法是 `A_foo`，子类B在 `+load` 中也对 `foo` 进行了 `swizzle`，`swizzling` 方法是 `B_foo`，在向对象B发送消息的时候，我们期望的执行顺序是 `B_foo -> A_foo -> foo`，但是实际的执行顺序却是 `A_foo -> B_foo -> foo`,顺序与我们的期望的不符，不过还好三个方法全都执行了。顺序异常的原因是 `+load` 方法的的执行顺序是先执行类中的实现，再执行扩展中的实现，这一点可以通过运行时开源代码中的 `call_load_methods` 看到。

## 四、解决方案 - RSSwizzle
RSSwizzle 使用了函数指针的方式来解决危险，但它是怎么处理上面的那个场景呢？

```
static void swizzle(Class classToSwizzle,
                    SEL selector,
                    RSSwizzleImpFactoryBlock factoryBlock)
{
    Method method = class_getInstanceMethod(classToSwizzle, selector);

    NSCAssert(NULL != method,
              @"Selector %@ not found in %@ methods of class %@.",
              NSStringFromSelector(selector),
              class_isMetaClass(classToSwizzle) ? @"class" : @"instance",
              classToSwizzle);

    NSCAssert(blockIsAnImpFactoryBlock(factoryBlock),
             @"Wrong type of implementation factory block.");

    __block OSSpinLock lock = OS_SPINLOCK_INIT;
    // To keep things thread-safe, we fill in the originalIMP later,
    // with the result of the class_replaceMethod call below.
    __block IMP originalIMP = NULL;

    // This block will be called by the client to get original implementation and call it.
    RSSWizzleImpProvider originalImpProvider = ^IMP{
        // It's possible that another thread can call the method between the call to
        // class_replaceMethod and its return value being set.
        // So to be sure originalIMP has the right value, we need a lock.
        OSSpinLockLock(&lock);
        IMP imp = originalIMP;
        OSSpinLockUnlock(&lock);

        if (NULL == imp){
            // If the class does not implement the method
            // we need to find an implementation in one of the superclasses.
            Class superclass = class_getSuperclass(classToSwizzle);
            imp = method_getImplementation(class_getInstanceMethod(superclass,selector));
        }
        return imp;
    };

    RSSwizzleInfo *swizzleInfo = [RSSwizzleInfo new];
    swizzleInfo.selector = selector;
    swizzleInfo.impProviderBlock = originalImpProvider;

    // We ask the client for the new implementation block.
    // We pass swizzleInfo as an argument to factory block, so the client can
    // call original implementation from the new implementation.
    id newIMPBlock = factoryBlock(swizzleInfo);

    const char *methodType = method_getTypeEncoding(method);

    NSCAssert(blockIsCompatibleWithMethodType(newIMPBlock,methodType),
             @"Block returned from factory is not compatible with method type.");

    IMP newIMP = imp_implementationWithBlock(newIMPBlock);

    // Atomically replace the original method with our new implementation.
    // This will ensure that if someone else's code on another thread is messing
    // with the class' method list too, we always have a valid method at all times.
    //
    // If the class does not implement the method itself then
    // class_replaceMethod returns NULL and superclasses's implementation will be used.
    //
    // We need a lock to be sure that originalIMP has the right value in the
    // originalImpProvider block above.
    OSSpinLockLock(&lock);
    originalIMP = class_replaceMethod(classToSwizzle, selector, newIMP, methodType);
    OSSpinLockUnlock(&lock);
}
```

要求外面传进来的 `block` 接受一个 `RSSwizzleInfo` 的参数返回一个 `newBlock`，并且这个 `newBlock` 的返回值跟要 `hook` 的方法保持一致，参数比方法的多一个 `self`，会进行校验：
* 用 `newBlock` 生成新的IMP
* 生成 `RSSwizzleInfo` 实例，记录相关信息，获取原始IMP的 `block`
* 替换IMP，拿到原始IMP
* 从参数中拿到当时保存的获得IMP的block
* 由于block中存储的是originIMP ，所以获得的是原始的实现

调用不太友好，比较难懂。由于方法返回值的不定，不好通过代码把相关类型固定，优化代码。
```
SEL selector = @selector(calculate:);
[RSSwizzle
 swizzleInstanceMethod:selector
 inClass:classToSwizzle
 newImpFactory:^id(RSSWizzleInfo *swizzleInfo) {
     // This block will be used as the new implementation.
     return ^int(__unsafe_unretained id self, int num){
         // You MUST always cast implementation to the correct function pointer.
         int (*originalIMP)(__unsafe_unretained id, SEL, int);
         originalIMP = (__typeof(originalIMP))[swizzleInfo getOriginalImplementation];
         // Calling original implementation.
         int res = originalIMP(self,selector,num);
         // Returning modified return value.
         return res + 1;
     };
 }
 mode:RSSwizzleModeAlways
 key:NULL];
```

修改RSSwizzleOriginalIMP，在代码中就不需要进行强转，不过要自己心里清楚，要进行相关的参数匹配
```
/**改动
 A function pointer to the original implementation of the swizzled method.
 */
typedef void (*RSSwizzleOriginalIMP)(id, SEL, ...);

//调用
SEL selector = @selector(calculate:);
[RSSwizzle
 swizzleInstanceMethod:selector
 inClass:classToSwizzle
 newImpFactory:^id(RSSWizzleInfo *swizzleInfo) {
     // This block will be used as the new implementation.
     return ^int(__unsafe_unretained id self, int num){

        RSSwizzleOriginalIMP originalIMP = [swizzleInfo getOriginalImplementation];
         // Calling original implementation.
         int res = originalIMP(self,selector,num);
         // Returning modified return value.
         return res + 1;
     };
 }
 mode:RSSwizzleModeAlways
 key:NULL];

```

ps：`imp_implementationWithBlock()`它的第一个参数是id 类型的，相当于IMP中的 `self`，后面的是block传递进来的参数。

## 五、思考
这是核武器，用着感觉很方便，但一定要注意风险、少用。特别是项目大的时候，很容易出现各种问题，还不容易调试。一个好的框架要考虑各种情况，个人出现的可能性不大，但用户多时就会遇到各种问题。

### class_ 系列函数
修改时只修改当前类的信息，不影响父类（要是能改父类的信息，岂不乱套了），访问（即读取）时可以访问父类的信息，即走消息响应列表。

```
BOOL class_addMethod(Class _Nullable cls,
                       SEL _Nonnull name,
                        IMP _Nonnull imp,
            const char * _Nullable types);

IMP  class_replaceMethod(Class _Nullable cls,
                           SEL _Nonnull name,
                            IMP _Nonnull imp,
                const char * _Nullable types);
```
