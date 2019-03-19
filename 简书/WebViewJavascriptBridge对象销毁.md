#WebViewJavascriptBridge对象销毁
在项目中，为了与js交互，页面A引用了WebViewJavascriptBridge框架创建了WebViewJavascriptBridge对象，没有测试页面A退出时，页面A是否销毁。近日，页面A播放了一段音乐，发现在退出页面A后，音乐仍在播放中，没法关闭，只有kill掉app。
查找后发现，[WebViewJavascriptBridge](https://github.com/marcuswestin/WebViewJavascriptBridge)部分源码如下
>  @implementation WKWebViewJavascriptBridge {
    WKWebView* _webView;
    id<WKNavigationDelegate> _webViewDelegate;
    long _uniqueId;
    WebViewJavascriptBridgeBase *_base;
}
\- (void)setWebViewDelegate:(id<WKNavigationDelegate>)webViewDelegate {
    _webViewDelegate = webViewDelegate;
}

需要在  *-(void)viewWillDisappear:(BOOL)animated* 或 *- (void)viewDidDisappear:(BOOL)animated* 中设置setWebViewDelegate为nil，页面A才会销毁。

项目中导入了[JAPatch](https://github.com/bang590/JSPatch)，main.js中相关代码如下：
> viewWillDisappear: function(animated) {
            self.super().viewWillDisappear(animated);
           self.bridge().setWebViewDelegate(null);
            },

执行后发现页面A销毁了，但相应的WebViewJavascriptBridge对象没有销毁，音乐播放仍在继续中。 想起在[JSPatch文档-内存释放问题](https://github.com/bang590/JSPatch/wiki/JSPatch-%E5%B8%B8%E8%A7%81%E9%97%AE%E9%A2%98#%E5%86%85%E5%AD%98%E9%87%8A%E6%94%BE%E9%97%AE%E9%A2%98)中看到的
> 如果一个 OC 对象被 JS 引用，或者在 JS 创建这个对象，这个 OC 对象在退出作用域后不会马上释放，而是会等到 JS 垃圾回收时才释放，这会导致一些 OC 对象延迟释放,
没有被 JS 引用过的 OC 对象不受影响。

经过测试发现，在页面A销毁后，一分钟左右时间之后，相应的WebViewJavascriptBridge对象会销毁（dealloc会调用），音乐播放停止。怎么在JS中部引用WebViewJavascriptBridge对象呢？KVC。代码如下：
>  viewWillDisappear: function(animated) {
            self.super().viewWillDisappear(animated);
            //delegate是强引用
           self.setValue_forKeyPath(null, "bridge.webViewDelegate");
            },

经过测试，没有问题，完美！
