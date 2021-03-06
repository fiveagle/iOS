//
//  UIColor+VaavudColors.m
//  Vaavud
//
//  Created by Thomas Stilling Ambus on 19/02/2014.
//  Copyright (c) 2014 Andreas Okholm. All rights reserved.
//

#import "UIColor+VaavudColors.h"

@implementation UIColor (VaavudColors)

+ (UIColor *)vaavudBlueColor {
    return [UIColor colorWithRed:(0.0/255.0) green:(161.0/255.0) blue:(225.0/255.0) alpha:1.0];
}

+ (UIColor *)vaavudRedColor {
    return [UIColor colorWithRed:(209.0/255.0) green:(42.0/255.0) blue:(47.0/255.0) alpha:1.0];
}

+ (UIColor *)vaavudGreenColor {
    return [UIColor colorWithRed:(108.0/255.0) green:(192.0/255.0) blue:(73.0/255.0) alpha:1.0];
}

+ (UIColor *)vaavudGreyColor {
    return [UIColor colorWithRed:(228.0/255.0) green:(231.0/255.0) blue:(232.0/255.0) alpha:1.0];
}

+ (UIColor *)vaavudLightGreyColor {
    return [UIColor colorWithRed:(122.0/255.0) green:(134.0/255.0) blue:(140.0/255.0) alpha:1.0];
}

+ (UIColor *)vaavudDarkGreyColor {
    return [UIColor colorWithRed:(48.0/255.0) green:(62.0/255.0) blue:(72.0/255.0) alpha:1.0];
}

+ (UIColor *)vaavudTabbarSelectedColor {
    return [UIColor colorWithRed:(241.0/255.0) green:(242.0/255.0) blue:(243.0/255.0) alpha:1.0];
}

+ (UIColor *)vaavudColor {
    return [UIColor vaavudBlueColor];
}

@end
