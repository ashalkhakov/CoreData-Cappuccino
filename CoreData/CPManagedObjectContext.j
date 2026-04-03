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

/*

***** HEADER *****
@public
- (CPArray) executeFetchRequest:(CPFetchRequest)aFetchRequest;
- (CPArray) executeStoreFetchRequest:(CPFetchRequest)aFetchRequest;

@private
- (CPSet) _executeLocalFetchRequest:(CPFetchRequest) aFetchRequest;
- (CPSet) _executeStoreFetchRequest:(CPFetchRequest) aFetchRequest;

- (CPManagedObject) _insertedObjectWithID:(CPManagedObjectID) aObjectID;
- (CPManagedObject) _updatedObjectWithID:(CPManagedObjectID) aObjectID;
- (CPManagedObject) _deletedObjectWithID:(CPManagedObjectID) aObjectID;
- (BOOL) reset;
- (void) _objectDidChange:(CPManagedObject) aObject;
- (CPManagedObject) _registerObject:(CPManagedObject) object;
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
        var objectEnum = [resultSet objectEnumerator];
        var objectFromResponse;
        while ((objectFromResponse = [objectEnum nextObject]))
        {
            if (transparent)
            {
                [resultArray addObject:objectFromResponse];
            }
            else
            {
                [resultArray addObject:[self _registerObject:objectFromResponse]];
            }
        }
    }
    return resultArray;
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
            var objectEnum = [resultSet objectEnumerator];
            var objectFromResponse;
            while((objectFromResponse = [objectEnum nextObject]))
            {
                [resultArray addObject:[self _registerObject:objectFromResponse]];
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
            [self _registerObject:objectFromResponse];
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
        return YES
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
    [self _validateUpdatedObject:updatedObjects
                 insertedObjects:insertedObjects];
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
    return resultSet;
}

- (void) _validateUpdatedObject:(CPSet)updated
                insertedObjects:(CPSet)inserted
{
    var unionSet = [[CPMutableSet alloc] init];
    [unionSet unionSet:updated];
    [unionSet unionSet:inserted];

    var enumerator = [unionSet objectEnumerator];
    var aObject;

    while((aObject = [enumerator nextObject]))
    {
        if(![aObject validateForUpdate])
        {
            [updated removeObject:aObject];
            [inserted removeObject:aObject];

            var objectEnum = [unionSet objectEnumerator];
            var object;
            while((object = [objectEnum nextObject]))
            {
                if([object _containsObject:[aObject objectID]])
                {
                    [updated removeObject:object];
                    [inserted removeObject:object];
                }
            }
        }
    }
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


- (CPManagedObject) _fetchObjectWithID:(CPManagedObjectID) aObjectID
{
    var objectFromResponse = nil;
    if(aObjectID != nil)
    {
        if([self _deletedObjectWithID:aObjectID] == nil && [aObjectID validatedGlobalID])
        {
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
                    objectFromResponse = [self _registerObject:objectFromResponse];
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
        [self _registerObject: aObject];
        [_insertedObjectIDs addObject: [aObject objectID]];
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
