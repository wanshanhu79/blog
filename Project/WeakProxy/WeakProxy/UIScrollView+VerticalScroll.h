// 判断scroll是否是在上下滑动
//  UIScrollView+VerticalScroll.h
//  WeakProxy
//
//  Created by llzhang on 2019/5/1.
//  Copyright © 2019 zll. All rights reserved.
//

#import <UIKit/UIKit.h>

/// 上下滑动时的通知
UIKIT_EXTERN NSString * _Nullable const ZLLverticalScrollNotification;
/// 上下滑动时的通知的userInfo 中滑动距离的key
UIKIT_EXTERN NSString * _Nullable const ZLLverticalScrollDistanceKey;
/// 上下滑动时的通知的userInfo 中滑动视图的key
UIKIT_EXTERN NSString * _Nullable const ZLLverticalScrollViewKey;

NS_ASSUME_NONNULL_BEGIN
/// 主要是hook的思路
@interface UIScrollView (VerticalScrollHook)

/// 更新是否监听scrollview 上下滑动，滑动会发出通知
- (void)zll_beginObserverVerticalScroll;

@end

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
/// 派生一个子类 思路出自IMYAOPTableView
@interface UIScrollView (VerticalScrollDerive)

/// 开启监听
- (void)zll_beginObserverVerticalScroll1;

@end

NS_ASSUME_NONNULL_END
