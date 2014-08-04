//
//  TabBarControllerViewController.m
//  Vaavud
//
//  Created by Thomas Stilling Ambus on 20/09/2013.
//  Copyright (c) 2013 Andreas Okholm. All rights reserved.
//

#import "TabBarController.h"
#import "UIColor+VaavudColors.h"
#import "CustomSMCalloutDrawnBackgroundView.h"
#import "GuideView.h"

@interface TabBarController ()

@property (nonatomic) GuideView *calloutGuideView;
@property (nonatomic) SMCalloutView *calloutView;
@property (nonatomic) DismissOnTouchUIView *overlayDimmingView;
@property (nonatomic) BOOL isCalloutGuideViewShown;

@end

@implementation TabBarController

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
    }
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
	if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
        self.tabBar.tintColor = [UIColor clearColor];
    }
    else {
        self.tabBar.tintColor = [UIColor vaavudBlueColor];
    }
    
    NSArray* topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"GuideView" owner:self options:nil];
    self.calloutGuideView = (GuideView*) [topLevelObjects objectAtIndex:0];
    self.calloutGuideView.frame = CGRectMake(0, 0, CALLOUT_GUIDE_VIEW_WIDTH, [self.calloutGuideView preferredHeight]);
    self.calloutGuideView.backgroundColor = [UIColor clearColor];
    self.calloutGuideView.headingLabel.textColor = [UIColor darkGrayColor];
    self.calloutGuideView.explanationLabel.textColor = [UIColor darkGrayColor];
    self.calloutGuideView.topSpaceConstraint.constant = 10.0;
    self.calloutGuideView.headingLabelWidthConstraint.constant = CALLOUT_GUIDE_VIEW_WIDTH - 20.0;
    self.calloutGuideView.explanationLabelWidthConstraint.constant = CALLOUT_GUIDE_VIEW_WIDTH - 20.0;
    self.calloutGuideView.labelVerticalSpaceConstraint.constant = 5.0;
    
    UITapGestureRecognizer *calloutGuideViewTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(guideViewTap:)];
    [self.calloutGuideView addGestureRecognizer:calloutGuideViewTapRecognizer];
    
    self.isCalloutGuideViewShown = NO;
    
    self.calloutView = [SMCalloutView new];
    self.calloutView.delegate = self;
}

-(NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void) guideViewTap:(UITapGestureRecognizer*)recognizer {
    [self hideCalloutGuideView:YES];
}

- (void) dismissOverlayView {
    [self hideCalloutGuideView:YES];
}

- (BOOL) isShowingGuideView {
    return self.isCalloutGuideViewShown;
}

- (void) showCalloutGuideView:(NSString*)headingText explanationText:(NSString*)explanationText customPosition:(CGRect)rect inView:(UIView*)inView {
    
    if (self.isCalloutGuideViewShown) {
        [self hideCalloutGuideView:NO];
    }
    
    self.calloutGuideView.headingLabel.text = headingText;
    self.calloutGuideView.explanationLabel.text = explanationText;
    
    CGFloat preferredHeight = [self.calloutGuideView preferredHeight];
    
    UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CALLOUT_GUIDE_VIEW_WIDTH, preferredHeight)];
    self.calloutGuideView.frame = CGRectMake(0, 0, CALLOUT_GUIDE_VIEW_WIDTH, preferredHeight);
    [containerView addSubview:self.calloutGuideView];
    
    self.calloutView.contentView = containerView;
    self.calloutView.backgroundView = [CustomSMCalloutDrawnBackgroundView new];
    
    SMCalloutArrowDirection arrowDirection = SMCalloutArrowDirectionDown;
    CGFloat bottomLayoutGuide = 49.0;
    CGFloat y = self.view.frame.size.height - bottomLayoutGuide - 1.0;
    CGFloat x;
    
    x = rect.origin.x;
    y = rect.origin.y;
    arrowDirection = SMCalloutArrowDirectionAny;
    
    if (!inView) {
        inView = self.view;
    }
    
    CGFloat overlayDimmingViewHeight = inView.frame.size.height;
    
    if ([inView isKindOfClass:[UIScrollView class]]) {
        overlayDimmingViewHeight = MAX(overlayDimmingViewHeight, ((UIScrollView*) inView).contentSize.height);
    }
    
    CGRect overlayDimmingViewRect = CGRectMake(0, 0, inView.frame.size.width, overlayDimmingViewHeight);
    
    self.overlayDimmingView = [[DismissOnTouchUIView alloc] initWithFrame:overlayDimmingViewRect];
    self.overlayDimmingView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.0];
    [inView addSubview:self.overlayDimmingView];
    self.overlayDimmingView.delegate = self;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.overlayDimmingView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.3];
    } completion:nil];
    
    [self.calloutView presentCalloutFromRect:CGRectMake(x, y, rect.size.width, rect.size.height)
                                      inView:inView
                           constrainedToView:inView
                    permittedArrowDirections:arrowDirection
                                    animated:YES];
    
    self.isCalloutGuideViewShown = YES;
}

- (void) hideCalloutGuideView:(BOOL)animated {
    
    self.isCalloutGuideViewShown = NO;
    
    if (self.calloutView.window) {
        [self.calloutView dismissCalloutAnimated:animated];
    }
    
    if (self.overlayDimmingView) {
        self.overlayDimmingView.delegate = nil;
        if (animated) {
            
            [UIView animateWithDuration:0.3 animations:^{
                self.overlayDimmingView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.0];
            } completion:^(BOOL finished) {
                [self.overlayDimmingView removeFromSuperview];
                self.overlayDimmingView = nil;
            }];
        }
        else {
            [self.overlayDimmingView removeFromSuperview];
            self.overlayDimmingView = nil;
        }
    }
}

@end
