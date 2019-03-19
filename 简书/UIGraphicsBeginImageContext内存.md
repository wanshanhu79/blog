## 一、寄宿图Bitmap
之前看过[内存恶鬼drawRect](http://bihongbo.com/2016/01/03/memoryGhostdrawRect/)，也验证过，确实如此，但理解花了好长时间。  

> 在每一个UIView实例当中，都有一个默认的支持图层，UIView负责创建并且管理这个图层。实际上这个CALayer图层才是真正用来在屏幕上显示的，UIView仅仅是对它的一层封装，实现了CALayer的delegate，提供了处理事件交互的具体功能。
> CALayer只是一个普通的类，它也不能直接渲染到屏幕上，因为屏幕上你所看到的东西，其实都是一张张图片。而为什么我们能看到CALayer的内容呢，是因为CALayer内部有一个contents属性。contents默认可以传一个id类型的对象，但是只有你传CGImage的时候，它才能够正常显示在屏幕上。contents也被称为寄宿图，除了给它赋值CGImage之外，我们也可以直接对它进行绘制，。如果UIView检测到-drawRect：方法被调用了，它就会为视图分配一个寄宿图。这个寄宿图的像素尺寸等于视图大小乘以contentsScale。

为什么要做这样的设定呢？  
猜测是为了方便显示，[iOS保持界面流畅的技巧](https://blog.ibireme.com/2015/11/12/smooth_user_interfaces_for_ios/#more-41893) 中指出图片的解码比较消耗CPU性能，为保持界面流畅，图片需要提前解码，即从寄宿图直接创建图片。

> 当你用UIImage后CGImageSource的那几个方法创建图片时，图片数据并不会立刻解码。图片设置到UIImageView或者CALayer.contents中去，并且CALayer被提交到GPU 前，CGImage 中的数据才会得到解码。这一步是发生在主线程的，并且不可避免。如果想要绕开这个机制，常见的做法是在后台线程先把图片绘制到 CGBitmapContext 中，然后从 Bitmap 直接创建图片。目前常见的网络图片库都自带这个功能。

## 二、UIGraphicsBeginImageContext
之前看过一篇文章[iOS微信内存监控](https://mp.weixin.qq.com/s/r0Q7um7P1p2gIb0aHldyNw?scene=25#wechat_redirect)中提到大图片处理时采用这种方法
```
 - (UIImage *)scaleImage:(UIImage *)image newSize:(CGSize)newSize {
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}
```
> 但处理大分辨率图片时，往往容易出现OOM，原因是-[UIImage drawInRect:]在绘制时，先解码图片，再生成原始分辨率大小的bitmap，这是很耗内存的。解决方法是使用更低层的ImageIO接口，避免中间bitmap产生：
```
+ (UIImage *)scaleImageWithData:(NSData *)data withSize:(CGSize)size
                          scale:(CGFloat)scale
                    orientation:(UIImageOrientation)orientation {
    CGFloat maxPixelSize = MAX(size.width, size.height);
    CGImageSourceRef sourceRef = CGImageSourceCreateWithData((__bridge CFDataRef)data, nil);
    NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:(__bridge id)kCFBooleanTrue,
                              (__bridge id)kCGImageSourceThumbnailMaxPixelSize:[NSNumber numberWithFloat:maxPixelSize]
                              };
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(sourceRef, 0, (__bridge CFDictionaryRef)options);
    UIImage *resultImage = [UIImage imageWithCGImage:imageRef scale:scale orientation:orientation];
    CGImageRelease(imageRef);
    CFRelease(sourceRef);
    
    return resultImage;
}
//或者如下方法
- (UIImage *)imageByCropToRect:(CGRect)rect {
    rect.origin.x *= self.scale;
    rect.origin.y *= self.scale;
    rect.size.width *= self.scale;
    rect.size.height *= self.scale;
    if (rect.size.width <= 0 || rect.size.height <= 0) return nil;
    CGImageRef imageRef = CGImageCreateWithImageInRect(self.CGImage, rect);
    UIImage *image = [UIImage imageWithCGImage:imageRef scale:self.scale orientation:self.imageOrientation];
    CGImageRelease(imageRef);
    return image;
}
```
不过以上两个方法不好处就是提交图片后在真正显示的时候才会解码，会影响CPU性能。

以下摘自源码
 ```
// UIImage context

// The following methods will only return a 8-bit per channel context in the DeviceRGB color space.
// Any new bitmap drawing code is encouraged to use UIGraphicsImageRenderer in leiu of this API.
UIKIT_EXTERN void     UIGraphicsBeginImageContext(CGSize size);
UIKIT_EXTERN void     UIGraphicsBeginImageContextWithOptions(CGSize size, BOOL opaque, CGFloat scale) NS_AVAILABLE_IOS(4_0);
UIKIT_EXTERN UIImage* __nullable UIGraphicsGetImageFromCurrentImageContext(void);
UIKIT_EXTERN void     UIGraphicsEndImageContext(void); 

/* Create a bitmap context. The context draws into a bitmap which is `width'
   pixels wide and `height' pixels high. The number of components for each
   pixel is specified by `space', which may also specify a destination color
   profile. The number of bits for each component of a pixel is specified by
   `bitsPerComponent'. The number of bytes per pixel is equal to
   `(bitsPerComponent * number of components + 7)/8'. Each row of the bitmap
   consists of `bytesPerRow' bytes, which must be at least `width * bytes
   per pixel' bytes; in addition, `bytesPerRow' must be an integer multiple
   of the number of bytes per pixel. `data', if non-NULL, points to a block
   of memory at least `bytesPerRow * height' bytes. If `data' is NULL, the
   data for context is allocated automatically and freed when the context is
   deallocated. `bitmapInfo' specifies whether the bitmap should contain an
   alpha channel and how it's to be generated, along with whether the
   components are floating-point or integer. */

CG_EXTERN CGContextRef __nullable CGBitmapContextCreate(void * __nullable data,
    size_t width, size_t height, size_t bitsPerComponent, size_t bytesPerRow,
    CGColorSpaceRef cg_nullable space, uint32_t bitmapInfo)
    CG_AVAILABLE_STARTING(__MAC_10_0, __IPHONE_2_0);
```
**UIGraphicsBeginImage**：经过测试当创建一个 宽高都为5000的size时，内存疯狂上涨，约为5000 * 5000 * scale^2 * 4。  
**CGBitmapContextCreate**：同样的测试,宽高都为5000的size时，内存疯狂上涨，约为5000 * 5000 * bitsPerComponent。

如果我们截屏图片的目的是保存到相册，不是为了显示截屏图片，尽量采用比UIGraphicsBeginImageContex底层的方案；如果是为了显示，尽量采用UIGraphicsBeginImageContex，但要确保UIGraphicsBeginImageContext和UIGraphicsEndImageContext必须成对出现。

## 三、截屏方案
常用方法如下，
```
+ (UIImage *)snapshottingWithView:(UIView *)inputView {

    UIGraphicsBeginImageContextWithOptions(inputView.frame.size, inputView.opaque, 0.0);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    [inputView.layer renderInContext:context];
    
    UIImage *targetImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    return targetImage;
}
```
这样我就好奇别人的超长图截屏方案是怎么实现的。如果是大分辨率图片，在特定条件下，如果直接用上述方案很容易引往往容易出现OOM。

## 四、常用图片框架SDWebImage
4.3.0
```
  
    /**
     * By default, images are decoded respecting their original size. On iOS, this flag will scale down the
     * images to a size compatible with the constrained memory of devices.
     * If `SDWebImageProgressiveDownload` flag is set the scale down is deactivated.
     */
    SDWebImageScaleDownLargeImages = 1 << 12,

- (UIImage *)incrementallyDecodedImageWithData:(NSData *)data finished:(BOOL)finished {
    if (!_imageSource) {
        _imageSource = CGImageSourceCreateIncremental(NULL);
    }
    UIImage *image;
    
    // The following code is from http://www.cocoaintheshell.com/2011/05/progressive-images-download-imageio/
    // Thanks to the author @Nyx0uf
    
    // Update the data source, we must pass ALL the data, not just the new bytes
    CGImageSourceUpdateData(_imageSource, (__bridge CFDataRef)data, finished);
    
    if (_width + _height == 0) {
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(_imageSource, 0, NULL);
        if (properties) {
            NSInteger orientationValue = 1;
            CFTypeRef val = CFDictionaryGetValue(properties, kCGImagePropertyPixelHeight);
            if (val) CFNumberGetValue(val, kCFNumberLongType, &_height);
            val = CFDictionaryGetValue(properties, kCGImagePropertyPixelWidth);
            if (val) CFNumberGetValue(val, kCFNumberLongType, &_width);
            val = CFDictionaryGetValue(properties, kCGImagePropertyOrientation);
            if (val) CFNumberGetValue(val, kCFNumberNSIntegerType, &orientationValue);
            CFRelease(properties);
#pragma <#arguments#>
  在这个地方加入自己的逻辑判断图片，成倍的缩小_height与_width在合理范围内，待验证，期待更优雅的方式
            // When we draw to Core Graphics, we lose orientation information,
            // which means the image below born of initWithCGIImage will be
            // oriented incorrectly sometimes. (Unlike the image born of initWithData
            // in didCompleteWithError.) So save it here and pass it on later.
#if SD_UIKIT || SD_WATCH
            _orientation = [SDWebImageCoderHelper imageOrientationFromEXIFOrientation:orientationValue];
#endif
        }
    }
    
    if (_width + _height > 0) {
        // Create the image
        CGImageRef partialImageRef = CGImageSourceCreateImageAtIndex(_imageSource, 0, NULL);
        
#if SD_UIKIT || SD_WATCH
        // Workaround for iOS anamorphic image
        if (partialImageRef) {
            const size_t partialHeight = CGImageGetHeight(partialImageRef);
            CGColorSpaceRef colorSpace = SDCGColorSpaceGetDeviceRGB();
            CGContextRef bmContext = CGBitmapContextCreate(NULL, _width, _height, 8, 0, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
            if (bmContext) {
                CGContextDrawImage(bmContext, (CGRect){.origin.x = 0.0f, .origin.y = 0.0f, .size.width = _width, .size.height = partialHeight}, partialImageRef);
                CGImageRelease(partialImageRef);
                partialImageRef = CGBitmapContextCreateImage(bmContext);
                CGContextRelease(bmContext);
            }
            else {
                CGImageRelease(partialImageRef);
                partialImageRef = nil;
            }
        }
#endif
        
        if (partialImageRef) {
#if SD_UIKIT || SD_WATCH
            image = [[UIImage alloc] initWithCGImage:partialImageRef scale:1 orientation:_orientation];
#elif SD_MAC
            image = [[UIImage alloc] initWithCGImage:partialImageRef size:NSZeroSize];
#endif
            CGImageRelease(partialImageRef);
        }
    }
    
    if (finished) {
        if (_imageSource) {
            CFRelease(_imageSource);
            _imageSource = NULL;
        }
    }
    
    return image;
}
- (nullable UIImage *)sd_decompressedImageWithImage:(nullable UIImage *)image {
    if (![[self class] shouldDecodeImage:image]) {
        return image;
    }
    
    // autorelease the bitmap context and all vars to help system to free memory when there are memory warning.
    // on iOS7, do not forget to call [[SDImageCache sharedImageCache] clearMemory];
    @autoreleasepool{
        
        CGImageRef imageRef = image.CGImage;
        CGColorSpaceRef colorspaceRef = [[self class] colorSpaceForImageRef:imageRef];
        
        size_t width = CGImageGetWidth(imageRef);
        size_t height = CGImageGetHeight(imageRef);
        
        // kCGImageAlphaNone is not supported in CGBitmapContextCreate.
        // Since the original image here has no alpha info, use kCGImageAlphaNoneSkipLast
        // to create bitmap graphics contexts without alpha info.
        CGContextRef context = CGBitmapContextCreate(NULL,
                                                     width,
                                                     height,
                                                     kBitsPerComponent,
                                                     0,
                                                     colorspaceRef,
                                                     kCGBitmapByteOrderDefault|kCGImageAlphaNoneSkipLast);
        if (context == NULL) {
            return image;
        }
        
        // Draw the image into the context and retrieve the new bitmap image without alpha
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
        CGImageRef imageRefWithoutAlpha = CGBitmapContextCreateImage(context);
        UIImage *imageWithoutAlpha = [[UIImage alloc] initWithCGImage:imageRefWithoutAlpha scale:image.scale orientation:image.imageOrientation];
        CGContextRelease(context);
        CGImageRelease(imageRefWithoutAlpha);
        
        return imageWithoutAlpha;
    }
}
```
在图片解码中，并未判断图片尺寸，故如果返回的图片较大，像素较高（比如数码相机拍摄的高清照片，一张几十兆）时，会导致内存暴涨OOM。
