//
//  ViewController.m
//  kvoDemo
//
//  Created by wyb on 2017/8/14.
//  Copyright © 2017年 中天易观. All rights reserved.
//

#import "ViewController.h"
#import "Person.h"
#import "NSObject+KVO.h"


@interface ViewController ()

@property(nonatomic,strong)Person *person;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.person = [[Person alloc]init];
    [self.person yb_addObserver:self forKey:@"name" withBlock:^(id observedObject, NSString *observedKey, id oldValue, id newValue) {

        NSLog(@"%@",newValue);

    }];
    
 
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    self.person.name = @"wang";
}




@end
