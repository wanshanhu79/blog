项目中有个地方需要按页滑动，想了几种方法都没有好好的实现。用系统提供的*pagingEnabled*需要视图宽高和屏幕一致，效果才理想。

但在项目中看到前人的实现，居然可以完美的实现，很惊讶，就研究下了下。

```
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.start = scrollView.contentOffset.x;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    NSLog(@"decelerate:%d", decelerate);
    self.end = scrollView.contentOffset.x;

    NSInteger index = self.index;
    if (self.end - self.start >= 20) {
        index++;
    }else if (self.start - self.end >= 20) {
        index--;
    }

    if (index < 0) {
        index = 0;
    }
    if (index >= 10) {
        index = 9;
    }
    self.index = index;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.collView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:YES];
    });
}
```

`dispatch_async(dispatch_get_main_queue()`这个是关键，没有的话没有效果。`- (**void**)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(**inout** CGPoint *)targetContentOffset`这个方法中也可以实现同样的效果。



经过打印发现：

* 异步block中代码开始执行在`- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate`方法之后，在`- (**void**)scrollViewDidEndDecelerating:(UIScrollView *)scrollView`之前。结束在这个方法之后
* `scrollViewDidEndDecelerating`方法执行后runloop立即退出，可以推断是mode切换了，因为滑动结束了
* 当有异步block中scrollToItemAtIndexPath方法时，`scrollViewDidEndDecelerating`的调用时机提前了很多，runloop不会再处理source0和timer事件，也不会休眠，而是立即退出

异步block我们可以理解为在`- (**void**)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(**BOOL**)decelerate `这个方法之后执行代码，不加异步是在方法中。在这个方法之后调用`- (**void**)scrollToItemAtIndexPath:(NSIndexPath *)indexPath atScrollPosition:(UICollectionViewScrollPosition)scrollPosition animated:(**BOOL**)animated;`，会停止减速，相当于加速减速过程，瞬间完成，并且没有滑动的距离。