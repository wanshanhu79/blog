在项目中看到不少地方使用 `dispatch_async(dispatch_get_main_queue(), ^{ });` 的地方，感觉有些疑惑，为啥这样做，有啥好处。

block中的代码执行时机是在下次RunLoop的时候吗，如果不是这样完全是画蛇添足的。验证代码如下：

```
// 监听主线程runloop的状态的切换,当前页面使push进来的
- (void)viewDidLoad {
    [super viewDidLoad];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"..%@..", @"11");
    });
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSLog(@"viewWillAppear:%@", @"22");
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSLog(@"viewDidAppear:%@", @"33");
}

//执行顺序如下
刚从睡眠中唤醒
即将处理timer
即将处理source
viewWillAppear:22
..11..
即将处理timer
即将处理source
即将处理timer
即将处理source
即将处理timer
即将处理source
即将进入睡眠
刚从睡眠中唤醒
即将处理timer
即将处理source
即将进入睡眠
刚从睡眠中唤醒
即将处理timer
即将处理source
即将进入睡眠
刚从睡眠中唤醒
即将处理timer
即将处理source
即将进入睡眠
刚从睡眠中唤醒
viewDidAppear:33
```

****

**`dispatch_async(dispatch_get_main_queue(), ^{ });`不会在下一个runloop中执行**。为什么呢，只能从源码入手了。

摘自[源码 CF-1153.18](https://opensource.apple.com/source/CF/) 

## 一.什么是RunLoop

一般情况下，一个线程执行完之后就会停止。为了保证线程能随时处理事件而不退出，就需要循环的做一些事。

```
void CFRunLoopRun(void) {    /* DOES CALLOUT */
    int32_t result;
    do {
        result = CFRunLoopRunSpecific(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 1.0e10, false);
        CHECK_FOR_FORK();
    } while (kCFRunLoopRunStopped != result && kCFRunLoopRunFinished != result);
}
```

这种模型叫事件循环，**实现这种模型的关键点就是如何在没有消息到来的情况下休眠以避免系统资源的占用，消息一到来立刻恢复**

RunLoop就是这样的Event Loop模型。



## 二.RunLoop内部数据结构

Core Foundation中关于RunLoop的几个类

### 1.CFRunLoopRef

对外暴露的对象，外界通过CFRunLoopRef的接口来管理整个RunLoop

```
struct __CFRunLoop {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;          /* locked for accessing mode list */
    __CFPort _wakeUpPort;           // used for CFRunLoopWakeUp
    Boolean _unused;
    volatile _per_run_data *_perRunData;              // reset for runs of the run loop
    pthread_t _pthread; //runloop对应的线程
    uint32_t _winthread;
    CFMutableSetRef _commonModes;//存储的是字符串，记录所有标记为common的mode
    CFMutableSetRef _commonModeItems;//存储所有commonMode的item(source、timer、observer)
    CFRunLoopModeRef _currentMode;//当前运行的mode
    CFMutableSetRef _modes;//存储的是CFRunLoopModeRef，
    struct _block_item *_blocks_head;
    struct _block_item *_blocks_tail;
    CFAbsoluteTime _runTime;
    CFAbsoluteTime _sleepTime;
    CFTypeRef _counterpart;
};
```

RunLoop包含一个线程，和线程是一一对应的。有若干个Mode，但在一个时间点的只能有一个mode。如果需要切换Mode，只能退出Loop，再重新指定一个Mode进入。这样做主要是为了分隔开不同组的Source/Timer/Observer，让其互不影响。

### 2.CFRunLoopMode

```
struct __CFRunLoopMode {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;  /* must have the run loop locked before locking this */
    CFStringRef _name;   //mode名称
    Boolean _stopped;    //mode是否被终止
    char _padding[3];
    
    //几种事件，下面这四个字段，在苹果官方文档里面称为Item。runloop中有个commomitems字段，里面就是保持的下面这些内容。
    CFMutableSetRef _sources0;  //sources0
    CFMutableSetRef _sources1;  //sources1
    CFMutableArrayRef _observers; //观察者
    CFMutableArrayRef _timers;    //定时器
    
    CFMutableDictionaryRef _portToV1SourceMap; //字典  key是mach_port_t，value是CFRunLoopSourceRef
    __CFPortSet _portSet; //保存所有需要监听的port，比如_wakeUpPort，_timerPort都保存在这个数组中
    
    CFIndex _observerMask;
#if USE_DISPATCH_SOURCE_FOR_TIMERS
    dispatch_source_t _timerSource;
    dispatch_queue_t _queue;
    Boolean _timerFired; // set to true by the source when a timer has fired
    Boolean _dispatchTimerArmed;
#endif
#if USE_MK_TIMER_TOO
    mach_port_t _timerPort;
    Boolean _mkTimerArmed;
#endif
    uint64_t _timerSoftDeadline; /* TSR */
    uint64_t _timerHardDeadline; /* TSR */
};
```

source、timer、observer可以在多个mode中注册，但是只有runloop当前的currentmode下的source、timer、observer才可以运行。

### 3.CFRunLoopSource

```
struct __CFRunLoopSource {
    CFRuntimeBase _base;
    uint32_t _bits; //用于标记Signaled状态，source0只有在被标记为Signaled状态，才会被处理
    pthread_mutex_t _lock;
    CFIndex _order;         /* immutable */
    CFMutableBagRef _runLoops;
    union {
        CFRunLoopSourceContext version0;     /* immutable, except invalidation */
        CFRunLoopSourceContext1 version1;    /* immutable, except invalidation */
    } _context;
} ;

/** source0只包含了一个回调（函数指针），source0需要手动触发的Source，它并不能主动触发事件，x必须先把它标记为signal状态。使用时，你需要先调用 CFRunLoopSourceSignal(source)，将这个 Source 标记为待处理，也就是通过uint32_t _bits来实现的 ，只要_bits标记signled状态才会被处理，然后手动调用 CFRunLoopWakeUp(runloop) 来唤醒Runloop，让其处理这个事件 */
typedef struct {
    CFIndex version;
    void *  info;
    const void *(*retain)(const void *info);
    void    (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
    Boolean (*equal)(const void *info1, const void *info2);
    CFHashCode  (*hash)(const void *info);
    void    (*schedule)(void *info, CFRunLoopRef rl, CFStringRef mode);//当source加入到mode触发的回调
    void    (*cancel)(void *info, CFRunLoopRef rl, CFStringRef mode);//当source从runloop中移除时触发的回调
    void    (*perform)(void *info);//当source事件被触发时的回调，使用CFRunLoopSourceSignal方式触发。
} CFRunLoopSourceContext;

// source1结构体
/**
 包含了一个mach_port和一个回调（函数指针），被用于通过内核和其他线程相互发送消息。这个Source能主动唤醒RunLoop的线程。更加偏向于底层
 */
typedef struct {
    CFIndex version;
    void *  info;
    const void *(*retain)(const void *info);
    void    (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
    Boolean (*equal)(const void *info1, const void *info2);
    CFHashCode  (*hash)(const void *info);
#if (TARGET_OS_MAC && !(TARGET_OS_EMBEDDED || TARGET_OS_IPHONE)) || (TARGET_OS_EMBEDDED || TARGET_OS_IPHONE)
    mach_port_t (*getPort)(void *info);//当source被添加到mode中的时候，从这个函数中获得具体mach_port_t。
    void *  (*perform)(void *msg, CFIndex size, CFAllocatorRef allocator, void *info);
#else
    void *  (*getPort)(void *info);
    void    (*perform)(void *info);
#endif
} CFRunLoopSourceContext1;
```

__CFRunLoopSource 是事件产生的地方，有两种：Source0和Source1。

* Source0只包含了一个回调，是需要手动触发的Source（**触摸事件、 performSelector:onThread: **），它不能主动触发事件，必须要要先把它标记为signal状态。**使用时，你需要先调用 CFRunLoopSourceSignal(source)，将这个 Source 标记为待处理，也就是通过uint32_t _bits来实现的**，只有_bits标记Signaled状态才会被处理。然后手动调用 CFRunLoopWakeUp(runloop) 来唤醒 RunLoop，让其处理这个事件。
* Source1包含了一个port和一个回调。被用于通过内核和其他线程相互发送消息。更加偏向底层。**基于port的线程间通信，系统事件捕捉**

一个source可以被添加到多个runloop中，即多个线程中。

### 4.CFRunLoopTimer

```
struct __CFRunLoopTimer {
    CFRuntimeBase _base;
    uint16_t _bits;  //标记fire状态
    pthread_mutex_t _lock;
    CFRunLoopRef _runLoop;        //添加该timer的runloop
    CFMutableSetRef _rlModes;     //存放所有包含该timer的 mode的 modeName，意味着一个timer可能会在多个mode中存在
    CFAbsoluteTime _nextFireDate;
    CFTimeInterval _interval;     //理想时间间隔  /* immutable */
    CFTimeInterval _tolerance;    //时间偏差      /* mutable */
    uint64_t _fireTSR;          /* TSR units */
    CFIndex _order;         /* immutable */
    CFRunLoopTimerCallBack _callout;    /* immutable */
    CFRunLoopTimerContext _context; /* immutable, except invalidation */
};
```

它和 NSTimer 是toll-free bridged 的，可以混用。其包含一个时间长度和一个回调（函数指针）。当其加入到 RunLoop 时，RunLoop会注册对应的时间点，当时间点到时，RunLoop会被唤醒以执行那个回调。

一个timer只能存在与一个runloop中的多个mode下。

### 5.CFRunLoopObserver

```
struct __CFRunLoopObserver {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;
    CFRunLoopRef _runLoop;
    CFIndex _rlCount;
    CFOptionFlags _activities;      /* immutable */
    CFIndex _order;         /* immutable */
    CFRunLoopObserverCallBack _callout; /* immutable  设置回调函数*/
    CFRunLoopObserverContext _context;  /* immutable, except invalidation */
};

/* Run Loop Observer Activities */
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0), //即将进入run loop
    kCFRunLoopBeforeTimers = (1UL << 1), //即将处理timer
    kCFRunLoopBeforeSources = (1UL << 2),//即将处理source
    kCFRunLoopBeforeWaiting = (1UL << 5),//即将进入休眠
    kCFRunLoopAfterWaiting = (1UL << 6),//被唤醒但是还没开始处理事件
    kCFRunLoopExit = (1UL << 7),//run loop已经退出
    kCFRunLoopAllActivities = 0x0FFFFFFFU
};
```

**小结**

runloop其中有个commonds的数组，里面保存的是被标记为common的mode。这种标记为common的mode有种特性，那就是当RunLoop的内容发生变化时，RunLoop都会将commonModeItems里的Source/Observer/Timer 同步到具有 “Common” 标记的所有mode里。

## 三、RunLoop内部逻辑

如果RunLoop的Mode中没有一个source、timer、block，RunLoop会直接退出。

```
//rlm 即将切换到的model previousMode 当前正在运行的model
static Boolean __CFRunLoopModeIsEmpty(CFRunLoopRef rl, CFRunLoopModeRef rlm, CFRunLoopModeRef previousMode) {
    CHECK_FOR_FORK();
    if (NULL == rlm) return true;

    //pthread_main_np ( ) : 获取主线程
    //HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY 是对列发的消息
    //_CFGetTSD(__CFTSDKeyIsInGCDMainQ) 不在主对列
    Boolean libdispatchQSafe = pthread_main_np() && ((HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && NULL == previousMode) || (!HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && 0 == _CFGetTSD(__CFTSDKeyIsInGCDMainQ)));
    if (libdispatchQSafe && (CFRunLoopGetMain() == rl) && CFSetContainsValue(rl->_commonModes, rlm->_name)) return false; // represents the libdispatch main queue
    // 有sources0
    if (NULL != rlm->_sources0 && 0 < CFSetGetCount(rlm->_sources0)) return false;
    // 有sources1
    if (NULL != rlm->_sources1 && 0 < CFSetGetCount(rlm->_sources1)) return false;
    // 有timers
    if (NULL != rlm->_timers && 0 < CFArrayGetCount(rlm->_timers)) return false;
    
    // 是否有可执行的block，即gcd
    struct _block_item *item = rl->_blocks_head;
    while (item) {
        struct _block_item *curr = item;
        item = item->_next;
        Boolean doit = false;
        if (CFStringGetTypeID() == CFGetTypeID(curr->_mode)) {
            doit = CFEqual(curr->_mode, rlm->_name) || (CFEqual(curr->_mode, kCFRunLoopCommonModes) && CFSetContainsValue(rl->_commonModes, rlm->_name));
        } else {
            doit = CFSetContainsValue((CFSetRef)curr->_mode, rlm->_name) || (CFSetContainsValue((CFSetRef)curr->_mode, kCFRunLoopCommonModes) && CFSetContainsValue(rl->_commonModes, rlm->_name));
        }
        if (doit) return false;
    }
    return true;
}
```

## 四、Runloop执行过程

#### **CFRunLoopRun（入口函数）**

```
void CFRunLoopRun(void) {    /* DOES CALLOUT */
    int32_t result;
    do {
        result = CFRunLoopRunSpecific(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 1.0e10, false);
        CHECK_FOR_FORK();
    } while (kCFRunLoopRunStopped != result && kCFRunLoopRunFinished != result);
}
```

#### CFRunLoopRunInMode

```
SInt32 CFRunLoopRunInMode(CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
    CHECK_FOR_FORK();
    return CFRunLoopRunSpecific(CFRunLoopGetCurrent(), modeName, seconds, returnAfterSourceHandled);
}
```

#### CFRunLoopRunSpecific

```
SInt32 CFRunLoopRunSpecific(CFRunLoopRef rl, CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
    CHECK_FOR_FORK();
    // runloop 已经销毁
    if (__CFRunLoopIsDeallocating(rl)) return kCFRunLoopRunFinished;
    // runloop 加锁
    __CFRunLoopLock(rl);
    // 获取mode
    CFRunLoopModeRef currentMode = __CFRunLoopFindMode(rl, modeName, false);
    // model 不存在，或者没有source0、source1、timer、block事件要处理
    if (NULL == currentMode || __CFRunLoopModeIsEmpty(rl, currentMode, rl->_currentMode)) {
        Boolean did = false;
        if (currentMode) __CFRunLoopModeUnlock(currentMode);
        __CFRunLoopUnlock(rl);
        return did ? kCFRunLoopRunHandledSource : kCFRunLoopRunFinished;
    }
    volatile _per_run_data *previousPerRun = __CFRunLoopPushPerRunData(rl);
    // 切换model
    CFRunLoopModeRef previousMode = rl->_currentMode;
    rl->_currentMode = currentMode;
    int32_t result = kCFRunLoopRunFinished;
    //1. 通知observer 即将进入runloop
    if (currentMode->_observerMask & kCFRunLoopEntry ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
    // runloop 运行循环
    result = __CFRunLoopRun(rl, currentMode, seconds, returnAfterSourceHandled, previousMode);
    // 10.通知observer即将推出runloop
    if (currentMode->_observerMask & kCFRunLoopExit ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);
    
    __CFRunLoopModeUnlock(currentMode);
    __CFRunLoopPopPerRunData(rl, previousPerRun);
    // 回到之前的model
    rl->_currentMode = previousMode;
    __CFRunLoopUnlock(rl);
    return result;
}
```

#### __CFRunloopRun

```
#define TIMER_INTERVAL_LIMIT    504911232.0
/**
 seconds：纳秒
 returnAfterSourceHandled 是否处理完事件就返回
 */
static int32_t __CFRunLoopRun(CFRunLoopRef rl, CFRunLoopModeRef rlm, CFTimeInterval seconds, Boolean stopAfterHandle, CFRunLoopModeRef previousMode) {
    //获取时间
    uint64_t startTSR = mach_absolute_time();
    
    // 是不是停止状态
    if (__CFRunLoopIsStopped(rl)) {
        __CFRunLoopUnsetStopped(rl);
        return kCFRunLoopRunStopped;
    } else if (rlm->_stopped) {
        rlm->_stopped = false;
        return kCFRunLoopRunStopped;
    }
    
    // mach 端口，在内核中，消息在端口之间传递。初始为0
    mach_port_name_t dispatchPort = MACH_PORT_NULL;
    //pthread_main_np ( ) : 获取主线程
    //HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY 是对列发的消息
    //_CFGetTSD(__CFTSDKeyIsInGCDMainQ) 不在主对列
    Boolean libdispatchQSafe = pthread_main_np() && ((HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && NULL == previousMode) || (!HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && 0 == _CFGetTSD(__CFTSDKeyIsInGCDMainQ)));
    // 如果在主线程 并且 runloop是主线程的runloop 并且 该model是commonModel ，则给mach端口赋值为主线程收发消息的端口
    if (libdispatchQSafe && (CFRunLoopGetMain() == rl) && CFSetContainsValue(rl->_commonModes, rlm->_name)) dispatchPort = _dispatch_get_main_queue_port_4CF();
    
#if USE_DISPATCH_SOURCE_FOR_TIMERS
    mach_port_name_t modeQueuePort = MACH_PORT_NULL;
    if (rlm->_queue) {
        /// model线程端口
        modeQueuePort = _dispatch_runloop_root_queue_get_port_4CF(rlm->_queue);
        if (!modeQueuePort) {
            CRASH("Unable to get port for run loop mode queue (%d)", -1);
        }
    }
#endif
    // GCD 管理的定时器，用于实现runloop超时机制
    dispatch_source_t timeout_timer = NULL;
    struct __timeout_context *timeout_context = (struct __timeout_context *)malloc(sizeof(*timeout_context));
    if (seconds <= 0.0) { // instant timeout 立即超时
        seconds = 0.0;
        timeout_context->termTSR = 0ULL;
    } else if (seconds <= TIMER_INTERVAL_LIMIT) {
        dispatch_queue_t queue = pthread_main_np() ? __CFDispatchQueueGetGenericMatchingMain() : __CFDispatchQueueGetGenericBackground();
        timeout_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_retain(timeout_timer);
        timeout_context->ds = timeout_timer;
        timeout_context->rl = (CFRunLoopRef)CFRetain(rl);
        timeout_context->termTSR = startTSR + __CFTimeIntervalToTSR(seconds);
        dispatch_set_context(timeout_timer, timeout_context); // source gets ownership of context
        dispatch_source_set_event_handler_f(timeout_timer, __CFRunLoopTimeout);
        dispatch_source_set_cancel_handler_f(timeout_timer, __CFRunLoopTimeoutCancel);
        uint64_t ns_at = (uint64_t)((__CFTSRToTimeInterval(startTSR) + seconds) * 1000000000ULL);
        dispatch_source_set_timer(timeout_timer, dispatch_time(1, ns_at), DISPATCH_TIME_FOREVER, 1000ULL);
        dispatch_resume(timeout_timer);
    } else { // infinite timeout 永不超时
        seconds = 9999999999.0;
        timeout_context->termTSR = UINT64_MAX;
    }
    
    /// 标志位默认为true
    Boolean didDispatchPortLastTime = true;
    int32_t retVal = 0;
    do {
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        voucher_mach_msg_state_t voucherState = VOUCHER_MACH_MSG_STATE_UNCHANGED;
        voucher_t voucherCopy = NULL;
#endif
        // 初始化一个存放内核消息的缓冲池
        uint8_t msg_buffer[3 * 1024];
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        mach_msg_header_t *msg = NULL;
        mach_port_t livePort = MACH_PORT_NULL;
#endif
        //所有要需要监听的port
        __CFPortSet waitSet = rlm->_portSet;
        /// 设置runloop为可以唤醒状态
        __CFRunLoopUnsetIgnoreWakeUps(rl);
        
        /// 2.通知observer，即将触发timer回调，处理timer事件
        if (rlm->_observerMask & kCFRunLoopBeforeTimers) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeTimers);
        //// 3.通知observer，即将触发source回调
        if (rlm->_observerMask & kCFRunLoopBeforeSources) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeSources);
        /// .处理加入当前runloop的block
        __CFRunLoopDoBlocks(rl, rlm);
        
        /// 4.处理source0事件，有没有事件要处理
        Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
        if (sourceHandledThisLoop) {
            ///处理加入当前runloop的block
            __CFRunLoopDoBlocks(rl, rlm);
        }
        
        /// 如果有source0事件处理或者超时，为true
        Boolean poll = sourceHandledThisLoop || (0ULL == timeout_context->termTSR);
        
        /// 第一次do.. while循环不会走该分支，因为didDispatchPortLastTime为true
        if (MACH_PORT_NULL != dispatchPort && !didDispatchPortLastTime) {
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
            /// 从缓冲区读取消息
            msg = (mach_msg_header_t *)msg_buffer;
            /// 5.接受到dispatchPort 端口的信息 source1事件
            if (__CFRunLoopServiceMachPort(dispatchPort, &msg, sizeof(msg_buffer), &livePort, 0, &voucherState, NULL)) {
                /// 如果接受到了消息的话，前往第9步开始处理
                goto handle_msg;
            }
#endif
        }
        //表明不是第一次走了，下次要先看有没有source1事件
        didDispatchPortLastTime = false;
        
        //// 如果没有source0事件或者没有超时
        //// 6.即将进入休眠
        if (!poll && (rlm->_observerMask & kCFRunLoopBeforeWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeWaiting);
        // 设置runloop为休眠状态
        __CFRunLoopSetSleeping(rl);
        // do not do any user callouts after this point (after notifying of sleeping)
        
        // Must push the local-to-this-activation ports in on every loop
        // iteration, as this mode could be run re-entrantly and we don't
        // want these ports to get serviced.
        /// 设置端口监听方便唤醒
        __CFPortSetInsert(dispatchPort, waitSet);
        
        __CFRunLoopModeUnlock(rlm);
        __CFRunLoopUnlock(rl);
        
        /// 开始休眠的时间？当这个runloop有处理任务时从新开始计时
        CFAbsoluteTime sleepStart = poll ? 0.0 : CFAbsoluteTimeGetCurrent();
        
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
#if USE_DISPATCH_SOURCE_FOR_TIMERS
        // 内循环，用于接受等待端口的消息。线程进入休眠，收到新消息，跳出该循环，继续执行runloop
        do {
            if (kCFUseCollectableAllocator) {
                // objc_clear_stack(0);
                // <rdar://problem/16393959>
                memset(msg_buffer, 0, sizeof(msg_buffer));
            }
            msg = (mach_msg_header_t *)msg_buffer;
            /// 7.接受waitset端口的消息，休眠
            __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);
            /// 收到消息后，livePort的值为msg->msgh_local_port
            if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
                // Drain the internal queue. If one of the callout blocks sets the timerFired flag, break out and service the timer.
                //排空内部队列。 如果其中一个标注块设置了timerFired标志，则中断并为定时器提供服务。
                while (_dispatch_runloop_root_queue_perform_4CF(rlm->_queue));
                if (rlm->_timerFired) {
                    // Leave livePort as the queue port, and service timers below
                    //将livePort保留为队列端口，并将服务计时器保留在下面
                    rlm->_timerFired = false;
                    break;
                } else {
                    if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
                }
            } else {
                // Go ahead and leave the inner loop.
                break;
            }
        } while (1);
#else
        if (kCFUseCollectableAllocator) {
            // objc_clear_stack(0);
            // <rdar://problem/16393959>
            memset(msg_buffer, 0, sizeof(msg_buffer));
        }
        msg = (mach_msg_header_t *)msg_buffer;
        __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);
#endif
        
#endif
        
        __CFRunLoopLock(rl);
        __CFRunLoopModeLock(rlm);
        
        /// 休眠时间
        rl->_sleepTime += (poll ? 0.0 : (CFAbsoluteTimeGetCurrent() - sleepStart));
        
        // Must remove the local-to-this-activation ports in on every loop
        // iteration, as this mode could be run re-entrantly and we don't
        // want these ports to get serviced. Also, we don't want them left
        // in there if this function returns.
        /**
         必须在每个循环中删除本地到此激活端口
                   迭代，因为这种模式可以重新运行而我们不会
                   希望这些端口得到服务。 此外，我们不希望他们离开
                 在那里，如果此函数返回。
         */
        
        __CFPortSetRemove(dispatchPort, waitSet);
        
        
        __CFRunLoopSetIgnoreWakeUps(rl);
        
        // user callouts now OK again
        //取消runloop的休眠状态
        __CFRunLoopUnsetSleeping(rl);
        // 8.通知观察者runloop被唤醒
        if (!poll && (rlm->_observerMask & kCFRunLoopAfterWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopAfterWaiting);
        
        // 9.处理接收到的消息
    handle_msg:;
        __CFRunLoopSetIgnoreWakeUps(rl);
        

        if (MACH_PORT_NULL == livePort) {
            CFRUNLOOP_WAKEUP_FOR_NOTHING();
            // handle nothing
        } else if (livePort == rl->_wakeUpPort) {
            CFRUNLOOP_WAKEUP_FOR_WAKEUP();
            // 什么都不干，跳回2重新循环
        }
#if USE_DISPATCH_SOURCE_FOR_TIMERS
        else if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
            CFRUNLOOP_WAKEUP_FOR_TIMER();
            if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                // Re-arm the next timer, because we apparently fired early
                __CFArmNextTimerInMode(rlm, rl);
            }
        }
#endif
#if USE_MK_TIMER_TOO
        //如果是定时器事件
        else if (rlm->_timerPort != MACH_PORT_NULL && livePort == rlm->_timerPort) {
            CFRUNLOOP_WAKEUP_FOR_TIMER();
            // On Windows, we have observed an issue where the timer port is set before the time which we requested it to be set. For example, we set the fire time to be TSR 167646765860, but it is actually observed firing at TSR 167646764145, which is 1715 ticks early. The result is that, when __CFRunLoopDoTimers checks to see if any of the run loop timers should be firing, it appears to be 'too early' for the next timer, and no timers are handled.
            // In this case, the timer port has been automatically reset (since it was returned from MsgWaitForMultipleObjectsEx), and if we do not re-arm it, then no timers will ever be serviced again unless something adjusts the timer list (e.g. adding or removing timers). The fix for the issue is to reset the timer here if CFRunLoopDoTimers did not handle a timer itself. 9308754
            
            // 9.1处理定时器事件
            if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                // Re-arm the next timer
                __CFArmNextTimerInMode(rlm, rl);
            }
        }
#endif
        //如果是dispatch到main queue的block
        else if (livePort == dispatchPort) {
            CFRUNLOOP_WAKEUP_FOR_DISPATCH();
            __CFRunLoopModeUnlock(rlm);
            __CFRunLoopUnlock(rl);
            _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)6, NULL);
            // 9.2 执行block
            __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__(msg);
            _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)0, NULL);
            __CFRunLoopLock(rl);
            __CFRunLoopModeLock(rlm);
            sourceHandledThisLoop = true;
            didDispatchPortLastTime = true;
        } else {
            CFRUNLOOP_WAKEUP_FOR_SOURCE();
            
            // If we received a voucher from this mach_msg, then put a copy of the new voucher into TSD. CFMachPortBoost will look in the TSD for the voucher. By using the value in the TSD we tie the CFMachPortBoost to this received mach_msg explicitly without a chance for anything in between the two pieces of code to set the voucher again.
            voucher_t previousVoucher = _CFSetTSD(__CFTSDKeyMachMessageHasVoucher, (void *)voucherCopy, os_release);
            
            // Despite the name, this works for windows handles as well
            CFRunLoopSourceRef rls = __CFRunLoopModeFindSourceForMachPort(rl, rlm, livePort);
            /// 有source1事件待处理
            if (rls) {
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
                mach_msg_header_t *reply = NULL;
                sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls, msg, msg->msgh_size, &reply) || sourceHandledThisLoop;
                if (NULL != reply) {
                    (void)mach_msg(reply, MACH_SEND_MSG, reply->msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
                    CFAllocatorDeallocate(kCFAllocatorSystemDefault, reply);
                }
#endif
            }
            
            // Restore the previous voucher
            _CFSetTSD(__CFTSDKeyMachMessageHasVoucher, previousVoucher, os_release);
            
        }
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
#endif
        /// 处理block
        __CFRunLoopDoBlocks(rl, rlm);
        
        
        if (sourceHandledThisLoop && stopAfterHandle) {
            retVal = kCFRunLoopRunHandledSource;
        } else if (timeout_context->termTSR < mach_absolute_time()) {
            retVal = kCFRunLoopRunTimedOut;
        } else if (__CFRunLoopIsStopped(rl)) {
            __CFRunLoopUnsetStopped(rl);
            retVal = kCFRunLoopRunStopped;
        } else if (rlm->_stopped) {
            rlm->_stopped = false;
            retVal = kCFRunLoopRunStopped;
        } else if (__CFRunLoopModeIsEmpty(rl, rlm, previousMode)) {
            retVal = kCFRunLoopRunFinished;
        }
        
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        voucher_mach_msg_revert(voucherState);
        os_release(voucherCopy);
#endif
        
    } while (0 == retVal);
    
    if (timeout_timer) {
        dispatch_source_cancel(timeout_timer);
        dispatch_release(timeout_timer);
    } else {
        free(timeout_context);
    }
    
    return retVal;
}
```

实际上RunLoop内部就是一个do-while循环。RunLoop在run的时候必须指定其中一个mode。

#### RunLoop相关操作

iOS中不能直接创建Runloop，只能从系统中获取CFRunLoopGetMain() 和 CFRunLoopGetCurrent()。

```
CFRunLoopRef CFRunLoopGetCurrent(void);//获取当前线程的RunLoop对象
CFRunLoopRef CFRunLoopGetMain(void);//获取主线程的RunLoop对象
+(NSRunLoop *)currentRunLoop
+(NSRunLoop *)mainRunLoop
```



```
CFRunLoopRef CFRunLoopGetMain(void) {
    CHECK_FOR_FORK();
    static CFRunLoopRef __main = NULL; // no retain needed
    if (!__main) __main = _CFRunLoopGet0(pthread_main_thread_np()); // no CAS needed
    return __main;
}

CFRunLoopRef CFRunLoopGetCurrent(void) {
    CHECK_FOR_FORK();
    CFRunLoopRef rl = (CFRunLoopRef)_CFGetTSD(__CFTSDKeyRunLoop);
    if (rl) return rl;
    return _CFRunLoopGet0(pthread_self());
}

//全局的Dictionary，key 是 pthread_t， value 是 CFRunLoopRef
static CFMutableDictionaryRef __CFRunLoops = NULL;
// 访问 loopDic 时的锁，可以知道 __CFRunLoops 是线程不安全
static CFLock_t loopsLock = CFLockInit;

// should only be called by Foundation
// t==0 is a synonym for "main thread" that always works
CF_EXPORT CFRunLoopRef _CFRunLoopGet0(pthread_t t) {
    //如果传入线程为空，默认则为主线程
    if (pthread_equal(t, kNilPthreadT)) {
        t = pthread_main_thread_np();
    }
    // 加锁
    __CFLock(&loopsLock);
    if (!__CFRunLoops) {
        __CFUnlock(&loopsLock);
        // 初始化字典
        CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
        // 创建主线程的runloop
        CFRunLoopRef mainLoop = __CFRunLoopCreate(pthread_main_thread_np());
        CFDictionarySetValue(dict, pthreadPointer(pthread_main_thread_np()), mainLoop);
        if (!OSAtomicCompareAndSwapPtrBarrier(NULL, dict, (void * volatile *)&__CFRunLoops)) {
            CFRelease(dict);
        }
        CFRelease(mainLoop);
        __CFLock(&loopsLock);
    }
    // 从字典里取 线程指针为key
    CFRunLoopRef loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
    __CFUnlock(&loopsLock);
    // 没有则创建
    if (!loop) {
        CFRunLoopRef newLoop = __CFRunLoopCreate(t);
        __CFLock(&loopsLock);
        loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
        if (!loop) {
            CFDictionarySetValue(__CFRunLoops, pthreadPointer(t), newLoop);
            loop = newLoop;
        }
        // don't release run loops inside the loopsLock, because CFRunLoopDeallocate may end up taking it
        __CFUnlock(&loopsLock);
        CFRelease(newLoop);
    }
    // 如果传入的线程是当前线程
    if (pthread_equal(t, pthread_self())) {
        _CFSetTSD(__CFTSDKeyRunLoop, (void *)loop, NULL);
        if (0 == _CFGetTSD(__CFTSDKeyRunLoopCntr)) {
            // 注册一个回调，当线程销毁时，也销毁对应的 RunLoop
            _CFSetTSD(__CFTSDKeyRunLoopCntr, (void *)(PTHREAD_DESTRUCTOR_ITERATIONS-1), (void (*)(void *))__CFFinalizeRunLoop);
        }
    }
    return loop;
}

```

总结如下：

* 线程和RunLoop之间是一一对应的，其关系是保存在一个全局的 Dictionary 里。
* 线程刚创建时并没有RunLoop，不主动获取，一直都不会有。
* RunLoop的创建是发生在第一次获取，RunLoop的销毁是发生在线程结束时。
* 只能在一个线程的内部获取其RunLoop，主线程除外。

#### 总结

从上面的源码中可以看出，

* 虽然事先调用了“kCFRunLoopBeforeTimers”、“kCFRunLoopBeforeSources”，但真正处理的是source0事件，然后处理的是block。
* 有source0事件会再次处理block，有没有source0事件影响这次runloop进入休眠是否通知
* 如果source1则会跳转处理，timer的处理也在这里。处理的优先级依次是 timer、gcd、source1，三者一次只能处理其一，当下次进入这里时再处理其它的。处理过block后从头开始循环。
* 如果没有source1，则进入休眠。如果之前处理过source0或者超时了，不会通知进入休眠。
* 如果是初进入runloop的这个model，不会判断source1

简化版如下

```
Int32 CFRunLoopRunSpecific(CFRunLoopRef rl, CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {      CALLOUT
    //1. 通知observer 即将进入runloop
    if (currentMode->_observerMask & kCFRunLoopEntry ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
    // runloop 运行循环
    do {
        /// 2.通知observer，即将触发timer回调，处理timer事件
        if (rlm->_observerMask & kCFRunLoopBeforeTimers) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeTimers);
        //// 3.通知observer，即将触发source回调
        if (rlm->_observerMask & kCFRunLoopBeforeSources) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeSources);
        /// .处理加入当前runloop的block
        __CFRunLoopDoBlocks(rl, rlm);
        
        /// 4.处理source0事件，有没有事件要处理
        Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
        if (sourceHandledThisLoop) {
            ///处理加入当前runloop的block
            __CFRunLoopDoBlocks(rl, rlm);
        }
        
        /// 如果有source0事件处理或者超时，为true
        Boolean poll = sourceHandledThisLoop || (0ULL == timeout_context->termTSR);
        
        /// 第一次do.. while循环不会走该分支，因为didDispatchPortLastTime为true
        if (MACH_PORT_NULL != dispatchPort && !didDispatchPortLastTime) {
            /// 5.接受到dispatchPort 端口的信息 source1事件
            if (__CFRunLoopServiceMachPort(dispatchPort, &msg, sizeof(msg_buffer), &livePort, 0, &voucherState, NULL)) {
                /// 如果接受到了消息的话，前往第9步开始处理
                goto handle_msg;
            }
        }
        //表明不是第一次走了，下次要先看有没有source1事件
        didDispatchPortLastTime = false;
        
        //// 如果没有source0事件或者没有超时
        //// 6.即将进入休眠
        if (!poll && (rlm->_observerMask & kCFRunLoopBeforeWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeWaiting);
        // 设置runloop为休眠状态
        __CFRunLoopSetSleeping(rl);

        
        __CFRunLoopSetIgnoreWakeUps(rl);
        
        // user callouts now OK again
        //取消runloop的休眠状态
        __CFRunLoopUnsetSleeping(rl);
        // 8.通知观察者runloop被唤醒
        if (!poll && (rlm->_observerMask & kCFRunLoopAfterWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopAfterWaiting);
        
        // 9.处理接收到的消息
    handle_msg:;
        __CFRunLoopSetIgnoreWakeUps(rl);
        
        
        if (MACH_PORT_NULL == livePort) {
            CFRUNLOOP_WAKEUP_FOR_NOTHING();
            // handle nothing
        } else if (livePort == rl->_wakeUpPort) {
            CFRUNLOOP_WAKEUP_FOR_WAKEUP();
            // 什么都不干，跳回2重新循环
        }
        //如果是定时器事件
        else if (rlm->_timerPort != MACH_PORT_NULL && livePort == rlm->_timerPort) {
            // 9.1处理定时器事件
            if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                // Re-arm the next timer
                __CFArmNextTimerInMode(rlm, rl);
            }
        }
        //如果是dispatch到main queue的block
        else if (livePort == dispatchPort) {
        
        } else {
        // Despite the name, this works for windows handles as well
            CFRunLoopSourceRef rls = __CFRunLoopModeFindSourceForMachPort(rl, rlm, livePort);
            /// 有source1事件待处理
            if (rls) {
                sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls, msg, msg->msgh_size, &reply) || sourceHandledThisLoop;
            }
        }

        /// 处理block
        __CFRunLoopDoBlocks(rl, rlm);
        
        //是否退出
        if (sourceHandledThisLoop && stopAfterHandle) {
            retVal = kCFRunLoopRunHandledSource;
        } else if (timeout_context->termTSR < mach_absolute_time()) {
            retVal = kCFRunLoopRunTimedOut;
        } else if (__CFRunLoopIsStopped(rl)) {
            __CFRunLoopUnsetStopped(rl);
            retVal = kCFRunLoopRunStopped;
        } else if (rlm->_stopped) {
            rlm->_stopped = false;
            retVal = kCFRunLoopRunStopped;
        } else if (__CFRunLoopModeIsEmpty(rl, rlm, previousMode)) {
            retVal = kCFRunLoopRunFinished;
        }
        
    } while (0 == retVal);
    // 10.通知observer即将推出runloop
    if (currentMode->_observerMask & kCFRunLoopExit ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);
    
}

```

**因为有些情况时，runloop进入休眠与唤醒并不会通知观察者，而开头的打印结果中在viewwillappear和dispatch_async之间没有发现重新通知timer要处理，所以可以严格意义上的讲，它们是在一个RunLoop之间的**。但是虽然进入了超时时间，但是在用户态的Mach消息的mach_msg的函数的`mach_msg_timeout_t`参数为0，即放弃前等待的时间为0。虽然进入了休眠，但是立马被唤醒了，所以没必要通知了



**分析:** 我们知道viewDidLoad、viewWillAppear在一个runloop中执行，当我们在viewDidLoad中添加一个异步的block时，这个block被添加到主线程的串行队列中，libDispatch向主线程的RunLoop发送消息，而此时viewDidLoad方法还未执行完（source0，点击事件触发的），等到判断是否source1事件时，是有的，直接跳转处理。

```
static Boolean __CFRunLoopServiceMachPort(mach_port_name_t port, mach_msg_header_t **buffer, size_t buffer_size, mach_port_t *livePort, mach_msg_timeout_t timeout, voucher_mach_msg_state_t *voucherState, voucher_t *voucherCopy) {
    Boolean originalBuffer = true;
    kern_return_t ret = KERN_SUCCESS;
    for (;;) {        /* In that sleep of death what nightmares may come ... */
        mach_msg_header_t *msg = (mach_msg_header_t *)*buffer;
        msg->msgh_bits = 0;
        msg->msgh_local_port = port;
        msg->msgh_remote_port = MACH_PORT_NULL;
        msg->msgh_size = buffer_size;
        msg->msgh_id = 0;
        if (TIMEOUT_INFINITY == timeout) { CFRUNLOOP_SLEEP(); } else { CFRUNLOOP_POLL(); }
        ret = mach_msg(msg, MACH_RCV_MSG|(voucherState ? MACH_RCV_VOUCHER : 0)|MACH_RCV_LARGE|((TIMEOUT_INFINITY != timeout) ? MACH_RCV_TIMEOUT : 0)|MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0)|MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AV), 0, msg->msgh_size, port, timeout, MACH_PORT_NULL);
        
        // Take care of all voucher-related work right after mach_msg.
        // If we don't release the previous voucher we're going to leak it.
        voucher_mach_msg_revert(*voucherState);
        
        // Someone will be responsible for calling voucher_mach_msg_revert. This call makes the received voucher the current one.
        *voucherState = voucher_mach_msg_adopt(msg);
        
        if (voucherCopy) {
            if (*voucherState != VOUCHER_MACH_MSG_STATE_UNCHANGED) {
                // Caller requested a copy of the voucher at this point. By doing this right next to mach_msg we make sure that no voucher has been set in between the return of mach_msg and the use of the voucher copy.
                // CFMachPortBoost uses the voucher to drop importance explicitly. However, we want to make sure we only drop importance for a new voucher (not unchanged), so we only set the TSD when the voucher is not state_unchanged.
                *voucherCopy = voucher_copy();
            } else {
                *voucherCopy = NULL;
            }
        }
        
        CFRUNLOOP_WAKEUP(ret);
        if (MACH_MSG_SUCCESS == ret) {
            *livePort = msg ? msg->msgh_local_port : MACH_PORT_NULL;
            return true;
        }
        if (MACH_RCV_TIMED_OUT == ret) {
            if (!originalBuffer) free(msg);
            *buffer = NULL;
            *livePort = MACH_PORT_NULL;
            return false;
        }
        if (MACH_RCV_TOO_LARGE != ret) break;
        buffer_size = round_msg(msg->msgh_size + MAX_TRAILER_SIZE);
        if (originalBuffer) *buffer = NULL;
        originalBuffer = false;
        *buffer = realloc(*buffer, buffer_size);
    }
    HALT;
    return false;
}
///这个函数通过内核的Mach陷阱把自己从用户态陷入内核态
mach_msg_return_t   mach_msg(
                    mach_msg_header_t *msg,
                    mach_msg_option_t option,
                    mach_msg_size_t send_size,
                    mach_msg_size_t rcv_size,
                    mach_port_name_t rcv_name,
                    mach_msg_timeout_t timeout,
                    mach_port_name_t notify);
```

## 五、RunLoop在系统中的引用

### 1.Block

```
typedef struct 
{
  mach_msg_bits_t   msgh_bits;//标志位
  mach_msg_size_t   msgh_size;//大小
  mach_port_t       msgh_remote_port;//目标端口（发送：接受方，接收：发送方）
  mach_port_t       msgh_local_port; //源端口（发送：发送方，接收：接收方）
  mach_port_name_t  msgh_voucher_port;
  mach_msg_id_t     msgh_id;
} mach_msg_header_t; //消息头

struct _block_item {
    struct _block_item *_next;
    CFTypeRef _mode;    // CFString or CFSet
    void (^_block)(void);
};
/**
 执行block
 @param rl runloop
 @param rlm 当前的model
 @return 是否执行
 */
static Boolean __CFRunLoopDoBlocks(CFRunLoopRef rl, CFRunLoopModeRef rlm) { // Call with rl and rlm locked
    //如果头结点没有、或者model不存在则强制返回，什么也不做
    if (!rl->_blocks_head) return false;
    if (!rlm || !rlm->_name) return false;
    Boolean did = false;//记录其中一个block结点是否被执行过
    //取出头尾结点，并且将当前runloop保存的头尾节点置位NULL
    struct _block_item *head = rl->_blocks_head;
    struct _block_item *tail = rl->_blocks_tail;
    rl->_blocks_head = NULL;
    rl->_blocks_tail = NULL;
    //取出被标记为common的所有mode、及当前model的name
    CFSetRef commonModes = rl->_commonModes;
    CFStringRef curMode = rlm->_name;
    __CFRunLoopModeUnlock(rlm);
    __CFRunLoopUnlock(rl);
    
    //定义两个临时变量，用于对保存block链表的遍历
    struct _block_item *prev = NULL;
    struct _block_item *item = head;//记录头指针，从头部开始遍历
    //开始遍历block链表
    while (item) {
        struct _block_item *curr = item;
        item = item->_next;
        Boolean doit = false；//表示是否应该执行这个block,注意和前面的did区分开
        
        //从blockitem结构体就知道,其中的_mode只能是CFString 或者CFSet
        //如果block结点保存的model是CFString类型
        if (CFStringGetTypeID() == CFGetTypeID(curr->_mode)) {
            //是否执行block只需要满足下面三个条件中的一个
            //1. blockitem 中保存的model是当前的model
            //2. blockitem 中保存的model是标记为kCFRunLoopCommonModes的model
            //3. 当前model保存在commonModes数组
            doit = CFEqual(curr->_mode, curMode) || (CFEqual(curr->_mode, kCFRunLoopCommonModes) && CFSetContainsValue(commonModes, curMode));
        } else {
            //如果block结点保存的model是CFSet类型，步骤和上面一样，等于换成了包含。
            doit = CFSetContainsValue((CFSetRef)curr->_mode, curMode) || (CFSetContainsValue((CFSetRef)curr->_mode, kCFRunLoopCommonModes) && CFSetContainsValue(commonModes, curMode));
        }
        
        //如果不执行block,则直接移动当前结点，进行下一个blockitem的判断
        if (!doit) prev = curr;
        if (doit) {
            //如果执行block,则先移动结点。
            if (prev) prev->_next = item;
            if (curr == head) head = item;
            if (curr == tail) tail = prev;
            
            void (^block)(void) = curr->_block;
            CFRelease(curr->_mode);
            free(curr);
            if (doit) {
                //最终在这里执行block，__CFRUNLOOP_IS_CALLING_OUT_TO_A_BLOCK__的函数原型就是调用block
                __CFRUNLOOP_IS_CALLING_OUT_TO_A_BLOCK__(block);
                did = true;
            }
            Block_release(block); // do this before relocking to prevent deadlocks where some yahoo wants to run the run loop reentrantly from their dealloc
        }
    }
    __CFRunLoopLock(rl);
    __CFRunLoopModeLock(rlm);
    //重建循环链表
    if (head) {
        tail->_next = rl->_blocks_head;
        rl->_blocks_head = head;
        if (!rl->_blocks_tail) rl->_blocks_tail = tail;
    }
    return did;
}

```

block在runloop中通过循环链表保存的。如果block只能在加入的mode下执行。每次调用__CFRunLoopDoBlocks，会把加入的block遍历执行，然后重置循环链表



这些block是由CFRunLoopPerformBlock(CFRunLoopRef rl, CFTypeRef mode, void (^block)(void))添加的 Blocks。

### 2.AutoreleasePool

App启动后，苹果在主线程RunLoop里注册了两个Observer，其回调都是_wrapRunLoopWithAutoreleasePoolHandler()。

第一Observer监视的是事件时Entry（即将进入Loop），其回调内会调用_objc_autoreleasePoolPush()创建自动释放池。其 order 是-2147483647，优先级最高，保证创建释放池发生在其他所有回调之前。

第二个Observer监视了两个事件：BeforeWaiting（准备进入休眠）时调用_objc_autoreleasePoolPop()和_objc_autoreleasePoolPush() 释放旧的池并创建新池；xit(即将退出Loop) 时调用 _objc_autoreleasePoolPop() 来释放自动释放池。这个 Observer 的 order 是 2147483647，优先级最低，保证其释放池子发生在其他所有回调之后。

### 3.手势识别

当_UIApplicationHandleEventQueue() 识别了一个手势时，其首先会调用cancel将当前的touchesBegin/Move/End系列回调打断。随后系统将对应UIGestureRecognizer标记Wie待处理。

苹果注册了一个Observer 检测 BeforeWaiting事件，这个Observer的回调函数是_UIGestureRecognizerUpdateObserver()，其内部会获取所有被标记为待处理的GestureRecognizer，并执行GestureRecognizer的回调。

当有GestureRecognizer的变化（创建/销毁/状态改变）时，这个回调都会进行相应处理。

### 4.界面更新

_beforeCACommitHandler与_ZN2CA11Transaction17observer_callbackEP19__CFRunLoopObservermPv，是关于动画及界面更新的。

当在操作UI时，比如改变了frame，更新了UIView/CALayer的层次时，或者手动调用了 UIView/CALaye的setNeedsLayout/setNeedsDisplay方法后，这个UIView/CALaye 就被标记为待处理，并被提交到一个全局的容器去。

果注册了一个 Observer 监听 BeforeWaiting(即将进入休眠) 和 Exit (即将退出Loop) 事件，回调去执行一个很长的函数：
_ZN2CA11Transaction17observer_callbackEP19__CFRunLoopObservermPv()。这个函数里会遍历所有待处理的 UIView/CAlayer 以执行实际的绘制和调整，并更新 UI 界面。

### 5.定时器

RunLoop为了节省资源，并不会在非常准确的时间点回调这个Timer。Timer 有个属性叫做 Tolerance (宽容度)，标示了当时间点到后，容许有多少最大误差。

如果某个时间点被错过了，例如执行了一个很长的任务，则那个时间点的回调也会跳过去，不会延后执行。就比如等公交，如果 10:10 时我忙着玩手机错过了那个点的公交，那我只能等 10:20 这一趟了。

### 6.PerformSelecter

当调用 NSObject 的 performSelecter:afterDelay: 来实现延迟执行，实际上其内部会创建一个 Timer 并添加到当前线程的 RunLoop 中。**所以如果当前线程没有 RunLoop，则这个方法会失效。**

当调用 performSelector:onThread: 时，实际上其会创建一个 Timer 加到对应的线程去，**同样的，如果对应线程没有 RunLoop 该方法也会失效。**

### 7.GCD

当调用 dispatch_async(dispatch_get_main_queue(), block) 时，libDispatch 会向主线程的 RunLoop 发送消息，RunLoop会被唤醒，并从消息中取得这个 block，并在回调 **CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE**() 里执行这个 block。但这个逻辑仅限于 dispatch 到主线程，dispatch 到其他线程仍然是由 libDispatch 处理的。

### 8.网络请求

iOS中，关于网络请求的接口自下至上有如下几层

```
CFSocket
CFNetwork       ->ASIHttpRequest
NSURLConnection ->AFNetworking
NSURLSession    ->AFNetworking2, Alamofire
```

CFSocket是最底层的接口，只负责socket通信，CFNetwork是基于CFSocket等接口的上层封装。NSURLConnection 是基于 CFNetwork 的更高层的封装，提供面向对象的接口。NSURLSession 是 iOS7 中新增的接口，表面上是和 NSURLConnection 并列的，但底层仍然用到了 NSURLConnection 的部分功能 (比如 com.apple.NSURLConnectionLoader 线程)，AFNetworking2 和 Alamofire 工作于这一层。



通常使用NSURLConnection时，你会传入一个delegate，当调用了[connection start]后，这个delegate就会不停收到事件回调。实际上，start这个函数的内部会获取currentRunLoop，然后在其中的 DefaultMode 添加了4个 Source0 (即需要手动触发的Source)。CFMultiplexerSource 是负责各种 Delegate 回调的，CFHTTPCookieStorage 是处理各种 Cookie 的。

当开始网络传输时，我们可以看到 NSURLConnection 创建了两个新线程：com.apple.NSURLConnectionLoader 和 com.apple.CFSocket.private。其中 CFSocket 线程是处理底层 socket 连接的。NSURLConnectionLoader 这个线程内部会使用 RunLoop 来接收底层 socket 的事件，并通过之前添加的 Source0 通知到上层的 Delegate。
[图片](https://blog.ibireme.com/wp-content/uploads/2015/05/RunLoop_network.png)

NSURLConnectionLoader 中的 RunLoop 通过一些基于 mach port 的 Source 接收来自底层 CFSocket 的通知。当收到通知后，其会在合适的时机向 CFMultiplexerSource 等 Source0 发送通知，同时唤醒 Delegate 线程的 RunLoop 来让其处理这些通知。CFMultiplexerSource 会在 Delegate 线程的 RunLoop 对 Delegate 执行实际的回调。



## 六、学习资料

[RunLoop从源码到应用全面解析]([http://weslyxl.coding.me/2018/03/18/2018/3/RunLoop%E4%BB%8E%E6%BA%90%E7%A0%81%E5%88%B0%E5%BA%94%E7%94%A8%E5%85%A8%E9%9D%A2%E8%A7%A3%E6%9E%90/](http://weslyxl.coding.me/2018/03/18/2018/3/RunLoop从源码到应用全面解析/))

[**深入浅出 GCD 之 dispatch_queue**](https://xiaozhuanlan.com/topic/7193856240)