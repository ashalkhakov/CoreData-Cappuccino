//
//  CPAsynchronousFetchResult.j
//
//  Mirrors NSAsynchronousFetchResult.
//

@import <Foundation/Foundation.j>
@import "CPPersistentStoreResult.j"

@class CPAsynchronousFetchRequest;

/*!
    The result object delivered to the completion block of a
    CPAsynchronousFetchRequest.

    Mirrors NSAsynchronousFetchResult<ResultType>.

    @property fetchRequest  The CPAsynchronousFetchRequest that produced
                            this result.
    @property finalResult   CPArray of managed objects returned by the
                            fetch, or nil if the fetch failed.
*/
@implementation CPAsynchronousFetchResult : CPPersistentStoreResult
{
    CPAsynchronousFetchRequest _fetchRequest @accessors(property=fetchRequest);
    CPArray                    _finalResult  @accessors(property=finalResult);
}

@end
