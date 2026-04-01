//
//  CPOrderFlowStoreType.j
//
//  Type registration for CPOrderFlowStore.
//

@import <Foundation/Foundation.j>


@implementation CPOrderFlowStoreType : CPPersistentStoreType
{
}

+ (CPString)type
{
    return @"CPOrderFlowStore";
}

+ (Class)storeClass
{
    return [CPOrderFlowStore class];
}

@end
