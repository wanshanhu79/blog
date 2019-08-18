左右列表页面，点击左边列表的某一行，右边列表自动滑动到相应的部分，展示对应的数据。滑动右边列表页面，左边列表选中相应的部分，展示对应的数据。

交互需求：在右侧列表页面，当一个cell向上滑动超过70%的长度后自动吸附到顶部消失，过渡到下一个cell。

### 1.思路

##### 1).向上滑动

声明一个属性记录x开始拖拽时的位置，后续根据`scrollView.contentOffset.y`与初始记录位置的差异来判断是否向上滑动，大于0时为向上滑动。

```
@interface ZLLXXXXXXX ()

@property (nonatomic, assign) CGFloat startMovY;

@end

@implementation ZLLXXXXXXX
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.startMovY = scrollView.contentOffset.y;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.contentOffset.y - self.startMovY > 0) {
 
    }
}
@end
```



##### 2).滑动超过70%的长度

实现 `UIScrollViewDelegate` 协议的 `- (void)scrollViewDidScroll:(UIScrollView *)scrollView`  方法，在方法里拿到tableView的当前展示的cell的第一个，拿到对应的位置跟cell的高度对比，是否大于0.7，进而调用相应的方法滑动到下一行（scrollToRowAtIndexPath）。

代码如下：

```
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    // 取出显示在 视图 且最靠上 的 cell 的 indexPath
    NSIndexPath *topHeaderViewIndexpath = [[self.tableView indexPathsForVisibleRows] firstObject];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:topHeaderViewIndexpath];

    CGFloat height = cell.frame.size.height;
    CGFloat movY = self.tableView.contentOffset.y - cell.frame.origin.y;
    //当是减速的时候再进行自动滑动到下一个，如果手指在拖动中，就不管
    if (movY / height > 0.7 && scrollView.isDecelerating) {
        if (topHeaderViewIndexpath.section != self.dataArray.count - 1) {
            topHeaderViewIndexpath = [NSIndexPath indexPathForRow:0 inSection:topHeaderViewIndexpath.section + 1];
            
              [self.tableView scrollToRowAtIndexPath:topHeaderViewIndexpath atScrollPosition:UITableViewScrollPositionTop animated:YES];
        }
        
    }

}

```

### 2.问题

初步完整代码

```
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // 取出显示在 视图 且最靠上 的 cell 的 indexPath
    NSIndexPath *topHeaderViewIndexpath = [[self.tableView indexPathsForVisibleRows] firstObject];
    
    if (scrollView.contentOffset.y - self.startMovY > 0) {
        ///用这个方法会引起抖动
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:topHeaderViewIndexpath];
     
        CGFloat height = cell.frame.size.height;
        CGFloat movY = self.tableView.contentOffset.y - cell.frame.origin.y;
        //当是减速的时候再进行自动滑动到下一个，如果手指在拖动中，就不管
        if (movY / height > 0.7) {
            if (topHeaderViewIndexpath.section != self.dataArray.count - 1) {
                topHeaderViewIndexpath = [NSIndexPath indexPathForRow:0 inSection:topHeaderViewIndexpath.section + 1];
                 [self.tableView scrollToRowAtIndexPath:topHeaderViewIndexpath atScrollPosition:UITableViewScrollPositionTop animated:YES];
            }
            
        }
    }
    // 左侧 talbelView 移动到的位置 indexPath
    //  NSIndexPath *moveToIndexpath = [NSIndexPath indexPathForRow:topHeaderViewIndexpath.row inSection:0];
    self.updateSelectRowBlock(topHeaderViewIndexpath);

}
```

* 当cell高度未超过一屏时，只滑动右边列表，无法选中最后一个数据

  因为右侧列表的最后一个cell无法滑动到顶部。**解决放大：cell的高度最小为一屏**

* cell向上滑动过程充，headerView会抖动（cell高度均超过一屏）

  这个过程中发现scrollToRowAtIndexPath并没调用，推测是，获取到了相应的cell，又是使用的自动布局。**换`rectForRowAtIndexPath`方法可以解决问题**，原因还待探索。

* 当手指一直拖动，且一个cell向上滑动超过70%的长度，会自动跳动到下一个cell，效果比较混乱

  判断当不在拖动中时再自动滚动到下一行。**`decelerating`，根据注释选择的这个**

* 在右侧列表自动滑动到下一个cell时，左侧列表的选择cell上下来回滚动。

  这是因为`scrollToRowAtIndexPath`执行这个方法，有动画时`scrollViewDidScroll`这个方法会走我们的逻辑。需要在这个过程中让这个方法不执行，**通过属性记录**，需要在动画执行完成后，重置这个属性。在协议方法`- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView`中做这个事情。



在`scrollViewDidScroll`方法执行过程中，进入了runloop的trackModel。在这个模式下，对属性的修改要等到runloop切换到defaultModel时才有效，不知道这一块是怎么做到的。但是获取没有问题。



### 3.最终代码

```
@interface ZLLXXXXXXX ()

@property (nonatomic, assign) CGFloat startMovY;
///标记在自动滑动中，为了动画效果，同时还不要scrollViewDidScroll的事件
@property (nonatomic, assign) BOOL animationing;

@end

@implementation ZLLXXXXXXX
static NSString *cellIden = @"cell";
static NSString *headerIden = @"header";
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = SBScreenHeight();
    self.tableView.estimatedSectionHeaderHeight = 58;
    [self.tableView registerClass:[SBProductListRightTableViewCell class] forCellReuseIdentifier:cellIden];
    [self.tableView registerClass:[SBProductListRightHeaderView class] forHeaderFooterViewReuseIdentifier:headerIden];
    [self.tableView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.dataArray.count;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath  {
    SBProductListRightTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIden];
    cell.service = self.dataArray[indexPath.section];
    return cell;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    SBProductListRightHeaderView *headerView = [tableView dequeueReusableHeaderFooterViewWithIdentifier:headerIden];
    headerView.titleLabel.text = self.dataArray[section].name;
    return headerView;
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.startMovY = scrollView.contentOffset.y;
    self.animationing = NO;
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
   
    self.animationing = NO;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {

    ///当在scrollToRowAtIndexPath滑动时返回
    if (self.animationing) {
        return;
    }

    // 取出显示在 视图 且最靠上 的 cell 的 indexPath
    NSIndexPath *topHeaderViewIndexpath = [[self.tableView indexPathsForVisibleRows] firstObject];
    
    if (scrollView.contentOffset.y - self.startMovY > 0) {
        ///用这个方法会引起抖动
        //UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:topHeaderViewIndexpath];
        ///用这个方法获取相应indexPath的frame不会，神奇吧
        
        CGRect frame = [self.tableView rectForRowAtIndexPath:topHeaderViewIndexpath];
        CGFloat height = frame.size.height;
        CGFloat movY = self.tableView.contentOffset.y - frame.origin.y;
        //当是减速的时候再进行自动滑动到下一个，如果手指在拖动中，就不管
        if (movY / height > 0.7 && scrollView.isDecelerating) {
            if (topHeaderViewIndexpath.section != self.dataArray.count - 1) {
                topHeaderViewIndexpath = [NSIndexPath indexPathForRow:0 inSection:topHeaderViewIndexpath.section + 1];
                self.selectedIndexPath = topHeaderViewIndexpath;
            }

        }
        _selectedIndexPath = topHeaderViewIndexpath;
    }else{
        //从上往下拖动，不需要改变触发滑动，只需要改变记录值，确定当前选中的是对
        _selectedIndexPath = topHeaderViewIndexpath;
    }
    
    // 左侧 talbelView 移动到的位置 indexPath
  //  NSIndexPath *moveToIndexpath = [NSIndexPath indexPathForRow:topHeaderViewIndexpath.row inSection:0];
    self.updateSelectRowBlock(topHeaderViewIndexpath);
}

- (void)setDataArray:(NSArray<ServiceModel *> *)dataArray {
    _dataArray = dataArray;
    [self.tableView reloadData];
}

-  (void)setSelectedIndexPath:(NSIndexPath *)selectedIndexPath {
    
    if (_selectedIndexPath && _selectedIndexPath.section == selectedIndexPath.section) {
        return;
    }
   
    _selectedIndexPath = selectedIndexPath;
    if (selectedIndexPath.section < self.dataArray.count) {
        self.animationing = YES;
        [self.tableView scrollToRowAtIndexPath:selectedIndexPath atScrollPosition:UITableViewScrollPositionTop animated:YES];
    }
}

@end
```

