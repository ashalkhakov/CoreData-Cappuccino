//
//  CPAsynchronousFetchRequest.j
//
//  Mirrors NSAsynchronousFetchRequest.
//

@import <Foundation/Foundation.j>
@import "CPPersistentStoreRequest.j"
@import "CPFetchRequest.j"

@class CPAsynchronousFetchResult;

/*!
    A persistent-store request that executes a fetch asynchronously and
    delivers its result to a completion block.

    Mirrors NSAsynchronousFetchRequest<ResultType>.

    Usage:
    @code
        var asyncReq = [CPAsynchronousFetchRequest
                            fetchRequestWithFetchRequest:fetchReq
                                        completionBlock:function(result) {
            var items = [result finalResult];
            [self updateTableWithItems:items];
        }];
        var err = nil;
        [context executeRequest:asyncReq error:@ref(err)];
    @endcode

    The completion block is called with a CPAsynchronousFetchResult
    once the underlying store fetch completes.  The return value of
    -executeRequest:error: is an empty CPAsynchronousFetchResult
    (with finalResult nil) matching Apple's behaviour where the real
    result is delivered asynchronously.
*/
@implementation CPAsynchronousFetchRequest : CPPersistentStoreRequest
{
    CPFetchRequest _fetchRequest      @accessors(property=fetchRequest);
    Function       _completionBlock   @accessors(property=completionBlock);
    double         _estimatedProgress @accessors(property=estimatedProgress);
}

/*!
    Convenience factory.

    @param req   A configured CPFetchRequest.
    @param block A JS function(CPAsynchronousFetchResult) called when the
                 fetch completes.
*/
+ (CPAsynchronousFetchRequest)fetchRequestWithFetchRequest:(CPFetchRequest)req
                                           completionBlock:(Function)block
{
    var asyncReq = [[self alloc] init];
    [asyncReq setFetchRequest:req];
    [asyncReq setCompletionBlock:block];
    return asyncReq;
}

- (id)init
{
    if ((self = [super init]))
    {
        _requestType      = CPAsynchronousFetchRequestType;
        _estimatedProgress = 0.0;
    }
    return self;
}

@end
