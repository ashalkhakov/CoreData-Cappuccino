//
//  CPHTTPIncrementalStoreType.j
//
//  HTTP incremental persistent store type for Cappuccino CoreData.
//  Talks to OrderFlow backend OrdersAPI endpoints /cdFetch and /cdSave.
//

@import <Foundation/Foundation.j>

/*!
    Base URL for the OrdersAPI backend, e.g. @"http://localhost:8080/api/"
    The URL must end with a slash or a non-slash (the store normalises it).
*/
CPHTTPIncrementalStoreConfigurationKeyBaseURL = "CPHTTPIncrementalStoreBaseURL";

@implementation CPHTTPIncrementalStoreType : CPPersistentStoreType
{
}

+ (CPString)type
{
    return "CPHTTPIncrementalStore";
}

+ (Class)storeClass
{
    return [CPHTTPIncrementalStore class];
}

@end
