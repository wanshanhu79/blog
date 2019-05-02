//
//  ZLLTableViewController.m
//  WeakProxy
//
//  Created by llzhang on 2019/5/1.
//  Copyright © 2019 zll. All rights reserved.
//

#import "ZLLTableViewController.h"
#import "UIScrollView+VerticalScroll.h"
@interface ZLLTableViewController ()<UIScrollViewDelegate>

@end

@implementation ZLLTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"TableView";
#if Condition == 1
    //情景一 调用之前delegate还没有设置
    self.tableView.delegate = nil;
#elif Condition == 2
    //情景二 调用之前delegate已有
#endif

    [self.tableView addObserver:self forKeyPath:@"delegate" options:NSKeyValueObservingOptionNew context:nil];
    
#if Scheme == 1
    //方案一 交换方法实现，新增一个IMP
    [self.tableView zll_beginObserverVerticalScroll];
#elif Scheme == 2
    //方案二 学习KVO，动态派生一个子类，重写方法
     [self.tableView zll_beginObserverVerticalScroll1];
#endif

#if Condition == 1
    self.tableView.delegate = self;
#elif Condition == 2
    
#endif
   
    
    [self.tableView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(change:) name:ZLLverticalScrollNotification object:nil];
}
- (void)dealloc {
    [self.tableView removeObserver:self forKeyPath:@"delegate"];
    [self.tableView removeObserver:self forKeyPath:@"contentOffset"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
#pragma mark -
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSLog(@"%@:%@", keyPath, change);
}

#pragma mark - action
- (void)change:(NSNotification *)noti {
    NSLog(@"change:%@", noti.userInfo);
}
#pragma mark - UIScrollViewDelegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    NSLog(@"ZLLTableViewController:%@", scrollView);
}


@end
