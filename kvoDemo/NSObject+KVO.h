//
//  NSObject+KVO.h
//  kvoDemo
//
//  Created by wyb on 2017/8/14.
//  Copyright © 2017年 中天易观. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^YBObserverBlock)(id observedObject, NSString *observedKey, id oldValue, id newValue);

@interface NSObject (KVO)

- (void)yb_addObserver:(NSObject *)observer forKey:(NSString *)key withBlock:(YBObserverBlock) block;

- (void)yb_removeObserver:(NSObject *)observer forKey:(NSString *)key;

@end
