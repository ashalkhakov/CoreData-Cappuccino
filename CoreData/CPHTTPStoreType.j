//
//  CPHTTPStoreType.j
//
//  HTTP-backed incremental store type targeting the OrdersAPI cdFetch / cdSave
//  endpoints.
//
//  Configuration keys (pass in the storeConfiguration dictionary):
//
//    CPHTTPStoreBaseURL             - required; the OrdersAPI root URL,
//                                     e.g. "http://host/wa/OrdersAPI"
//    CPHTTPStoreTimeout             - optional request timeout in seconds
//    CPHTTPStoreDefaultIncludeDepth - optional default relationship include depth
//                                     (default: 1)
//

@import <Foundation/CPObject.j>
@import "CPPersistentStoreType.j"

CPHTTPStoreBaseURL             = @"CPHTTPStoreBaseURL";
CPHTTPStoreTimeout             = @"CPHTTPStoreTimeout";
CPHTTPStoreDefaultIncludeDepth = @"CPHTTPStoreDefaultIncludeDepth";


@implementation CPHTTPStoreType : CPPersistentStoreType
{
}

+ (CPString)type
{
    return @"CPHTTPStore";
}

+ (Class)storeClass
{
    return [CPHTTPStore class];
}

@end
