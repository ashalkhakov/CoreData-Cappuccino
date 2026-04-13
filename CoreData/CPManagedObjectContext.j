//
//  CPManagedObjectContext.j
//
//  Created by Raphael Bartolome on 07.10.09.
//

@import <Foundation/Foundation.j>
@import "CPManagedObject.j"
@import "CPManagedObjectID.j"
@import "CPManagedObjectModel.j"
@import "CPPersistentStore.j"
@import "CPPersistentStoreCoordinator.j"
@import "CPPersistentStoreRequest.j"
@import "CPAsynchronousFetchRequest.j"
@import "CPAsynchronousFetchResult.j"

/*

***** HEADER *****
@public
- (CPArray) executeFetchRequest:(CPFetchRequest)aFetchRequest;
- (CPArray) executeStoreFetchRequest:(CPFetchRequest)aFetchRequest;
- (void) executeStoreFetchRequestAsync:(CPFetchRequest)aFetchRequest completionHandler:(Function)handler;
- (void) saveChangesWithCompletionHandler:(Function)handler;

@private
- (CPSet) _executeLocalFetchRequest:(CPFetchRequest) aFetchRequest;
- (CPSet) _executeStoreFetchRequest:(CPFetchRequest) aFetchRequest;

- (CPManagedObject) _insertedObjectWithID:(CPManagedObjectID) aObjectID;
- (CPManagedObject) _updatedObjectWithID:(CPManagedObjectID) aObjectID;
- (CPManagedObject) _deletedObjectWithID:(CPManagedObjectID) aObjectID;
- (BOOL) reset;
- (void) _objectDidChange:(CPManagedObject) aObject;
- (CPManagedObject) _registerObject:(CPManagedObject) object;
- (CPManagedObject) _registerFetchedObject:(CPManagedObject) object;
- (void) _unregisterObject:(CPManagedObject) object;
- (void) _deleteObject: ({CPManagedObject}) aObject saveAfterDeletion:(BOOL) saveAfterDeletion;

*/

// Notifications.
CPManagedObjectContextObjectsDidChangeNotification = "CPManagedObjectContextObjectsDidChangeNotification";
CPManagedObjectContextDidSaveNotification = "CPManagedObjectContextDidSaveNotification";
CPManagedObjectContextDidLoadObjectsNotification = "CPManagedObjectContextDidLoadObjectsNotification";
CPManagedObjectContextDidSaveChangedObjectsNotification = "CPManagedObjectContextDidSaveChangedObjectsNotification";
CPManagedObjectContextDidSaveAllObjectsNotification = "CPManagedObjectContextDidSaveAllObjectsNotification";

CPDInsertedObjectsKey = "CPDInsertedObjectsKey";
CPDUpdatedObjectsKey = "CPDUpdatedObjectsKey";
CPDDeletedObjectsKey = "CPDDeletedObjectsKey";

// Error domain and user-info keys for validation failures.
CPCoreDataErrorDomain          = @"CPCoreDataErrorDomain";
CPDetailedErrorsKey            = @"CPDetailedErrors";
CPValidationMultipleErrorsError = 1550;
CPValidationMissingMandatoryPropertyError = 1570;


@implementation CPManagedObjectContext : CPObject
{
    BOOL _autoSaveChanges;
    CPPersistentStoreCoordinator _storeCoordinator @accessors(property=storeCoordinator);

    CPMutableSet _registeredObjects;
    CPMutableSet _insertedObjectIDs;
    CPMutableSet _updatedObjectIDs;
    CPMutableSet _deletedObjects;
}

- (id) init
{
    if ((self = [super init]))
    {
        _autoSaveChanges = false;
        _registeredObjects = [CPMutableSet new];
        _insertedObjectIDs = [CPMutableSet new];
        _updatedObjectIDs = [CPMutableSet new];
        _deletedObjects = [CPMutableSet new];
    }

    return self;
}

- (id) initWithPersistentStoreCoordinator:(CPPersistentStoreCoordinator)aStoreCoordinator
{
    if ((self = [super init]))
    {
        _autoSaveChanges = false;
        _registeredObjects = [CPMutableSet new];
        _insertedObjectIDs = [CPMutableSet new];
        _updatedObjectIDs = [CPMutableSet new];
        _deletedObjects = [CPMutableSet new];

        _storeCoordinator = aStoreCoordinator;
        [self loadAll];
    }

    return self;
}

- (void)dealloc
{
    [super dealloc];
}

- (CPManagedObjectModel)model
{
    return [_storeCoordinator managedObjectModel];
}

- (CPPersistentStore)store
{
    return [_storeCoordinator persistentStore];
}

- (BOOL) autoSaveChanges
{
    return _autoSaveChanges;
}

- (void) setAutoSaveChanges:(BOOL)aState
{
    _autoSaveChanges = aState;
}

// @TODO update methods to use _executeStoreFetchRequest
- (CPManagedObject) updateObject:(CPManagedObject) aObject mergeChanges:(BOOL) mergeChanges
{
    return nil;
}

- (CPManagedObject) updateObjectWithID:(CPManagedObjectID) aObjectID mergeChanges:(BOOL) mergeChanges
{
    // Try the local registry first
    var existing = [self objectRegisteredForID:aObjectID];
    if (existing !== nil)
        return existing;

    // Fire a fault fetch via the store if the object ID has a global ID
    if ([aObjectID validatedGlobalID])
        return [self _fetchObjectWithID:aObjectID];

    return nil;
}

// @TODO fetchLimit is missing
- (CPArray) executeFetchRequest:(CPFetchRequest)aFetchRequest
                          error:(@ref)anError
{
    var result = nil;

    var localSetResult = [self _executeLocalFetchRequest:aFetchRequest];
    var remoteSetResult = [self _executeStoreFetchRequest:aFetchRequest];
    [remoteSetResult unionSet:localSetResult];

    var unsortedResult = [remoteSetResult allObjects];

    if([aFetchRequest sortDescriptors] != nil)
        result = [unsortedResult sortedArrayUsingDescriptors:[aFetchRequest sortDescriptors]];
    else
        result = unsortedResult;

    if([aFetchRequest fetchLimit] > 0 && [result count] > [aFetchRequest fetchLimit])
        return [result subarrayWithRange:CPMakeRange(0,[aFetchRequest fetchLimit])];

    return result;
}

/**
    Execute a fetch on the store only.

    The store must implement executeFetchRequest:inManagedObjectContext:error.

    Transparent mode:
        Data received from the store is not added to the managed object
        context.
*/
- (CPArray) executeStoreFetchRequest:(CPFetchRequest)aFetchRequest
{
    var error = nil;
    var resultArray = [[CPMutableArray alloc] init];
    var resultSet = [[self store] executeFetchRequest:aFetchRequest
                              inManagedObjectContext:self
                                               error:error];
    if ([aFetchRequest error])
    {
        return nil;
    }
    else if (   resultSet != nil
             && [resultSet count] > 0
            )
    {
        var transparent = [aFetchRequest transparentFetch];
        var fetchEntity = [aFetchRequest entity];
        var objectEnum = [resultSet objectEnumerator];
        var objectFromResponse;
        while ((objectFromResponse = [objectEnum nextObject]))
        {
            if (transparent)
            {
                if (fetchEntity === nil || [[objectFromResponse entity] isEqual:fetchEntity])
                    [resultArray addObject:objectFromResponse];
            }
            else
            {
                var registered = [self _registerFetchedObject:objectFromResponse];
                if (fetchEntity === nil || [[registered entity] isEqual:fetchEntity])
                    [resultArray addObject:registered];
            }
        }
    }
    return resultArray;
}

/*!
    Async counterpart of executeStoreFetchRequest:.

    If the store implements executeFetchRequestAsync:inManagedObjectContext:completionHandler:,
    uses that so the browser UI is not blocked.  Otherwise falls back to the
    synchronous store fetch path (suitable for in-memory or other fast stores).

    Fires CPManagedObjectContextDidLoadObjectsNotification when complete.

    @param request  The fetch request.
    @param handler  JS function(results CPArray, error CPError).
                    results is a CPArray (empty on error).
                    Pass nil if you only need the notification.
*/
- (void)executeStoreFetchRequestAsync:(CPFetchRequest)aFetchRequest
                    completionHandler:(Function)handler
{
    var self_ = self;

    if ([[self store] respondsToSelector:@selector(executeFetchRequestAsync:inManagedObjectContext:completionHandler:)])
    {
        [[self store] executeFetchRequestAsync:aFetchRequest
                        inManagedObjectContext:self
                             completionHandler:function(resultSet, error) {
            var resultArray = [[CPMutableArray alloc] init];
            if (resultSet !== nil && error === nil)
            {
                var transparent = [aFetchRequest transparentFetch],
                    fetchEntity = [aFetchRequest entity],
                    objectEnum  = [resultSet objectEnumerator],
                    obj;
                while ((obj = [objectEnum nextObject]))
                {
                    if (transparent)
                    {
                        if (fetchEntity === nil || [[obj entity] isEqual:fetchEntity])
                            [resultArray addObject:obj];
                    }
                    else
                    {
                        var registered = [self_ _registerFetchedObject:obj];
                        if (fetchEntity === nil || [[registered entity] isEqual:fetchEntity])
                            [resultArray addObject:registered];
                    }
                }
            }
            [[CPNotificationCenter defaultCenter]
                postNotificationName:CPManagedObjectContextDidLoadObjectsNotification
                              object:self_
                            userInfo:nil];
            if (handler) handler(resultArray, error);
        }];
    }
    else
    {
        // Sync fallback for stores that don't implement the async API
        var resultArray = [self executeStoreFetchRequest:aFetchRequest];
        [[CPNotificationCenter defaultCenter]
            postNotificationName:CPManagedObjectContextDidLoadObjectsNotification
                          object:self
                        userInfo:nil];
        if (handler) handler(resultArray || [], nil);
    }
}

/*!
    Schedule a block to run asynchronously on the context's queue.

    Mirrors NSManagedObjectContext -perform:.

    In the single-threaded browser environment the block is deferred to the
    next run-loop turn via a zero-delay timer so that the calling stack has
    fully unwound before the block executes.

    @param block  A zero-argument JS function to execute.
*/
- (void)perform:(Function)block
{
    if (block)
        window.setTimeout(block, 0);
}

/*!
    Execute a block synchronously on the context's queue.

    Mirrors NSManagedObjectContext -performAndWait:.

    In the single-threaded browser environment this is equivalent to calling
    the block immediately.

    @param block  A zero-argument JS function to execute.
*/
- (void)performAndWait:(Function)block
{
    if (block)
        block();
}

/*!
    Execute a persistent-store request.

    Mirrors NSManagedObjectContext -executeRequest:error:.

    Supported request types:
    - CPAsynchronousFetchRequestType: fires an async fetch and delivers the
      result to the request's completionBlock.  Returns an empty
      CPAsynchronousFetchResult immediately (finalResult will be nil until
      the completion block is called).
    - CPFetchRequestType: performs a synchronous fetch and returns a CPArray.
    - CPSaveRequestType: performs a synchronous save and returns @(YES/NO).

    @param request  A CPPersistentStoreRequest (or subclass) instance.
    @param error    On return, if an error occurred this ref is set to a
                    CPError describing the problem.
    @return The result of the operation, or nil on failure.
*/
- (id)executeRequest:(CPPersistentStoreRequest)request
               error:(@ref)error
{
    var type = [request requestType];

    if (type === CPAsynchronousFetchRequestType)
    {
        var asyncRequest = request,
            innerFetch   = [asyncRequest fetchRequest],
            result       = [[CPAsynchronousFetchResult alloc] init];

        [result setFetchRequest:asyncRequest];
        [result setFinalResult:nil];

        [self executeStoreFetchRequestAsync:innerFetch
                          completionHandler:function(resultArray, fetchError) {
            [result setFinalResult:(fetchError === nil ? resultArray : nil)];

            var completionBlock = [asyncRequest completionBlock];
            if (completionBlock)
                completionBlock(result);
        }];

        return result;
    }
    else if (type === CPFetchRequestType)
    {
        return [self executeFetchRequest:request error:error];
    }
    else if (type === CPSaveRequestType)
    {
        var saveError = nil;
        var success = [self saveChanges:@ref(saveError)];
        if (error) @deref(error) = saveError;
        return success;
    }

    CPLog.warn("CPManagedObjectContext -executeRequest:error: unrecognised requestType " + type);
    return nil;
}

- (CPSet) _executeLocalFetchRequest:(CPFetchRequest) aFetchRequest
{
    var resultArray = [[CPMutableArray alloc] init];
    var searchPredicate = nil;
    var entityPredicate = [CPPredicate predicateWithFormat:@"%K like %@", @"entity.name", [[aFetchRequest entity] name]];

    if([aFetchRequest predicate] == nil)
    {
        searchPredicate = entityPredicate;
    }
    else
    {
        searchPredicate = [CPCompoundPredicate andPredicateWithSubpredicates:[entityPredicate, [aFetchRequest predicate]]];
    }

    var unsortedResult = [[_registeredObjects allObjects] filteredArrayUsingPredicate:searchPredicate];

    if([aFetchRequest sortDescriptors] != nil)
        resultArray = [unsortedResult sortedArrayUsingDescriptors:[aFetchRequest sortDescriptors]];
    else
        resultArray = unsortedResult;

    if([aFetchRequest fetchLimit] > 0 && [resultArray count] > [aFetchRequest fetchLimit])
        return [CPSet setWithArray:[resultArray subarrayWithRange:CPMakeRange(0,[aFetchRequest fetchLimit])]];

    return [CPSet setWithArray:resultArray];
}


- (CPSet) _executeStoreFetchRequest:(CPFetchRequest)aFetchRequest
{
    var error;
    var resultArray = [[CPMutableArray alloc] init];
    if ([[self store] respondsToSelector:@selector(executeFetchRequest:inManagedObjectContext:error:)])
    {
        var resultSet = [[self store] executeFetchRequest:aFetchRequest
                                  inManagedObjectContext:self
                                                   error:error];
        if (resultSet != nil && [resultSet count] > 0 && error == nil)
        {
            var fetchEntity = [aFetchRequest entity];
            var objectEnum = [resultSet objectEnumerator];
            var objectFromResponse;
            while((objectFromResponse = [objectEnum nextObject]))
            {
                var registered = [self _registerFetchedObject:objectFromResponse];
                if (fetchEntity === nil || [[registered entity] isEqual:fetchEntity])
                    [resultArray addObject:registered];
            }
        }
    }
    return [CPSet setWithArray:resultArray];
}


- (void) reset
{
    var result = YES;
    [_registeredObjects makeObjectsPerformSelector:@selector(_resetChangedDataForProperties)];
    [_updatedObjectIDs removeAllObjects];
    [_insertedObjectIDs removeAllObjects];
    [_deletedObjects removeAllObjects];
    return result;
}


- (void) rollback
{
}

- (BOOL)saveAll
{
    var error = nil;
    var result = [self reset];
    [[self store] saveAll:[self registeredObjects] error:error];
    [[CPNotificationCenter defaultCenter]
                        postNotificationName: CPManagedObjectContextDidSaveAllObjectsNotification
                                      object: self
                                    userInfo: nil];
    return result;
}


- (BOOL) loadAll
{
    var error = nil;
    var result = YES;
    var resultSet = nil;
    var propertiesDictionary = [[CPMutableDictionary alloc] init];

    var allEntities = [[[self model] entities] objectEnumerator];
    var aEntity;

    while((aEntity = [allEntities nextObject]))
    {
        var propertiesFromEntity = [CPSet setWithArray: [aEntity propertyNames]];
        [propertiesDictionary setObject:propertiesFromEntity forKey:[aEntity name]];
    }
    resultSet = [[self store] loadAll:propertiesDictionary inManagedObjectContext:self error:error];
    if(resultSet != nil && [resultSet count] > 0 && error == nil)
    {
        var resultEnumerator = [[resultSet allObjects] objectEnumerator];
        var objectFromResponse;

        while(objectFromResponse = [resultEnumerator nextObject])
        {
            [self _registerFetchedObject:objectFromResponse];
        }
    }
    [[CPNotificationCenter defaultCenter] postNotificationName:CPManagedObjectContextDidLoadObjectsNotification
                                                        object:self
                                                      userInfo:nil];
    return result;
}


/**
    Update, insert or delete objects depending on their current state.

    Uses saveAll if the store doesn't support selector
    saveObjectsUpdated:inserted:deleted:inManagedObjectContext:error:

    TODO: better error handling

    @param error should be nil or a @ref, will receive a CPError object on error.
*/
- (BOOL)saveChanges:(@ref)error
{
    if (![self hasChanges])
    {
        // Even with no store-level changes there may be FRC pending changes
        // (e.g. deletes of objects without a persistent globalID).  Always
        // post DidSave so observers such as CPFetchedResultsController have a
        // chance to flush those pending changes.
        [[CPNotificationCenter defaultCenter]
            postNotificationName: CPManagedObjectContextDidSaveNotification
                          object: self
                        userInfo: nil];
        return YES;
    }
    var result = NO;
    if ([[self store] respondsToSelector:@selector(
                          saveObjectsUpdated:inserted:deleted:inManagedObjectContext:error:)]
       )
    {
        var saveError = nil,
            updatedObjects = [self updatedObjects],
            insertedObjects = [self insertedObjects],
            deletedObjects = [self deletedObjects];
        var modifiedObjects = [self _saveObjectsUpdated:updatedObjects
                                               inserted:insertedObjects
                                                deleted:deletedObjects
                                                  error:@ref(saveError)];
        if (saveError == nil)
        {
            result = [self reset];
        }
        else if (error && @deref(error) == nil)
        {
            // return the error to the caller
            @deref(error) = saveError;
        }
        [[CPNotificationCenter defaultCenter]
            postNotificationName: CPManagedObjectContextDidSaveNotification
                          object: self
                        userInfo: nil];
        [[CPNotificationCenter defaultCenter]
                            postNotificationName: CPManagedObjectContextDidSaveChangedObjectsNotification
                                          object: self
                                        userInfo: nil];
    }
    else
    {
        result = [self saveAll];
    }
    return result;
}

/*!
    Async counterpart of saveChanges:.

    If the store implements
      saveObjectsUpdated:inserted:deleted:inManagedObjectContext:completionHandler:
    uses that so the browser UI is not blocked.  Otherwise falls back to the
    synchronous save path.

    Fires CPManagedObjectContextDidSaveNotification and
    CPManagedObjectContextDidSaveChangedObjectsNotification on success.

    @param handler  JS function(success BOOL, error CPError).
                    Pass nil if you only need the notification.
*/
- (void)saveChangesWithCompletionHandler:(Function)handler
{
    if (![self hasChanges])
    {
        if (handler) handler(YES, nil);
        return;
    }

    if (![[self store] respondsToSelector:@selector(saveObjectsUpdated:inserted:deleted:inManagedObjectContext:completionHandler:)])
    {
        // Sync fallback for stores that don't implement the async API
        var syncError = nil;
        var result = [self saveChanges:@ref(syncError)];
        if (handler) handler(result, syncError);
        return;
    }

    var self_            = self,
        updatedObjects   = [self updatedObjects],
        insertedObjects  = [self insertedObjects],
        deletedObjects   = [self deletedObjects],
        allSavingObjects = [[CPMutableSet alloc] init];

    [allSavingObjects unionSet:updatedObjects];
    [allSavingObjects unionSet:insertedObjects];
    [allSavingObjects unionSet:deletedObjects];

    var validationError = nil;
    if (![self _validateUpdatedObject:updatedObjects
                      insertedObjects:insertedObjects
                                error:@ref(validationError)])
    {
        if (handler) handler(NO, validationError);
        return;
    }

    [[allSavingObjects allObjects] makeObjectsPerformSelector:@selector(willSave)];

    [[self store] saveObjectsUpdated:updatedObjects
                            inserted:insertedObjects
                             deleted:deletedObjects
              inManagedObjectContext:self
                   completionHandler:function(resultSet, saveError) {
        if (saveError !== nil)
        {
            if (handler) handler(NO, saveError);
            return;
        }

        // Apply ID remapping from server
        if (resultSet && [resultSet count] > 0)
        {
            var objectsEnum = [resultSet objectEnumerator],
                obj;
            while ((obj = [objectsEnum nextObject]))
            {
                var registeredObject = [self_ objectRegisteredForID:[obj objectID]];
                if (registeredObject !== nil)
                {
                    [[registeredObject objectID] setGlobalID:[[obj objectID] globalID]];
                    [[registeredObject objectID] setIsTemporary:[[obj objectID] isTemporary]];
                }
            }
        }

        [[allSavingObjects allObjects] makeObjectsPerformSelector:@selector(didSave)];
        [self_ reset];

        [[CPNotificationCenter defaultCenter]
            postNotificationName:CPManagedObjectContextDidSaveNotification
                          object:self_
                        userInfo:nil];
        [[CPNotificationCenter defaultCenter]
            postNotificationName:CPManagedObjectContextDidSaveChangedObjectsNotification
                          object:self_
                        userInfo:nil];

        if (handler) handler(YES, nil);
    }];
}


/*!
    Save a single object from the context.

    Whatever needs to be done with the object will be done. This can be
    insert/update or delete.
*/
- (BOOL)saveObject:(CPManagedObject)aObject
             error:(@ref)error
{
    CPLog.debug(  "context:" + self
                + " saveObject: reg " + [_registeredObjects count]
                + ", upd "  + [_updatedObjectIDs count]
                + ", ins " + [_insertedObjectIDs count]
                + ", del "  + [_deletedObjects count]);
    var result = NO,
        saveError = nil,
        updatedObjects = [CPMutableSet new],
        insertedObjects = [CPMutableSet new],
        deletedObjects = [CPMutableSet new],
        obj;
    obj = [self _insertedObjectWithID:[aObject objectID]];
    if (obj) {
        [insertedObjects addObject:obj];
    }
    obj = [self _updatedObjectWithID:[aObject objectID]];
    if (obj) {
        [updatedObjects addObject:obj];
    }
    obj = [self _deletedObjectWithID:[aObject objectID]];
    if (obj) {
        [deletedObjects addObject:obj];
    }
    var modifiedObjects = [self _saveObjectsUpdated:updatedObjects
                                           inserted:insertedObjects
                                            deleted:deletedObjects
                                              error:@ref(saveError)];

    if (saveError == nil)
    {
        // update the state of the object in the context
        [_updatedObjectIDs removeObject:[aObject objectID]];
        [_insertedObjectIDs removeObject:[aObject objectID]];
        [_deletedObjects removeObject:[aObject objectID]];
        result = YES;
    }
    else if (error && @deref(error) == nil)
    {
        // return the error to the caller
        @deref(error) = saveError;
    }
    return result;
}


-(CPSet)_saveObjectsUpdated:(CPSet)updatedObjects
                   inserted:(CPSet)insertedObjects
                    deleted:(CPSet)deletedObjects
                      error:(@ref)error
{
    var saveError = nil;
    if (![self _validateUpdatedObject:updatedObjects
                      insertedObjects:insertedObjects
                                error:@ref(saveError)])
    {
        if (error && @deref(error) == nil)
            @deref(error) = saveError;
        return nil;
    }

    // Notify all objects that are about to be saved
    var allSavingObjects = [[CPMutableSet alloc] init];
    [allSavingObjects unionSet:updatedObjects];
    [allSavingObjects unionSet:insertedObjects];
    [allSavingObjects unionSet:deletedObjects];
    [[allSavingObjects allObjects] makeObjectsPerformSelector:@selector(willSave)];

    var resultSet = [[self store] saveObjectsUpdated:updatedObjects
                                            inserted:insertedObjects
                                             deleted:deletedObjects
                              inManagedObjectContext:self
                                               error:@ref(saveError)];
    if (resultSet && [resultSet count] > 0)
    {
        var objectsEnum = [resultSet objectEnumerator];
        var objectFromResponse;
        while((objectFromResponse = [objectsEnum nextObject]))
        {
            var registeredObject = [self objectRegisteredForID:[objectFromResponse objectID]];
            if (registeredObject != nil)
            {
                [[registeredObject objectID] setGlobalID: [[objectFromResponse objectID] globalID]];
                [[registeredObject objectID] setIsTemporary: [[objectFromResponse objectID] isTemporary]];
            }
        }
    }
    if (saveError != nil && error && @deref(error) == nil)
    {
        // return the error to the caller
        @deref(error) = saveError;
    }
    else
    {
        // Save succeeded — notify all participating objects
        [[allSavingObjects allObjects] makeObjectsPerformSelector:@selector(didSave)];

        // Keep the coordinator's row cache consistent with the committed state.
        var coordinator = [self storeCoordinator];
        if (coordinator !== nil)
        {
            // Evict deleted objects so stale data is never served from the cache.
            var de = [deletedObjects objectEnumerator],
                delObj;
            while ((delObj = [de nextObject]))
            {
                var delGlobalID = [[delObj objectID] globalID];
                if (delGlobalID !== nil)
                    [coordinator invalidateRowDataForGlobalID:delGlobalID];
            }

            // Refresh cache entries for objects that were saved with new data
            // (both updated and newly inserted objects whose global ID is now known).
            var ue = [[CPMutableSet alloc] init];
            [ue unionSet:updatedObjects];
            [ue unionSet:insertedObjects];
            var ueEnum = [ue objectEnumerator],
                saveObj;
            while ((saveObj = [ueEnum nextObject]))
            {
                var savedGlobalID = [[saveObj objectID] globalID];
                if (savedGlobalID !== nil)
                    [coordinator cacheRowData:[saveObj data] forGlobalID:savedGlobalID];
            }
        }
    }
    return resultSet;
}

- (BOOL) _validateUpdatedObject:(CPSet)updated
                insertedObjects:(CPSet)inserted
                          error:(@ref)error
{
    var unionSet = [[CPMutableSet alloc] init];
    [unionSet unionSet:updated];
    [unionSet unionSet:inserted];

    var enumerator = [unionSet objectEnumerator];
    var aObject;
    var failedObjects = [[CPMutableArray alloc] init];

    while((aObject = [enumerator nextObject]))
    {
        if(![aObject validateForUpdate])
            [failedObjects addObject:aObject];
    }

    if ([failedObjects count] > 0)
    {
        if (error && @deref(error) == nil)
        {
            var ui = [[CPMutableDictionary alloc] init];
            [ui setObject:@"One or more objects failed validation and the save was aborted."
                   forKey:CPLocalizedDescriptionKey];
            [ui setObject:failedObjects forKey:CPDetailedErrorsKey];
            @deref(error) = [CPError errorWithDomain:CPCoreDataErrorDomain
                                               code:CPValidationMultipleErrorsError
                                           userInfo:ui];
        }
        return NO;
    }
    return YES;
}

/*
 *    Check if the context has changes
 */
- (BOOL) hasChanges
{
    CPLog.debug(  "context:" + self
                + " reg " + [_registeredObjects count]
                + ", upd "  + [_updatedObjectIDs count]
                + ", ins " + [_insertedObjectIDs count]
                + ", del "  + [_deletedObjects count]);
    return    ([_updatedObjectIDs count] > 0)
           || ([_insertedObjectIDs count] > 0)
           || ([_deletedObjects count] > 0);
}

/*
 *    request registered,inserted, updated and deleted objects by object id
 */
- (CPManagedObject) objectRegisteredForID: (CPManagedObjectID) aObjectID
{
    if(aObjectID != nil)
    {
        var localID = nil;
        if ([aObjectID validatedLocalID])
        {
            localID = [aObjectID localID];
        }
        var globalID = nil;
        if ([aObjectID validatedGlobalID])
        {
            globalID = [aObjectID globalID];
        }
        if (localID || globalID)
        {
            var e = [_registeredObjects objectEnumerator];
            var oid = nil;
            var object = nil;
            while (object = [e nextObject])
            {
                oid = [object objectID];
                if (   (localID && [oid isEqualToLocalID:aObjectID] == YES)
                    || (globalID && [oid isEqualToGlobalID:aObjectID] == YES)
                   )
                {
                    return object;
                }
            }
        }
    }
    return object;
}

/*!
    Returns the object for the given object ID.

    If the object is already registered in the context it is returned directly.
    Otherwise a fault object (isFault == YES) is created, registered, and
    returned.  The fault will be fully populated the first time any of its
    properties are accessed.

    This mirrors NSManagedObjectContext -objectWithID:.
*/
- (CPManagedObject) objectWithID:(CPManagedObjectID)aObjectID
{
    if (aObjectID === nil || aObjectID === null)
        return nil;

    var existing = [self objectRegisteredForID:aObjectID];
    if (existing !== nil)
    {
        // If the registered object is still a fault but row-cache data is
        // available, fulfill it in-place right now so callers get a live object.
        if ([existing isFault] && [aObjectID validatedGlobalID])
        {
            var coordinator = [self storeCoordinator];
            var cachedData = (coordinator !== nil)
                                ? [coordinator cachedRowDataForGlobalID:[aObjectID globalID]]
                                : nil;
            if (cachedData !== nil)
            {
                [existing _setData:[cachedData mutableCopy]];
                [existing setFault:NO];
                [existing awakeFromFetch];
            }
        }
        return existing;
    }

    // Check the coordinator row cache before creating a fault.
    // If data is present we can return a fully-resolved object immediately,
    // matching Apple CoreData's behaviour for objectWithID: when the row is
    // already known to the coordinator.
    if ([aObjectID validatedGlobalID])
    {
        var coordinator = [self storeCoordinator];
        var cachedData = (coordinator !== nil)
                            ? [coordinator cachedRowDataForGlobalID:[aObjectID globalID]]
                            : nil;
        if (cachedData !== nil)
        {
            var entity = [aObjectID entity];
            if (entity !== nil)
            {
                var localEntity = [[self model] entityWithName:[entity name]];
                if (localEntity !== nil)
                {
                    var cachedObj = [localEntity createObject];
                    [cachedObj setObjectID:aObjectID];
                    [cachedObj _setData:[cachedData mutableCopy]];
                    [cachedObj setFault:NO];
                    if (![aObjectID validatedLocalID])
                        [aObjectID setLocalID:[CPManagedObjectID createLocalID]];
                    return [self _registerFetchedObject:cachedObj];
                }
            }
        }
    }

    // Create a fault: a registered stub whose data has not yet been loaded.
    var entity = [aObjectID entity];
    if (entity === nil)
        return nil;

    var faultObject = [entity createObject];
    [faultObject setObjectID:aObjectID];
    [faultObject setFault:YES];
    if (![aObjectID validatedLocalID])
        [aObjectID setLocalID:[CPManagedObjectID createLocalID]];
    [_registeredObjects addObject:faultObject];
    [faultObject _applyToContext:self];
    return faultObject;
}


- (CPManagedObject) _fetchObjectWithID:(CPManagedObjectID) aObjectID
{
    var objectFromResponse = nil;
    if(aObjectID != nil)
    {
        if([self _deletedObjectWithID:aObjectID] == nil && [aObjectID validatedGlobalID])
        {
            // --- Check coordinator row cache first ---
            // Apple's CoreData keeps a shared row-cache at the coordinator level
            // so that faults can be resolved from data already held in memory by
            // any context sharing the same coordinator, without a network round-trip.
            var coordinator = [self storeCoordinator];
            var cachedData = (coordinator !== nil)
                                ? [coordinator cachedRowDataForGlobalID:[aObjectID globalID]]
                                : nil;
            if (cachedData !== nil)
            {
                // Hydrate a new managed object from the cached attribute snapshot.
                var localEntity = [[self model] entityWithName:[[aObjectID entity] name]];
                if (localEntity !== nil)
                {
                    var cachedObj = [localEntity createObject];
                    [cachedObj setObjectID:aObjectID];
                    [cachedObj _setData:[cachedData mutableCopy]];
                    [cachedObj setFault:NO];
                    return [self _registerFetchedObject:cachedObj];
                }
            }

            // --- Row cache miss: fall back to network fetch ---
            var setWithObjIDs = [[CPMutableSet alloc] init];
            [setWithObjIDs addObject:aObjectID];

            var newPropertiesDict = [[CPMutableDictionary alloc] init];
            var localEntity = [[self model] entityWithName:[[aObjectID entity] name]];
            var localProperties = [CPSet setWithArray: [localEntity propertyNames]];
            [newPropertiesDict setObject:localProperties forKey:[[aObjectID entity] name]];
            var error = nil;
            var resultSet = [[self store] fetchObjectsWithID:setWithObjIDs
                                             fetchProperties:newPropertiesDict
                                                       error:error];
            if(resultSet != nil && [resultSet count] > 0 && error == nil)
            {
                var objectEnum = [resultSet objectEnumerator];
                var objectFromResponse;

                while((objectFromResponse = [objectEnum nextObject]))
                {
                    [[objectFromResponse objectID] setLocalID: [aObjectID localID]];
                    objectFromResponse = [self _registerFetchedObject:objectFromResponse];
                    aObjectID = [objectFromResponse objectID];
                    return objectFromResponse;
                }
            }
        }
    }

    return objectFromResponse;
}


- (CPManagedObject) _insertedObjectWithID: (CPManagedObjectID) aObjectID
{
    var e;
    var object;

    e = [_insertedObjectIDs objectEnumerator];
    while ((object = [e nextObject]) != nil)
    {
        if ([object isEqualToLocalID: aObjectID] == YES)
        {
            return [self objectRegisteredForID: aObjectID];
        }
    }

    return nil;
}

- (CPManagedObject) _updatedObjectWithID: (CPManagedObjectID) aObjectID
{
    var e;
    var object;

    e = [_updatedObjectIDs objectEnumerator];
    while ((object = [e nextObject]) != nil)
    {
        if ([object isEqualToLocalID: aObjectID] == YES)
        {
            return [self objectRegisteredForID: aObjectID];
        }
    }

    return nil;
}


- (CPManagedObject) _deletedObjectWithID: (CPManagedObjectID) aObjectID
{
    var e;
    var object;

    e = [_deletedObjects objectEnumerator];
    while ((object = [e nextObject]) != nil)
    {
        if ([[object objectID] isEqualToLocalID: aObjectID] == YES)
        {
            return object;
        }
        else if ([[object objectID] isEqualToGlobalID: aObjectID] == YES)
        {
            return object;
        }
    }

    return nil;
}

/*
 *    Create new object from entity
 */
- (CPManagedObject) insertNewObjectForEntityForName:(CPString) entity
{
    var result_object;
    var tmpentity = [[self model] entityWithName:entity];
    if(tmpentity != nil)
    {
        result_object = [tmpentity createObject];
        if(result_object != nil)
        {
            [self insertObject:result_object];
        }
    }
    return result_object
}

/*
 *    Insert and delete registered objects
 */
- (void) insertObject: (CPManagedObject) aObject
{
    if([aObject objectID] == nil)
    {
        [aObject setObjectID:[[CPManagedObjectID alloc] initWithEntity:[aObject entity] globalID:nil isTemporary:YES]];
    }

    var deletedObject = [self _deletedObjectWithID: [aObject objectID]];
    if (deletedObject != nil)
    {
        [self _registerObject: aObject];
        [_deletedObjects removeObject: aObject];
        [_insertedObjectIDs addObject: [aObject objectID]];
    }
    else
    {
        // isNew must be checked BEFORE _registerObject: adds the object to
        // _registeredObjects; checking after would always yield NO.
        var isNew = ([self objectRegisteredForID:[aObject objectID]] == nil);
        [self _registerObject: aObject];
        [_insertedObjectIDs addObject: [aObject objectID]];
        if (isNew)
            [aObject awakeFromInsert];
    }

    [aObject _applyToContext: self];

    var userInfo = [CPDictionary dictionaryWithObject: [CPSet setWithObject: aObject]
                                               forKey: CPDInsertedObjectsKey];
    [[CPNotificationCenter defaultCenter]
        postNotificationName: CPManagedObjectContextObjectsDidChangeNotification
                      object: self
                    userInfo: userInfo];
}


- (void) deleteObject: (CPManagedObject) aObject
{
    [self _deleteObject:aObject saveAfterDeletion:YES];
}


- (void) _deleteObject: (CPManagedObject) aObject saveAfterDeletion:(BOOL) saveAfterDeletion
{
    if ([self objectRegisteredForID: [aObject objectID]] != nil)
    {
        [aObject prepareForDeletion];
        if ([aObject _solveRelationshipsWithDeleteRules] == YES)
        {
            var needToSave = NO;
            //if delete rule is Deny the result is false
            [aObject setDeleted: YES];

            if([[aObject objectID] validatedGlobalID])
            {
                [_deletedObjects addObject: aObject];
                needToSave = YES;
            }

            [_insertedObjectIDs removeObject: [aObject objectID]];
            [self _unregisterObject: aObject];

            var userInfo = [CPDictionary dictionaryWithObject: [CPSet setWithObject: aObject]
                                                       forKey: CPDDeletedObjectsKey];

            [[CPNotificationCenter defaultCenter]
                        postNotificationName: CPManagedObjectContextObjectsDidChangeNotification
                                      object: self
                                    userInfo: userInfo];

            if(saveAfterDeletion && [self autoSaveChanges] && needToSave)
                [self saveChanges:nil];
        }
    }
    else
    {
        [aObject setDeleted: YES];
        [_deletedObjects addObject: aObject];
    }
}

- (void) deleteObjectWithID: (CPManagedObjectID) aObjectId
{
    var aObject = [self objectRegisteredForID: aObjectId];
    if (aObject != nil)
    {
        [self deleteObject:aObject];
    }
}

/*
 *    Object changes notifications
 */
- (void)_objectDidChange:(CPManagedObject)aObject
{
    if ([self objectRegisteredForID: [aObject objectID]] != nil)
    {
        if ([self _insertedObjectWithID: [aObject objectID]] == nil)
        {
            [[self objectRegisteredForID: [aObject objectID]] setUpdated:YES];
            [_updatedObjectIDs addObject: [aObject objectID]];
        }

        var userInfo = [CPDictionary dictionaryWithObject: [CPSet setWithObject: aObject]
                                                   forKey: CPDUpdatedObjectsKey];
        [[CPNotificationCenter defaultCenter]
            postNotificationName: CPManagedObjectContextObjectsDidChangeNotification
                          object: self
                        userInfo: userInfo];
        CPLog.debug(  "context:" + self
                    + " Object did change: reg " + [_registeredObjects count]
                    + ", upd "  + [_updatedObjectIDs count]
                    + ", ins " + [_insertedObjectIDs count]
                    + ", del "  + [_deletedObjects count]);
    }
}


/*
 *    Register and Unregister object

    If aObject is already in the context only a CPManagedObjectContextObjectsDidChangeNotification
    is sent.
 */
- (CPManagedObject) _registerObject: (CPManagedObject) aObject
{
    var regObject = [self objectRegisteredForID:[aObject objectID]];
    if(regObject != nil)
    {
        if (regObject !== aObject)
        {
            //update regobject with object
            [regObject _updateWithObject: aObject];
            [regObject _applyToContext:self];
            // The incoming object has its data; the registered object (which may
            // have been a fault) is now fully populated.
            [regObject setFault:NO];
            aObject = regObject;
        }
        var userInfo = [CPDictionary dictionaryWithObject:[CPSet setWithObject:aObject]
                                                   forKey:CPDUpdatedObjectsKey];
        [[CPNotificationCenter defaultCenter]
                        postNotificationName: CPManagedObjectContextObjectsDidChangeNotification
                                      object: self
                                    userInfo: userInfo];
    }
    else
    {
        if (![[aObject objectID] validatedLocalID])
        {
            [aObject setEntity:[[aObject objectID] entity]];
            [[aObject objectID] setLocalID:[CPManagedObjectID createLocalID]];
        }
        [_registeredObjects addObject: aObject];
        [aObject _applyToContext:self];
    }
    return aObject;
}

/*!
    Register an object that arrived from a persistent store fetch.

    This method calls _registerObject: and then fires awakeFromFetch on the
    object if it was not already present in the context.  Use this from all
    code paths where objects are received from the store rather than created
    locally (loadAll:, executeStoreFetchRequest:, _fetchObjectWithID:).
*/
- (CPManagedObject) _registerFetchedObject: (CPManagedObject) aObject
{
    var wasRegistered = ([self objectRegisteredForID:[aObject objectID]] != nil);
    var registered = [self _registerObject:aObject];
    if (!wasRegistered)
        [registered awakeFromFetch];
    return registered;
}


- (void) _unregisterObject: (CPManagedObject) object
{
    if ([_registeredObjects containsObject: object] == YES)
    {
        [_registeredObjects removeObject: object];
    }
}


/*
 *    All inserted object ids
 */
- (CPSet) insertedObjectIDs
{
    return _insertedObjectIDs;
}


/*
 *    All updated object ids
 */
- (CPSet) updatedObjectIDs
{
    return _updatedObjectIDs;
}


/*
 *    All inserted objects
 */
- (CPSet) insertedObjects
{
    var result = [[CPMutableSet alloc] init];

    var objectsEnum = [_insertedObjectIDs objectEnumerator];
    var objID;
    while((objID = [objectsEnum nextObject]))
    {
        [result addObject:[self objectRegisteredForID:objID]];
    }

    return result;
}


/*
 *    All updated objects
 */
- (CPSet) updatedObjects
{
    var result = [[CPMutableSet alloc] init];

    var objectsEnum = [_updatedObjectIDs objectEnumerator];
    var objID;
    while((objID = [objectsEnum nextObject]))
    {
        [result addObject:[self objectRegisteredForID:objID]];
    }
    return result;
}



/*
 *    All deleted objects
 */
- (CPSet) deletedObjects
{
    return _deletedObjects;
}


/*
 *    All registrated object ids
 */
- (CPSet) registeredObjectIDs
{
    var result = [[CPMutableSet alloc] init];

    var objectsEnum = [_registeredObjects objectEnumerator];
    var obj;
    while((obj = [objectsEnum objectEnumerator]))
    {
        [result addObject:[obj objectID]];
    }

    return result;
}

/*
 * All registrated objects
 */
- (CPSet) registeredObjects
{
 return _registeredObjects
}



@end
