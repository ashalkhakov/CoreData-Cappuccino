//
//  CPFetchRequest.j
//
//  Created by Raphael Bartolome on 11.11.09.
//

@import <Foundation/Foundation.j>

@class CPEntityDescription;

// Result type constants, matching Apple's NSFetchRequestResultType.
CPManagedObjectResultType   = 0;
CPManagedObjectIDResultType = 1;
CPDictionaryResultType      = 2;
CPCountResultType           = 4;

/**
    Parameters for a fetch request.

    The request object is also used to transfer errors back to the requester
    using the error property.

    @property transparentFetch The result of the fetch is not stored in the context.
                       This can be used to directly access the underlying
                       storage without the overhead of storing the data in the managed context.
    @property resultType Controls the type of objects returned. Use CPCountResultType to
                       request a server-side count instead of objects.
    @property propertiesToFetch When resultType is CPDictionaryResultType, limits which
                       attributes are included in the returned dictionaries.
    @property relationshipKeyPathsForPrefetching Relationship key paths to eagerly fetch
                       alongside the primary objects. The HTTP store sends these as
                       include.relationships in the cdFetch request body.
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
    CPInteger _resultType @accessors(property=resultType);
    CPArray _propertiesToFetch @accessors(property=propertiesToFetch);
    CPArray _relationshipKeyPathsForPrefetching @accessors(property=relationshipKeyPathsForPrefetching);
    BOOL _transparentFetch @accessors(property=transparentFetch);

    // response data set if an error occured during a fetch
    CPError _error @accessors(property=error);
}

- (id)init
{
    if (self = [super init])
    {
        _fetchLimit = 0;
        _fetchOffset = 0;
        _resultType = CPManagedObjectResultType;
    }
    return self;
}

@end

