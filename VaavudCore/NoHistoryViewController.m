//
//  NoHistoryViewController.m
//  Vaavud
//
//  Created by Thomas Stilling Ambus on 27/02/2014.
//  Copyright (c) 2014 Andreas Okholm. All rights reserved.
//

#import "NoHistoryViewController.h"

@interface NoHistoryViewController ()

@property (nonatomic, weak) IBOutlet UILabel *noMeasurementsLabel;
@property (nonatomic, weak) IBOutlet UILabel *gotoMeasureLabel;
@property (nonatomic, weak) IBOutlet UIView *arrowView;

@end

@implementation NoHistoryViewController

- (void) viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"HISTORY_TITLE", nil);
    self.noMeasurementsLabel.text = NSLocalizedString(@"HISTORY_NO_MEASUREMENTS", nil);
    self.gotoMeasureLabel.text = NSLocalizedString(@"HISTORY_GO_TO_MEASURE", nil);
    
    self.noMeasurementsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.noMeasurementsLabel.numberOfLines = 0;
    self.gotoMeasureLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.gotoMeasureLabel.numberOfLines = 0;
}

@end
