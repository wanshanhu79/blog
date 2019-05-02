//
//  ZLLScrollViewController.m
//  WeakProxy
//
//  Created by llzhang on 2019/5/1.
//  Copyright © 2019 zll. All rights reserved.
//

#import "ZLLScrollViewController.h"
#import "UIScrollView+VerticalScroll.h"
@interface ZLLScrollViewController () <UIScrollViewDelegate>
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;

@end

@implementation ZLLScrollViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"ScrollView";
#if Condition == 1
    //情景一 调用之前delegate还没有设置
    self.scrollView.delegate = nil;
#elif Condition == 2
    //情景二 调用之前delegate已有
#endif
    
    [self.scrollView addObserver:self forKeyPath:@"delegate" options:NSKeyValueObservingOptionNew context:nil];
    
#if Scheme == 1
    //方案一 交换方法实现，新增一个IMP
    [self.scrollView zll_beginObserverVerticalScroll];
#elif Scheme == 2
    //方案二 学习KVO，动态派生一个子类，重写方法
    [self.scrollView zll_beginObserverVerticalScroll1];
#endif
    
#if Condition == 1
    self.scrollView.delegate = self;
#elif Condition == 2
    
#endif
    [self.scrollView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(change:) name:ZLLverticalScrollNotification object:nil];
    // Do any additional setup after loading the view.
}
- (void)dealloc {
    [self.scrollView removeObserver:self forKeyPath:@"delegate"];
    [self.scrollView removeObserver:self forKeyPath:@"contentOffset"];
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
    NSLog(@"ZLLScrollViewController:%@", scrollView);
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
