//
//  CPFetchRequest.j
//
//  Created by Raphael Bartolome on 11.11.09.
//

@import <Foundation/Foundation.j>

@class CPEntityDescription;

/**
    Parameters for a fetch request.

    The request object is also used to transfer errors back to the requester
    using the error property.

    @property transparentFetch The result of the fetch is not stored in the context.
                       This can be used to directly access the underlying
                       storage without the overhead of storing the data in the managed context.
*/
@implementation CPFetchRequest : CPObject
{
    // Entity
    CPEntityDescription _entity @accessors(property=entity);

    // Fetch Contraints
    CPPredicate _predicate @accessors(property=predicate);
    CPInteger _fetchLimit @accessors(property=fetchLimit);
    CPInteger _fetchOffset @accessors(property=fetchOffset);
    CPInteger _fetchBatchSize @accessors(property=fetchBatchSize);
    CPArray _affectedStores @accessors(property=affectedStores);

    // Sorting
    CPArray _sortDescriptors @accessors(property=sortDescriptors);

    // Managing How Results Are Returned
    CPArray _propertiesToFetch @accessors(property=propertiesToFetch);
    BOOL _transparentFetch @accessors(property=transparentFetch);

    // response data set if an error occured during a fetch
    CPError _error @accessors(property=error);
}

@end

