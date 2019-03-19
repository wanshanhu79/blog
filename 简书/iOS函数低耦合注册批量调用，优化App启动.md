### 来源

这是在看了美团的[美团外卖iOS App冷启动治理](https://tech.meituan.com/2018/12/06/waimai-ios-optimizing-startup.html)这篇技术文章时，自己做的笔记。还有一些笔记可以分享，不过都是一些总结，后面会慢慢发出来。

### 理论
我们注册APP启动项的时候，如果有多个函数需要在APP启动时调用，难道都在AppDelegate中导入头文件后再调用，这样耦合性高，复用也差。有些业务之间的事件依赖关系，如果直接在代码中调用，不仅耦合严重，还不方便平台化。

**借助编译器函数和事件注册的基础组件**，可以降低这种情况。借助编译器函数在编译时把数据（如函数指针）写入可执行文件的__DATA段中，运行时再从__DATA段中取出数据进行相应的操作（调用函数）。借用__DATA段，能够覆盖所有的启动阶段，例如main()之前的阶段。

Clang提供了很多的编译器函数，它们可以完成不同的功能。其中一种是section()函数，section()函数提供了二进制段的读写能力，它可以将一些编译期就可以确定的常量写入数据段。在具体的实现中，主要分为编译期和运行时两个部分。在编译期，编译器会将标记了attribute((section()))的数据写到指定的数据段，例如写一个{key(key代表不同的启动阶段), *pointer}对到数据段。到运行时，在合适的时间节点，再根据key读取出函数指针，完成函数的调用。

### 代码
参考美团的与github上搜到的，表示感谢，感谢分享！
```
#import <mach-o/getsect.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <mach-o/ldsyms.h>

#ifndef __LP64__
typedef uint32_t MemoryType;
#else
typedef uint64_t MemoryType;
#endif

typedef void ZLLFunction(void);
#pragma mark - 编译时 写入 
void ZLLTest(void) {
    printf("调用了我\n");
}
void * ZLLLoaddd __attribute__((used, section("__DATA, ZLLDATA"))) = ZLLTest;

#pragma mark - 运行时 调用
void reaadFunc(char *sectionName, const struct mach_header *mhp);
static void dyld_callback(const struct mach_header *mhp, integer_t vmaddr_slide) {
    printf("callback\n");//会执行很多次，每个镜像都会调用
    reaadFunc("ZLLDATA", mhp);
}

//该函数会在main（）函数执行之前被自动的执行。
__attribute__((constructor))
void initProhet () {
    // 在 dyld 加载镜像时，会执行注册过的回调函数，调用这个方法注册定义的回调
    _dyld_register_func_for_add_image(dyld_callback);
    //对于每一个已经存在的镜像，当它被动态链接时，都会执行回调 void (*func)(const struct mach_header* mh, intptr_t vmaddr_slide)，传入文件的 mach_header 以及一个虚拟内存地址 intptr_t。
}
void reaadFunc(char *sectionName, const struct mach_header *mhp) {
    unsigned long size = 0;
#ifndef __LP64__
    MemoryType *memory = getsectiondata(mhp, SEG_DATA, sectionName, &size);
#else
    const struct mach_header_64 *mhp64 = (const struct mach_header_64 *)mhp;
    MemoryType *memory = (MemoryType*)getsectiondata(mhp64, SEG_DATA, sectionName, &size);
#endif
    long counter = size/ sizeof(void *);
    for (int idx = 0; idx < counter; ++idx) {
        ZLLFunction *my = (ZLLFunction *)memory[idx];
        my();
    }
}
```
另一种取值方式
```
#ifdef __LP64__
typedef uint64_t MustOverrideValue;
typedef struct section_64 MustOverrideSection;
#define GetSectByNameFromHeader getsectbynamefromheader_64
#else
typedef uint32_t MustOverrideValue;
typedef struct section MustOverrideSection;
#define GetSectByNameFromHeader getsectbynamefromheader
#endif
static void CheckOverrides(void) {
    Dl_info info;
    dladdr((const void *)&CheckOverrides, &info);
    printf("1\n");
    const MustOverrideValue mach_header = (MustOverrideValue)info.dli_fbase;
    const MustOverrideSection *section = GetSectByNameFromHeader((void *)mach_header, "__DATA", "ZLLDATA");
    if (section == NULL) return;
      printf("2\n");
    
        long counter = section->size/ sizeof(void *);
    for (MustOverrideValue addr = section->offset; addr < section->offset + section->size; addr+=sizeof(void *)) {
    //这儿是传进去的值得指针
        ZLLFunction **my = (ZLLFunction **)(mach_header +addr);
        (*my)();
    }
}
```
