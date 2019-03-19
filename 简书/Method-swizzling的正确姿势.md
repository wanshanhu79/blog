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
#endif
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
## 二、swizzling方式
```
@interface ZLLPersopn : NSObject
- (void)eatDrinkHaveFun;
@end

@interface ZLLStudent : ZLLPersopn
- (void)goodGoodStudy;
@end
```

如果要在类ZLLStudent的eatDrinkHaveFun方法的实现中加入ZLLStudent自己的东西，最简单的方式是在ZLLStudent中重写eatDrinkHaveFun方法了，但是对于不是我们写的类，比如系统提供的或者第三方提供的，就没法做到了。Swizzle的方式主要分为三种：
### 1.Swizzle的方法实现写在这个类的分类中
有两种思路，仅考虑实现，先不评说优劣。
* 仅影响当前类及其子类的方法实现，较为常用
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
这个实现中最关键的一句是class_addMethod这个，因为有好多类没有方法实现，都是从父类中继承来的，如果直接替换，相当于交换了父类这个方法的实现，但这个新的实现是在子类中的，父类的实例调用这个方法时，会崩溃。  
class_addMethod这句话的作用是如果当前类中没有待交换方法的实现，则把父类中的方法实现添加到当前类中。
* 父类中添加方法
向上查找，直到找到实现待替换方法的类，然后把新方法的实现加到找到的类
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
         //如果self未实现fromSel方法，而是继承父类的实现，直接swizzle，修改了父类方法fromSel的IMP，导致父类调用方法fromSel时，执行的是子类方法toSel的实现IMP，而在子类toSel实现中调用了自身toSel方法，去调用fromSel的实现IMP，而父类中未定义toSel方法，进而报错。
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
method_exchangeImplementations(fromMethod, class_getInstanceMethod(self, toSel))中 class_getInstanceMethod的self是关键点，不能是currentClassvc，不然这个方法不能使用了，会是一个死循环。  
不过这种操作，修改了父类的实现，有可能父类的其他子类不需要呢，故不适用。
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
## 危险性
[# [What are the Dangers of Method Swizzling in Objective C?](https://stackoverflow.com/questions/5339276/what-are-the-dangers-of-method-swizzling-in-objective-c)
](https://stackoverflow.com/questions/5339276/what-are-the-dangers-of-method-swizzling-in-objective-c)
* Method swizzling is not atomic
Method swizzling不是原子性操作。如果在+load方法里面写，是没有问题的，但是如果写在+initialize方法中就会出现一些奇怪的问题。
* Changes behavior of un-owned code
如果你在一个类中重写一个方法，并且不调用super方法，你可能会导致一些问题出现。在大多数情况下，super方法是期望被调用的（除非有特殊说明）。如果你是用同样的思想来进行Swizzling，可能就会引起很多问题。如果你不调用原始的方法实现，那么你Swizzling改变的越多就越不安全。
* Possible naming conflicts
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
* Swizzling changes the method's arguments
标准的Method Swizzling是不会改变方法参数的。使用Swizzling中，会改变传递给原来的一个函数实现的参数，例如：
```

[self my_setFrame:frame];
```
转换成
```
objc_msgSend(self, @selector(my_setFrame:), frame);
```
objc_msgSend会去查找my_setFrame对应的IMP。一旦IMP找到，会把相同的参数传递进去。这里会找到最原始的setFrame:方法，调用执行它。但是这里的_cmd参数并不是setFrame:，现在是my_setFrame:。原始的方法就被一个它不期待的接收参数调用了。

用方案三，用函数指针去实现。参数就不会变了。
* The order of swizzles matters
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

在load方法中加载swizzle，可以保证swizzle的顺序。load方法能保证父类会在其任何子类加载方法之前，加载相应的方法。
* Difficult to understand (looks recursive)
看着传统定义的swizzled method，我认为很难去预测会发生什么。但是对比上面标准的swizzling（方案三），还是很容易明白。这一点已经被解决了。
* Difficult to debug
在调试中，会出现奇怪的堆栈调用信息，尤其是swizzled的命名很混乱，一切方法调用都是混乱的。对比标准的swizzled方式，你会在堆栈中看到清晰的命名方法。swizzling还有一个比较难调试的一点， 在于你很难记住当前确切的哪个方法已经被swizzling了。

## 总结
我们常用的是方案一，方案二相对而言有些难理解，方案三相对来说，实现有些复杂，每个swizzling的方法都需要两个声明，一个定义，还是用函数方式来实现，不是OC语法。

应用场景，三种方案都应该在+load方法中调用，确保原子性、调用顺序，记得调用原方法实现。
* 方案一：通常用在对_cmd没有严格要求，或者不用_cmd来做事情的场合；通常用方法名前加前缀的方式来避免命名冲突；考虑当前类未实现要被swizzle的方法的应用场景。
* 方案二：要对某私有类来swizzling方法时，常采用；通常用方法名前加前缀的方式来避免命名冲突；考虑当前类未实现要被swizzle的方法的应用场景。
* 方案三：标准的swizzling方案，通常用在对_cmd有严格要求，或者用_cmd来做事情的场合；不需要考虑命名冲突；要用static修饰的变量来保存相关IMP，考虑函数和变量的命名冲突。
