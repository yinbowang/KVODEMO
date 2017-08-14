//
//  NSObject+KVO.m
//  kvoDemo
//
//  Created by wyb on 2017/8/14.
//  Copyright © 2017年 中天易观. All rights reserved.
//

#import "NSObject+KVO.h"
#import <objc/runtime.h>
#import <objc/message.h>


NSString *const YBAssociateArrayKey = @"YBAssociateArrayKey";
NSString *const kYBKVOClassPrefix = @"YBKVOClassPrefix_";

@interface YBObserverInfo : NSObject

/** 监听者 */
@property (nonatomic, weak) id observer;

/** 监听的属性 */
@property (nonatomic, copy) NSString *key;

/** 回调的block */
@property (nonatomic, copy) YBObserverBlock callback;


- (instancetype)initWithObserver:(id)observer key:(NSString *)key callback:(YBObserverBlock)callback;

@end

@implementation YBObserverInfo

- (instancetype)initWithObserver:(id)observer key:(NSString *)key callback:(YBObserverBlock)callback
{
    if (self = [super init]) {
        _observer = observer;
        _key = key;
        _callback = callback;
    }
    
    return self;
}

@end


@implementation NSObject (KVO)

- (void)yb_addObserver:(NSObject *)observer forKey:(NSString *)key withBlock:(YBObserverBlock) block
{
    //1. 检查对象的类有没有对应的setter 方法，如果没有就抛出异常
    SEL setterSelector = NSSelectorFromString([self setterForKey:key]);
    // 获取实例方法
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    if (setterSelector == nil) {
        NSLog(@"找不到方法");
        return;
    }
    // 2.检查对象 isa 指向的类是不是一个 KVO 类。如果不是，新建一个继承原来类的子类，并把 isa 指向这个新建的子类
    Class class = object_getClass(self);
    NSString *className = NSStringFromClass(class);
    //如果类名不带有前缀，就新建子类
    if (![className hasPrefix:kYBKVOClassPrefix]) {
        class = [self ybKvoClassWithOriginalClassName:className];
        object_setClass(self, class);
    }
    
    // 3. 为kvo class添加setter方法的实现
    const char *types = method_getTypeEncoding(setterMethod);
    class_addMethod(class, setterSelector, (IMP)yb_setter, types);
    
    // 4. 添加该观察者到观察者列表中
    // 4.1 创建观察者的信息
    YBObserverInfo *info = [[YBObserverInfo alloc] initWithObserver:observer key:key callback:block];
    // 4.2 获取关联对象(装着所有监听者的数组)
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(YBAssociateArrayKey));
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge const void *)(YBAssociateArrayKey), observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    [observers addObject:info];
    
}

- (void)yb_removeObserver:(NSObject *)observer forKey:(NSString *)key
{
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(YBAssociateArrayKey));
    if (!observers) return;
    
    for (YBObserverInfo *info in observers) {
        if([info.key isEqualToString:key]) {
            [observers removeObject:info];
            break;
        }
    }

}

/**
 *  重写setter方法, 新方法在调用原方法后, 通知每个观察者(调用传入的block)
 */
void yb_setter(id self, SEL _cmd, id newValue)
{
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = [self getterForSetter:setterName];
    
    
    if (!getterName) {
        NSLog(@"找不到getter方法");
    }
    
    // 获取旧值
    id oldValue = [self valueForKey:getterName];
    
    // 调用原类的setter方法
    
    struct objc_super superClazz = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    
    ((void (*)(void *, SEL, id))objc_msgSendSuper)(&superClazz, _cmd, newValue);
  
    // 找出观察者的数组, 调用对应对象的callback
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)(YBAssociateArrayKey));
    // 遍历数组
    for (YBObserverInfo *info in observers) {
        if ([info.key isEqualToString:getterName]) {
            // gcd异步调用callback
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                info.callback(info.observer, getterName, oldValue, newValue);
            });
        }
    }
}



- (Class) ybKvoClassWithOriginalClassName:(NSString *)className
{
    // 生成kvo_class的类名
    NSString *kvoClassName = [kYBKVOClassPrefix stringByAppendingString:className];
    Class kvoClass = NSClassFromString(kvoClassName);
    // 如果kvo class已经被注册过了, 则直接返回
    if (kvoClass) {
        return kvoClass;
    }
    
    Class originClass = object_getClass(self);
    // 创建继承自原来类的子类
    kvoClass = objc_allocateClassPair(originClass, kvoClassName.UTF8String, 0);
    
    // 修改kvo class方法的实现, 学习Apple的做法, 隐瞒这个kvo_class
    Method classMethod = class_getInstanceMethod(kvoClass, @selector(class));
    const char *types = method_getTypeEncoding(classMethod);
    class_addMethod(kvoClass, @selector(class), (IMP)class, types);
    
    // 注册kvo_class
    objc_registerClassPair(kvoClass);
    
    return kvoClass;
}

/**
 *  模仿Apple的做法, 欺骗人们这个kvo类还是原类
 */
Class class(id self, SEL cmd)
{
    Class clazz = object_getClass(self); // kvo_class
    Class superClazz = class_getSuperclass(clazz); // origin_class
    return superClazz; // origin_class
}


/**
 *  根据setter方法名返回getter方法名
 */
- (NSString *)getterForSetter:(NSString *)key
{
    // setName: -> Name -> name
    
    // 1. 去掉set
    NSRange range = [key rangeOfString:@"set"];
    
    NSString *subStr1 = [key substringFromIndex:range.location + range.length];
    
    // 2. 首字母转换成大写
    unichar c = [subStr1 characterAtIndex:0];
    NSString *subStr2 = [subStr1 stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[NSString stringWithFormat:@"%c", c+32]];
    
    // 3. 去掉最后的:
    NSRange range2 = [subStr2 rangeOfString:@":"];
    NSString *getter = [subStr2 substringToIndex:range2.location];
    
    return getter;
}

/**
 *  根据getter方法名返回setter方法名
 */
- (NSString *)setterForKey:(NSString *)key
{
    // 如 name
    // 第一个字母大写 N
    NSString *firstLetter = [[key substringToIndex:1] uppercaseString];
    // 剩下的字母 ame
    NSString *remainLetters = [key substringFromIndex:1];
    
    // setName:
    NSString *setter = [NSString stringWithFormat:@"set%@%@:",firstLetter,remainLetters];
    
    return setter;
}

@end
