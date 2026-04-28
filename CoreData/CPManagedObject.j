//
//  CPManagedObject.j
//
//  Created by Raphael Bartolome on 07.10.09.
//

@import <Foundation/Foundation.j>
@import "CPEntityDescription.j"
@import "CPManagedObjectContext.j"
@import "CPManagedObjectID.j"
@import "CPRelationshipDescription.j"

@class CPRelationshipDescription;
@class CPEntityDescription;
@class CPManagedObjectContext;

/*
**** HEADER ****
@private
- (void)willChangeValueForKey:(CPString)aKey;
- (void)didChangeValueForKey:(CPString)aKey;

- (BOOL)_solveRelationshipsWithDeleteRules;
- (void)_updateWithObject:(CPManagedObject) aObject;
- (void)_resetChangedDataForProperties;
- (void)_applyToContext:(CPManagedObjectContext) context;

- (CPArray)_properties;

- (BOOL)_containsKey:(CPString) aKey;
- (void)_resetObjectDataForProperties;

*/
CPManagedObjectUnexpectedValueTypeForProperty = "CPManagedObjectUnexpectedValueTypeForProperty";


/**
    Provides the management for object data.

    Object data is always assigned to an entity description which contains the
    property definitions.
    Access to properties must be done using KVC.
*/
@implementation CPManagedObject : CPObject
{
    CPEntityDescription _entity @accessors(property=entity);
    CPManagedObjectContext _context @accessors(property=context);
    CPPersistentStore _store @accessors(property=store);

    CPManagedObjectID _objectID @accessors(property=objectID);
    BOOL _isUpdated @accessors(getter=isUpdated, setter=setUpdated:);
    BOOL _isDeleted @accessors(getter=isDeleted, setter=setDeleted:);
    BOOL _isFault @accessors(getter=isFault, setter=setFault:);

    CPMutableDictionary _data @accessors(getter=data);
    CPMutableDictionary _changedData @accessors(getter=changedData);

    CPMutableSet _loadedRelationships;
}

-(id)init
{
    if (self = [super init])
    {
        _data = [[CPMutableDictionary alloc] init];
        _changedData = [[CPMutableDictionary alloc] init];
        _loadedRelationships = [[CPMutableSet alloc] init];
        _isUpdated = NO;
        _isDeleted = NO;
        _isFault = NO;
    }
    return self;
}

- (id)initWithEntity:(CPEntityDescription)entity
{
    return [self initWithEntity:entity inManagedObjectContext:nil];
}

- (id)initWithEntity:(CPEntityDescription)entity inManagedObjectContext:(CPManagedObjectContext)aContext
{
    if (self = [self init])
    {
        _entity = entity;
        _objectID = [[CPManagedObjectID alloc] initWithEntity:_entity
                                                     globalID:nil
                                                  isTemporary:YES];
        _context = aContext;
        [self _resetObjectDataForProperties];
        [_context insertObject:self];
    }
    return self;
}

/*!
    Returns the managed object context with which the receiver is registered.
    This is the CoreData-compatible alias for the \c context property.
*/
- (CPManagedObjectContext)managedObjectContext
{
    return _context;
}

/*!
    Record that a relationship was loaded from the persistent store.
    Called by CPHTTPStore after materialising a relationship from a server
    response.  Only relationships recorded here are included in the save
    payload for updated objects, preventing a partial inverse to-many set
    from overwriting the authoritative server-side collection.
*/
- (void)noteRelationshipLoaded:(CPString)key
{
    [_loadedRelationships addObject:key];
}

/*!
    Returns YES if the relationship named \a key was loaded from the
    persistent store (i.e. it was present in a server response and
    applied via -noteRelationshipLoaded:).
*/
- (BOOL)isRelationshipLoaded:(CPString)key
{
    return [_loadedRelationships containsObject:key];
}

/*
 *    KVC/KVO methods
 */
- (id)valueForKey:(CPString)aKey
{
    if ([self _containsKey:aKey])
    {// The key is a property from the entity
        return [self storedValueForKey:aKey];
    }
    else
    {
        return [super valueForKey:aKey];
    }
}

- (id)storedValueForKey:(CPString)aKey
{
    [self willAccessValueForKey:aKey];
    if ([self isPropertyOfTypeAttribute:aKey])
    {
        [self didAccessValueForKey:aKey];
        // Transform the value.
        // We do this here because we want to store the data untransformed.
        // The advantage of this is that we never modify data coming from an
        // external store except we really edit it.
        return [_entity transformValue:[_data objectForKey:aKey]
                           forProperty:aKey];
    }
    else if([self isPropertyOfTypeRelationship:aKey])
    {
        var value = [_data objectForKey:aKey];
        var values = nil;
        if(value != nil)
        {
            if([value isKindOfClass:[CPSet class]])
            {
                values = value;
            }
            else if([value isKindOfClass:[CPArray class]])
            {
                CPLog.warn("storedValueForKey: to-many relationship '" + aKey + "' stored as CPArray; converting to CPMutableSet");
                values = [CPMutableSet setWithArray: value];
            }
        }
        if(values != nil)
        {
            //return a qualified object set instead of a objectid array
            var resultSet  = [[CPSet alloc] init];
            var valuesEnumerator = [values objectEnumerator];
            var aValue;

            while((aValue = [valuesEnumerator nextObject]))
            {
                if(aValue != nil)
                {
                    var regObject = [_context objectRegisteredForID: aValue];
                    if(regObject == nil)
                    {
                        //if the regObject is nil we remove it
                        regObject = [_context updateObjectWithID:aValue mergeChanges:YES];
                        if(regObject != nil)
                        {
                            [values removeObject:aValue];
                            [values addObject:[regObject objectID]];
                            [self _setChangedObject:values forKey:aKey];
                        }
                        else
                        {
                            [values removeObject:aValue];
                            [self _setChangedObject:values forKey:aKey];
                        }
                    }
                    if(regObject != nil)
                        [resultSet addObject: regObject];
                }
            }
            [self didAccessValueForKey:aKey];
            return resultSet;
        }
        else if([_data objectForKey:aKey] != nil)
        {
            var regObject = [_context objectRegisteredForID:[_data objectForKey:aKey]];
            if(regObject == nil && [_data objectForKey:aKey] != nil)
            {
                regObject = [_context updateObjectWithID:[_data objectForKey:aKey] mergeChanges:YES];
                //if the regObject is nil we remove it
                if(regObject != nil)
                {
                    [self _setChangedObject:[regObject objectID] forKey:aKey];
                }
                else
                {
                    [self _setChangedObject:nil forKey:aKey];
                }
            }
            [self didAccessValueForKey:aKey];
            return regObject;
        }
    }
    [self didAccessValueForKey:aKey];
    return nil;
}

- (id)valueForKeyPath:(CPString)aKeyPath
{
    return [super valueForKeyPath:aKeyPath];
}

- (id)storedValueForKeyPath:(CPString)aKeyPath
{
    return [super valueForKeyPath:aKeyPath];
}

- (void)setValue:(id)aValue forKey:(CPString)aKey
{
    if([self _containsKey:aKey])
    {
        [self takeStoredValue:aValue forKey:aKey];
    }
    else
    {
        [super setValue:aValue forKey:aKey];
    }
}

- (void)takeStoredValue:(id)value forKey:(CPString)aKey
{
    if ([self isPropertyOfTypeAttribute:aKey])
    {
        if (   value == nil
            || [[self entity] acceptValue:value forProperty:aKey]
           )
        {
            [self willChangeValueForKey:aKey];
            [self _setChangedObject:value forKey:aKey];
            [self didChangeValueForKey:aKey];
        }
        else
        {
            [self _unexpectedValueTypeError:aKey expectedType:[[self attributeClassValue:aKey] className] receivedType:[value className]];
        }
    }
    else if([self isPropertyOfTypeRelationship: aKey])
    {
        var values;
        if([value isKindOfClass:[CPSet class]])
        {
            values = [value allObjects];
        }
        else if([value isKindOfClass:[CPArray class]])
        {
            values = value;
        }

        if(values != nil && [values count] > 0)
        {
            [self addObjects:values toBothSideOfRelationship:aKey];
        }
        else
        {
            [self addObject:value toBothSideOfRelationship:aKey];
        }
    }
}


- (void)setValue:(id)aValue forKeyPath:(CPString)aKeyPath
{
    [self takeStoredValue:aValue forKeyPath:aKeyPath];
}

- (void)takeStoredValue:(id)aValue forKeyPath:(CPString)aKeyPath
{
    [super setValue:aValue forKeyPath:aKeyPath];
}


- (void)addObjects:(CPArray)objectArray toBothSideOfRelationship:(CPString)propertyName
{
    if(objectArray != nil && [objectArray count] > 0)
    {
        var i = 0;

        for(i=0;i<[objectArray count];i++)
        {
            var object = [objectArray objectAtIndex:i];

            [self addObject:object toBothSideOfRelationship:propertyName];
        }
    }
}

- (void)addObject:(id)object toBothSideOfRelationship:(CPString)propertyName
{
    var tmpObjectID;

    if([object isKindOfClass: [CPManagedObject class]])
    {
        tmpObjectID = [object objectID];
    }
    else if([object isKindOfClass: [CPManagedObjectID class]])
    {
        tmpObjectID = object;
    }

    if(tmpObjectID != nil && [self isPropertyOfTypeRelationship: propertyName])
    {

        [self willChangeValueForKey:propertyName];

        //Add local
        var localRelationship = [[_entity relationshipsByName] objectForKey: propertyName];
        var propertyObject = [_data objectForKey:propertyName];

        if([localRelationship isToMany])
        {
            if(propertyObject == nil)
            {
                propertyObject = [[CPMutableSet alloc] init];
            }
            else
            {
                [propertyObject addObject: tmpObjectID];
            }

            // if([propertyObject containsObject:tmpObjectID])
            //     return;
            //
            // [propertyObject addObject: tmpObjectID];
            //
            // var changedPropertySet = nil;
            // if(![_changedData objectForKey:propertyName])
            //     changedPropertySet = [_changedData objectForKey:propertyName];
            // else
            //     changedPropertySet = [[CPMutableSet alloc] init];
            //
            // [changedPropertySet addObject:tmpObjectID];
            // [_changedData setObject:changedPropertySet forKey:propertyName];

            [self _setChangedObject:propertyObject forKey:propertyName];

        }
        else
        {
            if(propertyObject == tmpObjectID)
                return;

            propertyObject = tmpObjectID;

//            [_changedData setObject:propertyObject forKey:propertyName];
            [self _setChangedObject:propertyObject forKey:propertyName];
        }

        CPLog.debug(@"addObject:toBothSideOfRelationship: " + [localRelationship name]);

//        [_data setObject:propertyObject forKey:propertyName];
//        [_changedData setObject:propertyObject forKey:propertyName];

        //Add otherside
        var localRelationshipDestinationName  = [localRelationship destinationEntityName];
        var foreignRelationship = [self relationshipWithDestination:[localRelationship destination]];

//        CPLog.info([[self objectID] stringRepresentation]);
        var myObjectID = [[_context objectRegisteredForID:[self objectID]] objectID];


        if(myObjectID != nil)
        {
            if(![foreignRelationship isToMany])
            {
                [[_context objectRegisteredForID:tmpObjectID] addObject:myObjectID toBothSideOfRelationship:[foreignRelationship name]];
            }
            else
            {
                [[_context objectRegisteredForID:tmpObjectID] addObject:myObjectID toBothSideOfRelationship:[foreignRelationship name]];
            }
        }

        //Take care that the new object is under control
        if([_context objectRegisteredForID:tmpObjectID] == nil)
        {
            if ([object isKindOfClass:[CPManagedObject class]])
                [_context insertObject:object];
            else
                CPLog.warn(@"addObject:toBothSideOfRelationship: object with ID %@ is not registered in the context and cannot be inserted (only a CPManagedObjectID was provided)", tmpObjectID);
        }
        [self didChangeValueForKey:propertyName];
    }
}


- (void)removeObjects:(CPArray)objectArray fromBothSideOfRelationship:(CPString)propertyName
{
    //TODO implement
}

- (void)removeObject:(id)object fromBothSideOfRelationship:(CPString)propertyName
{
    //TODO implement
}

- (CPArray)toManyRelationshipsKey
{
    var result = [[CPMutableArray alloc] init];
    var relationshipDict = [_entity relationshipsByName];
    var allKeys = [relationshipDict allKeys];
    var i = 0;

    for(i=0;i<[allKeys count]; i++)
    {
        var key = [allKeys objectAtIndex:i];
        var tmpRel = [relationshipDict objectForKey: key];

        if([[tmpRel destination] isToMany] == YES)
        {
            [result addObject:tmpRel];
        }
    }
}

- (CPArray)toOneRelationshipsKey
{
    var result = [[CPMutableArray alloc] init];
    var relationshipDict = [_entity relationshipsByName];
    var allKeys = [relationshipDict allKeys];
    var i = 0;

    for(i=0;i<[allKeys count]; i++)
    {
        var key = [allKeys objectAtIndex:i];
        var tmpRel = [relationshipDict objectForKey: key];

        if([[tmpRel destination] isToMany] == NO)
        {
            [result addObject:tmpRel];
        }
    }
}


/*
 *    Detect changes and notify the context
 */
- (void)didChangeValueForKey:(CPString)aKey
{
    [super didChangeValueForKey:aKey];
    [_context _objectDidChange:self];
    if ([_context autoSaveChanges])
    {
        [_context saveChanges:nil];
    }
}


/*
 *    Detect changes and notify the context
 */

/*!
    Fire the receiver's fault if it has not yet been fulfilled.

    This is called automatically before every property access.  If the object
    is a fault AND has a global ID, the context is asked to resolve it — first
    from the coordinator's row cache, and on a cache miss from the persistent
    store.  After resolution the fault flag is cleared.
*/
- (void)willAccessValueForKey:(CPString)aKey
{
    if (_isFault && _context !== nil && _objectID !== nil && [_objectID validatedGlobalID])
    {
        // _fetchObjectWithID: either finds data in the coordinator's row cache
        // and merges it into self (via _registerObject: -> _updateWithObject:),
        // or fires a network request.  Either way, after this call self._data
        // has been populated.
        [_context _fetchObjectWithID:_objectID];
        _isFault = NO;
    }
}

- (void)didAccessValueForKey:(CPString)aKey
{
}

- (void)_unexpectedValueTypeError:(CPString) aKey expectedType:(CPString) expectedType receivedType:(CPString) receivedType
{
    CPLog.error("*** CPManagedObject Exception: expect value of type '" + expectedType + "', but received '" + receivedType + "' for property '" + aKey + "' ***");
}


/*
 * If the relationship is not empty or nil and the delete rule is CPRelationshipDescriptionDeleteRuleDeny
 * this method returns false otherwise it can be solve the relationship
 */
- (BOOL)_solveRelationshipsWithDeleteRules
{
    var result = YES;
    var e = [[_entity relationshipsByName] keyEnumerator];
    var property;

    while ((property = [e nextObject]) != nil)
    {
        var valueForProperty = [self valueForKey:property];
        var relationshipObject = [[_entity relationshipsByName] objectForKey:property];
        if([relationshipObject deleteRule] == CPRelationshipDescriptionDeleteRuleNullify)
        {
            CPLog.debug(@"The deletion rule for relationship '" + property + "' is CPRelationshipDescriptionDeleteRuleNullify.");
            if([self isPropertyOfTypeToManyRelationship:property])
            {
                if(valueForProperty != nil && [valueForProperty count] > 0)
                {
                    var valueForPropertyEnum = [valueForProperty objectEnumerator];
                    var objectFromValueForProperty;
                    while((objectFromValueForProperty = [valueForPropertyEnum nextObject]) != nil)
                    {
                        [objectFromValueForProperty _deleteReferencesForObject:self];
                    }
                }
            }
            else
            {
                if(valueForProperty != nil)
                {
                    [valueForProperty _deleteReferencesForObject:self];
                }
            }
        }
        else if([relationshipObject deleteRule] == CPRelationshipDescriptionDeleteRuleCascade)
        {
            CPLog.debug(@"The deletion rule for relationship '" + property + "' is CPRelationshipDescriptionDeleteRuleCascade.");
            if([self isPropertyOfTypeToManyRelationship:property])
            {
                if(valueForProperty != nil && [valueForProperty count] > 0)
                {
                    var valueForPropertyEnum = [valueForProperty objectEnumerator];
                    var objectFromValueForProperty;
                    while((objectFromValueForProperty = [valueForPropertyEnum nextObject]) != nil)
                    {
                        [objectFromValueForProperty _deleteReferencesForObject:self];
                        [_context _deleteObject:objectFromValueForProperty saveAfterDeletion:NO];
                    }
                }
            }
            else
            {
                if(valueForProperty != nil)
                {
                    [valueForProperty _deleteReferencesForObject:self];
                    [_context _deleteObject:valueForProperty saveAfterDeletion:NO];
                }
            }
        }
        else if([relationshipObject deleteRule] == CPRelationshipDescriptionDeleteRuleDeny)
        {
            CPLog.debug(@"The deletion rule for relationship '" + property + "' is CPRelationshipDescriptionDeleteRuleDeny.");
            if([self isPropertyOfTypeToManyRelationship:property])
            {
                if(valueForProperty != nil && [valueForProperty count] > 0)
                {
                    var valueForPropertyEnum = [valueForProperty objectEnumerator];
                    var objectFromValueForProperty;
                    while((objectFromValueForProperty = [valueForPropertyEnum nextObject]) != nil)
                    {
                        [objectFromValueForProperty _deleteReferencesForObject:self];
                    }

                    result = NO;
                    break;
                }
            }
            else
            {
                if(valueForProperty != nil)
                {
                    [valueForProperty _deleteReferencesForObject:self];
                    result = NO;
                    break;
                }
            }
        }
        else if([relationshipObject deleteRule] == CPRelationshipDescriptionDeleteRuleNoAction)
        {
            //don´t care about the deletion
            CPLog.debug(@"The deletion rule for relationship '" + property + "' is CPRelationshipDescriptionDeleteRuleNoAction.");
            [valueForProperty _deleteReferencesForObject:self];
        }
    }

//    CPLog.trace("_solveRelationshipsWithDeleteRules");

    return result;
}

- (void)_deleteReferencesForObject:(CPManagedObject) aObject
{
    var e = [[_entity relationshipsByName] keyEnumerator];
    var property;

    while ((property = [e nextObject]) != nil)
    {
        var valueForProperty = [self valueForKey:property];
        if(valueForProperty != nil)
        {
            if([self isPropertyOfTypeToManyRelationship:property])
            {
                var valueForPropertyEnum = [valueForProperty objectEnumerator];
                var objectFromValueForProperty;
                while((objectFromValueForProperty = [valueForPropertyEnum nextObject]) != nil)
                {
                    if ([[objectFromValueForProperty objectID] isEqualToLocalID: [aObject objectID]] == YES)
                    {
                        [valueForProperty removeObject:[objectFromValueForProperty objectID]];

                        var changedPropertySet = nil;
                        if(![_data objectForKey:property])
                            changedPropertySet = [_data objectForKey:property];

                        if(changedPropertySet != nil || [changedPropertySet count] > 0)
                        {
                            [changedPropertySet removeObject:[objectFromValueForProperty objectID]];
//                            [_changedData setObject:changedPropertySet forKey:property];
                            [self _setChangedObject:changedPropertySet forKey:property];
                        }
                    }
                }
            }
            else
            {
                if ([[valueForProperty objectID] isEqualToLocalID: [aObject objectID]] == YES)
                {
                    [self _setChangedObject:nil forKey:property];
                    // [_data setObject:nil forKey:property];
                    // [_changedData setObject:nil forKey:property];
                }
            }
        }
    }
}

- (void)_updateWithObject:(CPManagedObject) aObject
{
    [_objectID updateWithObjectID:[aObject objectID]];

    var data = [[aObject data] allKeys];
    var i = 0;
    for(i = 0;i<[data count];i++)
    {
        var aKey = [data objectAtIndex:i];
        var aValue = [[aObject data] objectForKey:aKey];
        [_data setObject:aValue forKey:aKey];
    }
}

- (BOOL)validateForDelete
{
    return [self _validateForChanges];
}

- (BOOL)validateForInsert
{
    return [self _validateForChanges];
}

- (BOOL)validateForUpdate
{
    return [self _validateForChanges];
}


/*
 * Lifecycle hooks
 *
 * These methods are called by CPManagedObjectContext at the appropriate
 * points in an object's lifecycle.  The default implementations are no-ops;
 * subclasses should override them without calling super (matching Apple's
 * NSManagedObject semantics).
 */

/*!
    Called the first time the receiver is inserted into a managed object
    context (i.e. after initWithEntity:inManagedObjectContext: completes).
    Subclasses can override this to set default property values.
*/
- (void)awakeFromInsert
{
}

/*!
    Called after the receiver has been fetched from a persistent store and
    populated with its persisted values.  Subclasses can override this to
    perform any post-fetch initialisation.
*/
- (void)awakeFromFetch
{
}

/*!
    Called on every dirty object just before the context sends a save request
    to the persistent store.  Subclasses can override this to make any last-
    minute changes before the save.
*/
- (void)willSave
{
}

/*!
    Called on every object that was part of a successful save operation after
    the save completes.  Subclasses can use this to trigger UI updates or
    post-save bookkeeping.
*/
- (void)didSave
{
}

/*!
    Called when the object is scheduled for deletion, before relationships are
    resolved and before the deletion is sent to the store.  Subclasses can
    override this to clean up derived data or unlink external resources.
*/
- (void)prepareForDeletion
{
}

- (BOOL)_validateForChanges
{
    var result = YES,
        allKeys = [_data allKeys],
        relationships = [_entity relationshipsByName];

    // For existing objects fetched from the server (non-temporary global ID),
    // Apple's CoreData only re-validates properties that were explicitly changed
    // by the application.  Properties that were never populated from the server
    // (nil in _data and absent from _changedData) must not block a save for an
    // otherwise valid change on the same object.  New inserts (temporary ID) are
    // always fully validated so all mandatory attributes must be supplied.
    var isNewObject = (_objectID === nil || [_objectID isTemporary]);

    for(var i=0; i < [allKeys count]; i++)
    {
        var property = [allKeys objectAtIndex:i];
        if ([_entity isMandatoryAttributeName:property])
        {
            if (   [_data objectForKey:property] == nil
                && ![_changedData objectForKey:property]
               )
            {
                if (!isNewObject)
                    continue; // existing object: skip nil check for unchanged attribute

                CPLog.warn(@"Object '%s' is not complete because property '%s' is missing",
                            [[self entity] name],
                            property
                          );
                return NO;
            }
        }
        else if ([_entity isRelationshipName:property])
        {
            var aRelationship = [relationships objectForKey:property];
            if ([_entity isMandatoryRelationship:aRelationship])
            {
                if(   [_data objectForKey:property] == nil
                   && ![_changedData objectForKey:property]
                  )
                {
                    if (!isNewObject)
                        continue; // existing object: skip nil check for unchanged relationship

                    CPLog.warn(@"Object '%s' is not complete because relation '%s' is missing",
                                [[self entity] name],
                                property
                              );
                    return NO;
                }
            }
            if([aRelationship isToMany])
            {
                var valueE = [[self valueForKey:property] objectEnumerator];
                var aObj;
                while((aObj = [valueE nextObject]))
                {
                    if(![aObj _validateForChanges])
                    {
                        CPLog.debug(@"Object is not complete because object with " + [[aObj objectID] localID] + " in toMany Relation '" + property + "' is not valid");
                        return NO;
                    }
                }
            }
        }
    }
    return result;
}

- (BOOL)_containsObject:(CPManagedObjectID) aObjectID
{
    var result = NO,
        allKeys = [_data allKeys],
        i = 0;
    for(i=0;i<[allKeys count];i++)
    {
        var property = [allKeys objectAtIndex:i];
        var valueForProperty = [_data objectForKey:property];
        if([self isPropertyOfTypeToOneRelationship:property])
        {
            if(valueForProperty != nil && [valueForProperty isEqualToLocalID:aObjectID])
                return YES;
        }
        else if([self isPropertyOfTypeToManyRelationship:property])
        {
            if(valueForProperty != nil && [valueForProperty containsObject:aObjectID])
                return YES;
        }
    }
    return result;
}

/*
@deprecated
- (void) _mergeChangedDataWithAllData
{
    var aEnum = [_data keyEnumerator];
    var aKey;
    while((aKey = [aEnum nextObject]))
    {
        var aObject = [_data objectForKey:aKey];
        if([_changedData objectForKey:aKey] == CPNull || [_changedData objectForKey:aKey] == nil)
        {
            [_changedData setObject:aObject forKey:aKey];
        }
    }
}
*/
- (void)_setChangedObject:(id) aObject forKey:(CPString) aKey
{
    var transformed = [_entity reverseTransformValue:aObject forProperty:aKey];
    [_changedData setObject:transformed forKey:aKey];
    [_data setObject:transformed forKey:aKey];
}

- (void)_resetChangedDataForProperties
{
    _changedData = [[CPMutableDictionary alloc] init];
}

- (void)_applyToContext:(CPManagedObjectContext)context
{
    if (_context === context)
        return
    _context = context;
    if(_objectID == nil)
    {
        _objectID = [[CPManagedObjectID alloc] initWithEntity:_entity globalID:nil isTemporary:YES];
        [_objectID setContext:context];
        [_objectID setPersistentStore:[context store]];
    }
}

- (CPArray)_properties
{
    return [_entity propertyNames];
}

- (BOOL)_containsKey:(CPString) aKey
{
    // A key is "contained" if it is a known property of the entity (regardless
    // of whether _data has been populated yet — fault objects have an empty
    // _data dictionary).  Routing all entity-property accesses through
    // storedValueForKey: ensures that willAccessValueForKey: is always called,
    // which fires pending faults before the value is read.
    if (_entity !== nil && [[_entity propertyNames] containsObject:aKey])
        return YES;
    return [[_data allKeys] containsObject: aKey];
}

- (void)_setData:(CPMutableDictionary) aDictionary
{
    _data = aDictionary;
    var e = [[_entity properties] objectEnumerator];
    var property;
    while ((property = [e nextObject]) != nil)
    {
        var propName = [property name];
        if([_data objectForKey:propName] == nil)
            [_data setObject:nil forKey:propName];
    }
}

- (void)_setChangedData:(CPMutableDictionary) aDictionary
{
    _changedData = aDictionary;
}

- (void)_resetObjectDataForProperties
{
    _data = [[CPMutableDictionary alloc] init];
    var e = [[_entity properties] objectEnumerator];
    var property;
    while ((property = [e nextObject]) != nil)
    {
        var propName = [property name];
        var value;
        if ([property isKindOfClass:[CPRelationshipDescription class]])
        {
            // relationships have no defaultValue; use nil for to-one and an
            // empty set for to-many
            value = [property isToMany] ? [[CPMutableSet alloc] init] : nil;
        }
        else
        {
            //@TODO nil is no longer supported as object
            value = [property defaultValue];
        }
        //value = [[self entity] transformValue:value
        //                          forProperty:propName];
        [_data setObject:value forKey:propName];
    }
}

- (BOOL)isPropertyOfTypeAttribute:(CPString)aKey
{
    return [_entity isAttributeName:aKey];
}

- (BOOL)isPropertyOfTypeRelationship:(CPString)aKey
{
    return [_entity isRelationshipName:aKey];
}

- (BOOL)isPropertyOfTypeToManyRelationship:(CPString)aKey
{
    var relationship = [[_entity relationshipsByName] objectForKey:aKey];
    if (relationship == nil)
    {
        return NO;
    }
    return [[[_entity relationshipsByName] objectForKey:aKey] isToMany];
}

- (BOOL)isPropertyOfTypeToOneRelationship:(CPString)aKey
{
    var relationship = [[_entity relationshipsByName] objectForKey:aKey];
    if (relationship == nil)
    {
        return NO;
    }
    return ![[[_entity relationshipsByName] objectForKey:aKey] isToMany];
}


- (Class)attributeClassValue:(CPString) aKey
{
    var result = nil;
    var att = [[_entity attributesByName] objectForKey:aKey];
    if(att != nil)
    {
        result = [att classValue];
    }
    return result;
}

- (Class)relationshipDestinationClassType:(CPString) key
{
    var result = nil;
    var att = [[_entity relationshipsByName] objectForKey:key];

    if(att != nil)
    {
        result = [att destinationClassType];
    }

    return result;
}


- (CPRelationshipDescription)relationshipWithDestination:(CPEntityDescription)entity
{
    var relationshipDict = [entity relationshipsByName];
    var allKeys = [relationshipDict allKeys];
    var i = 0;

    for(i=0;i<[allKeys count]; i++)
    {
        var key = [allKeys objectAtIndex:i];
        var tmpRel = [relationshipDict objectForKey: key];

        if([[tmpRel destination] isEqual: _entity])
        {
            return tmpRel;
        }
    }

    return nil;
}


- (CPString)stringRepresentation
{
    var result = "CPObject";

    result = result + [_objectID stringRepresentation];
    result = result + [_entity stringRepresentation];

    return result;
}


@end
