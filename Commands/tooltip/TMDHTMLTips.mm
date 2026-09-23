//
//  TMDHTMLTips.mm
//
//  Created by Ciarán Walsh on 2007-08-19.
//

#import "TMDHTMLTips.h"

/*
"$DIALOG" tooltip --text '‘foobar’'
"$DIALOG" tooltip --html '<h1>‘foobar’</h1>'
*/

static NSString* CSSString (NSString* str)
{
	str = [str stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
	str = [str stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
	return [NSString stringWithFormat:@"'%@'", str];
}

@interface TMDHTMLTip () <WKNavigationDelegate>
{
	WKWebView* webView;

	NSDate* didOpenAtDate; // ignore mouse moves for the next second
	NSPoint mousePositionWhenOpened;
}
- (void)setContent:(NSString*)content transparent:(BOOL)transparent;
- (void)runUntilUserActivity:(id)sender;
@end

@implementation TMDHTMLTip
// ==================
// = Setup/teardown =
// ==================
+ (void)showWithContent:(NSString*)content atLocation:(NSPoint)point transparent:(BOOL)transparent
{
	TMDHTMLTip* tip = [TMDHTMLTip new];
	[tip setFrameTopLeftPoint:point];
	[tip setContent:content transparent:transparent]; // The tooltip will show itself automatically when the HTML is loaded
}

- (id)init;
{
	if(self = [self initWithContentRect:NSMakeRect(0, 0, 1, 1) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO])
	{
		// Since we are relying on `setReleaseWhenClosed:`, we need to ensure that we are over-retained.
		CFBridgingRetain(self);
		[self setReleasedWhenClosed:YES];
		[self setAlphaValue:0.97];
		[self setOpaque:NO];
		[self setBackgroundColor:[NSColor clearColor]];
		[self setHasShadow:YES];
		[self setLevel:NSStatusWindowLevel];
		[self setHidesOnDeactivate:YES];
		[self setIgnoresMouseEvents:YES];

		WKWebViewConfiguration* configuration = [WKWebViewConfiguration new];
		configuration.suppressesIncrementalRendering = YES;

		webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
		[webView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[webView setNavigationDelegate:self];
		[webView setValue:@NO forKey:@"drawsBackground"];

		[self setContentView:webView];
	}
	return self;
}

- (void)dealloc
{
	webView.navigationDelegate = nil;
}

// ===========
// = Webview =
// ===========
- (NSRect)screenFrame
{
	// Find the screen which we are displaying on
	NSPoint pos = NSMakePoint(NSMinX(self.frame), NSMaxY(self.frame));
	for(NSScreen* candidate in [NSScreen screens])
	{
		if(NSPointInRect(pos, [candidate frame]))
			return [candidate visibleFrame];
	}
	return [[NSScreen mainScreen] visibleFrame];
}

- (void)setContent:(NSString*)content transparent:(BOOL)transparent
{
	// Previously set via WebPreferences: the user’s font (as standard and fixed font) and font size
	NSString* fontName = [NSUserDefaults.standardUserDefaults stringForKey:@"fontName"];
	NSInteger fontSize = [NSUserDefaults.standardUserDefaults integerForKey:@"fontSize"] ?: 11;
	NSFont* font = (fontName ? [NSFont fontWithName:fontName size:fontSize] : nil) ?: [NSFont userFixedPitchFontOfSize:fontSize];

	NSString* fullContent =	@"<html>"
				@"<head>"
				@"  <style type='text/css' media='screen'>"
				@"      body {"
				@"          background: %@;"
				@"          margin: 0;"
				@"          padding: 2px;"
				@"          overflow: hidden;"
				@"          display: table-cell;"
				@"          max-width: 800px;"
				@"          font-family: %@, monospace;"
				@"          font-size: %ldpx;"
				@"      }"
				@"      pre, code, kbd, samp, tt { font-family: %@, monospace; font-size: %ldpx; }"
				@"      pre { white-space: pre-wrap; }"
				@"  </style>"
				@"</head>"
				@"<body>%@</body>"
				@"</html>";

	NSString* family = CSSString(font.familyName ?: @"Menlo");
	fullContent = [NSString stringWithFormat:fullContent, transparent ? @"transparent" : @"#F6EDC3", family, (long)fontSize, family, (long)fontSize, content ?: @""];

	// The web view is given a large size so that the content is laid out as wide as allowed, then sized down to fit the content
	NSRect screenFrame = [self screenFrame];
	NSPoint topLeft = NSMakePoint(NSMinX(self.frame), NSMaxY(self.frame));
	[self setContentSize:NSMakeSize(NSWidth(screenFrame) - NSWidth(screenFrame) / 3.0, NSHeight(screenFrame))];
	[self setFrameTopLeftPoint:topLeft];

	[webView loadHTMLString:fullContent baseURL:nil];
}

- (void)sizeToContentWithCompletionHandler:(void(^)())handler
{
	[webView evaluateJavaScript:@"(() => { const r = document.body.getBoundingClientRect(); return [r.right, r.bottom]; })()" completionHandler:^(id result, NSError* error){
		NSArray* size = [result isKindOfClass:[NSArray class]] && [result count] == 2 ? result : @[ @100, @20 ];
		double width  = ceil([size[0] doubleValue]);
		double height = ceil([size[1] doubleValue]);

		// Current tooltip position
		NSPoint pos = NSMakePoint(NSMinX(self.frame), NSMaxY(self.frame));
		NSRect screenFrame = [self screenFrame];

		NSRect frame      = [self frameRectForContentRect:NSMakeRect(0, 0, width, height)];
		frame.size.width  = std::min(NSWidth(frame), NSWidth(screenFrame));
		frame.size.height = std::min(NSHeight(frame), NSHeight(screenFrame));
		[self setFrame:frame display:NO];

		pos.x = std::max(NSMinX(screenFrame), std::min(pos.x, NSMaxX(screenFrame)-NSWidth(frame)));
		pos.y = std::min(std::max(NSMinY(screenFrame)+NSHeight(frame), pos.y), NSMaxY(screenFrame));

		[self setFrameTopLeftPoint:pos];
		handler();
	}];
}

- (void)webView:(WKWebView*)sender didFinishNavigation:(WKNavigation*)navigation
{
	[self sizeToContentWithCompletionHandler:^{
		[self orderFront:self];
		[self performSelector:@selector(runUntilUserActivity:) withObject:self afterDelay:0];
	}];
}

- (void)webView:(WKWebView*)sender didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	[self close];
}

- (void)webView:(WKWebView*)sender didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	[self close];
}

// ==================
// = Event handling =
// ==================
- (BOOL)shouldCloseForMousePosition:(NSPoint)aPoint
{
	CGFloat ignorePeriod = [NSUserDefaults.standardUserDefaults floatForKey:@"OakToolTipMouseMoveIgnorePeriod"];
	if(-[didOpenAtDate timeIntervalSinceNow] < ignorePeriod)
		return NO;

	if(NSEqualPoints(mousePositionWhenOpened, NSZeroPoint))
	{
		mousePositionWhenOpened = aPoint;
		return NO;
	}

	NSPoint const& p = mousePositionWhenOpened;
	CGFloat deltaX = p.x - aPoint.x;
	CGFloat deltaY = p.y - aPoint.y;
	CGFloat dist = sqrt(deltaX * deltaX + deltaY * deltaY);

	CGFloat moveThreshold = [NSUserDefaults.standardUserDefaults floatForKey:@"OakToolTipMouseDistanceThreshold"];
	return dist > moveThreshold;
}

- (void)runUntilUserActivity:(id)sender
{
	[self setValue:[NSDate date] forKey:@"didOpenAtDate"];
	mousePositionWhenOpened = NSZeroPoint;

	NSWindow* keyWindow = [NSApp keyWindow];
	BOOL didAcceptMouseMovedEvents = [keyWindow acceptsMouseMovedEvents];
	[keyWindow setAcceptsMouseMovedEvents:YES];

	BOOL slowFadeOut = NO;
	while(NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES])
	{
		[NSApp sendEvent:event];

		if([event type] == NSEventTypeLeftMouseDown || [event type] == NSEventTypeRightMouseDown || [event type] == NSEventTypeOtherMouseDown || [event type] == NSEventTypeKeyDown || [event type] == NSEventTypeScrollWheel)
			break;

		if([event type] == NSEventTypeMouseMoved && [self shouldCloseForMousePosition:[NSEvent mouseLocation]])
		{
			slowFadeOut = YES;
			break;
		}

		if(keyWindow != [NSApp keyWindow] || ![NSApp isActive])
			break;
	}

	[keyWindow setAcceptsMouseMovedEvents:didAcceptMouseMovedEvents];


	[self fadeOutSlowly:slowFadeOut];
}

// =============
// = Animation =
// =============
- (void)fadeOutSlowly:(BOOL)slowly
{
	[NSAnimationContext beginGrouping];

	[NSAnimationContext currentContext].duration = slowly ? 0.5 : 0.25;
	[NSAnimationContext currentContext].completionHandler = ^{
		[self orderOut:self];
		[self close]; // releases the window (and its web view), see init
	};

	[self.animator setAlphaValue:0];

	[NSAnimationContext endGrouping];
}
@end
