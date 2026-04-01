//
//  CPHTTPStore.j
//
//  HTTP-backed persistent store targeting the OrdersAPI cdFetch / cdSave
//  endpoints.
//
//  Wire protocol
//  -------------
//  Fetch:  POST <baseURL>/cdFetch   with JSON body (see _buildFetchBody:)
//  Save:   POST <baseURL>/cdSave    with JSON body (see saveObjectsUpdated:...)
//
//  Object identity
//  ---------------
//  Server IDs have the shape  { entity: "Order", pk: { orderID: 245 } }.
//  They are mapped to a stable globalID string:
//
//      "Order|orderID=245;"
//
//  This is the same key format that the OrdersAPI uses for objectsByID dict
//  keys, so local lookup is cheap.
//
//  Relationship storage
//  --------------------
//  To-one  relationships are stored in CPManagedObject._data as
//  CPManagedObjectID references.
//  To-many relationships are stored as CPMutableSet of CPManagedObjectID.
//  This is consistent with how CPManagedObject.storedValueForKey: resolves
//  relationships via the context.
//
//  Fault objects
//  -------------
//  When onlyIDs mode is used (transparentFetch == YES on the fetch request),
//  returned objects have _isFault = YES.  Values are filled in when the
//  context fires the fault via updateObjectWithID:mergeChanges:.
//

@import <Foundation/Foundation.j>
@import "CPHTTPStoreType.j"
@import "CPHTTPPredicateEncoder.j"


@implementation CPHTTPStore : CPPersistentStore
{
}


// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

- (CPString)_baseURL
{
    return [_configuration objectForKey:CPHTTPStoreBaseURL] || @"";
}

- (CPString)_cdFetchURL
{
    return [self _baseURL] + @"/cdFetch";
}

- (CPString)_cdSaveURL
{
    return [self _baseURL] + @"/cdSave";
}


// ---------------------------------------------------------------------------
// loadAll / saveAll – minimal stubs (HTTP store doesn't prefetch everything)
// ---------------------------------------------------------------------------

- (CPSet)          loadAll:(CPDictionary)properties
    inManagedObjectContext:(CPManagedObjectContext)context
                     error:(CPError)error
{
    return [CPSet new];
}

- (void)saveAll:(CPSet)objects error:(CPError)error
{
    // not used; saveObjectsUpdated:inserted:deleted:... is the primary save path
}


// ---------------------------------------------------------------------------
// executeFetchRequest:inManagedObjectContext:error:
// ---------------------------------------------------------------------------

- (CPSet)executeFetchRequest:(CPFetchRequest)request
      inManagedObjectContext:(CPManagedObjectContext)context
                       error:(CPError)error
{
    var body = [self _buildFetchBody:request];

    var responseData = [self _postJSON:body toURL:[self _cdFetchURL]];
    if (responseData === nil)
    {
        CPLog.error(@"CPHTTPStore cdFetch: no response from server");
        return [CPSet new];
    }

    var parsed;
    try { parsed = JSON.parse([responseData rawString]); }
    catch (e)
    {
        CPLog.error(@"CPHTTPStore cdFetch: JSON parse error: " + e);
        return [CPSet new];
    }

    if (!parsed || !parsed.ok)
    {
        CPLog.error(@"CPHTTPStore cdFetch: server error: " + JSON.stringify(parsed));
        return [CPSet new];
    }

    // --- count result type ---------------------------------------------------
    if (parsed.count !== undefined)
    {
        var countObj = [[CPManagedObject alloc] init];
        [countObj _setData:[CPDictionary dictionaryWithObject:parsed.count forKey:@"count"]];
        return [CPSet setWithObject:countObj];
    }

    var rootIDs    = parsed.root       || [],
        objectsByID = parsed.objectsByID || {},
        onlyIDs     = [request transparentFetch];

    // --- IDs-only mode or no objectsByID in response -------------------------
    if (onlyIDs || !parsed.objectsByID)
    {
        var resultSet = [[CPMutableSet alloc] init];
        for (var i = 0; i < rootIDs.length; i++)
        {
            var faultObj = [self _faultObjectForServerID:rootIDs[i] context:context];
            if (faultObj !== nil)
                [resultSet addObject:faultObj];
        }
        return resultSet;
    }

    // --- Full graph response -------------------------------------------------
    // First pass: materialise all objects (scalar values only)
    var allMaterialized = [[CPMutableDictionary alloc] init];
    for (var globalIDKey in objectsByID)
    {
        if (!objectsByID.hasOwnProperty(globalIDKey)) continue;
        var matObj = [self _materializeServerObject:objectsByID[globalIDKey]
                                            context:context];
        if (matObj !== nil)
            [allMaterialized setObject:matObj forKey:globalIDKey];
    }

    // Second pass: apply relationships
    for (var globalIDKey in objectsByID)
    {
        if (!objectsByID.hasOwnProperty(globalIDKey)) continue;
        var matObj = [allMaterialized objectForKey:globalIDKey];
        if (matObj === nil) continue;
        [self _applyRelationships:(objectsByID[globalIDKey].relationships || {})
                         toObject:matObj
                  allMaterialized:allMaterialized
                          context:context];
    }

    // Build result from root IDs
    var resultSet = [[CPMutableSet alloc] init];
    for (var i = 0; i < rootIDs.length; i++)
    {
        var key = [self _globalIDStringForServerID:rootIDs[i]],
            obj = [allMaterialized objectForKey:key];
        if (obj === nil)
            obj = [self _faultObjectForServerID:rootIDs[i] context:context];
        if (obj !== nil)
            [resultSet addObject:obj];
    }
    return resultSet;
}

/*!
    Build the cdFetch request body from a CPFetchRequest.

    Supported CPFetchRequest fields
    --------------------------------
    entity                   → "entity"
    predicate                → "predicate" (encoded via CPHTTPPredicateEncoder;
                               a raw CPDictionary is passed through)
    sortDescriptors          → "sort": [{key, dir}]
    fetchLimit               → "limit"
    fetchOffset              → "offset"
    propertiesToFetch        → "include": {relationships:[...], depth:N}
                               (pass an array of relationship name strings;
                               a single-element array ["count"] means resultType=count)
    transparentFetch == YES  → "return": {"onlyIDs": true}

    Additional cdFetch modes
    -------------------------
    Pass a CPDictionary predicate with an "ids" key to trigger fault-fulfillment
    fetch mode directly.
*/
- (CPDictionary)_buildFetchBody:(CPFetchRequest)request
{
    var body = [[CPMutableDictionary alloc] init];

    [body setObject:[[request entity] name] forKey:@"entity"];

    // predicate
    var predicate = [request predicate];
    if (predicate !== nil)
    {
        var ast = [CPHTTPPredicateEncoder encodePredicateToAST:predicate];
        if (ast !== nil)
            [body setObject:ast forKey:@"predicate"];
    }

    // sort
    var sortDescriptors = [request sortDescriptors];
    if (sortDescriptors !== nil && [sortDescriptors count] > 0)
    {
        var sortArray = [[CPMutableArray alloc] init];
        var se = [sortDescriptors objectEnumerator],
            sd;
        while ((sd = [se nextObject]))
            [sortArray addObject:[CPDictionary dictionaryWithObjectsAndKeys:
                                      [sd key],                        @"key",
                                      [sd ascending] ? @"asc" : @"desc", @"dir", nil]];
        [body setObject:sortArray forKey:@"sort"];
    }

    // paging
    if ([request fetchLimit] > 0)
        [body setObject:[request fetchLimit] forKey:@"limit"];
    if ([request fetchOffset] > 0)
        [body setObject:[request fetchOffset] forKey:@"offset"];

    // include / resultType
    var propertiesToFetch = [request propertiesToFetch];
    if (propertiesToFetch !== nil && [propertiesToFetch count] > 0)
    {
        // Special sentinel: ["count"] requests a count result type
        if (   [propertiesToFetch count] == 1
            && [[propertiesToFetch objectAtIndex:0] isEqualToString:@"count"])
        {
            [body setObject:@"count" forKey:@"resultType"];
        }
        else
        {
            var depth = [_configuration objectForKey:CPHTTPStoreDefaultIncludeDepth] || 1;
            [body setObject:[CPDictionary dictionaryWithObjectsAndKeys:
                                 propertiesToFetch, @"relationships",
                                 depth,             @"depth", nil]
                     forKey:@"include"];
        }
    }

    // onlyIDs mode
    if ([request transparentFetch])
        [body setObject:[CPDictionary dictionaryWithObject:YES forKey:@"onlyIDs"]
                 forKey:@"return"];

    return body;
}


// ---------------------------------------------------------------------------
// fetchObjectsWithID:fetchProperties:error:
//   Called by CPManagedObjectContext._fetchObjectWithID: when a fault fires.
// ---------------------------------------------------------------------------

- (CPSet)fetchObjectsWithID:(CPSet)objectIDs
            fetchProperties:(CPDictionary)fetchProperties
                      error:(CPError)error
{
    if (objectIDs === nil || [objectIDs count] == 0)
        return [CPSet new];

    // Build ids array for cdFetch
    var idsArray = [[CPMutableArray alloc] init];
    var e = [objectIDs objectEnumerator],
        objID;
    while ((objID = [e nextObject]))
    {
        if ([objID validatedGlobalID])
        {
            var entityName = [[objID entity] name];
            [idsArray addObject:[self _serverIDFromGlobalIDString:[objID globalID]
                                                       entityName:entityName]];
        }
    }

    if ([idsArray count] == 0)
        return [CPSet new];

    var body = [CPDictionary dictionaryWithObjectsAndKeys:
                    [[[[objectIDs objectEnumerator] nextObject] entity] name], @"entity",
                    idsArray, @"ids", nil];

    var responseData = [self _postJSON:body toURL:[self _cdFetchURL]];
    if (responseData === nil)
    {
        CPLog.error(@"CPHTTPStore cdFetch (ids): no response from server");
        return [CPSet new];
    }

    var parsed;
    try { parsed = JSON.parse([responseData rawString]); }
    catch (e) { CPLog.error(@"CPHTTPStore cdFetch (ids): JSON parse error: " + e); return [CPSet new]; }

    if (!parsed || !parsed.ok)
    {
        CPLog.error(@"CPHTTPStore cdFetch (ids): server error");
        return [CPSet new];
    }

    var context = nil; // context not available here; objects registered separately
    var objectsByID = parsed.objectsByID || {};
    var resultSet   = [[CPMutableSet alloc] init];
    var allMaterialized = [[CPMutableDictionary alloc] init];

    for (var globalIDKey in objectsByID)
    {
        if (!objectsByID.hasOwnProperty(globalIDKey)) continue;
        var matObj = [self _materializeServerObjectWithoutContext:objectsByID[globalIDKey]];
        if (matObj !== nil)
        {
            [allMaterialized setObject:matObj forKey:globalIDKey];
            [resultSet addObject:matObj];
        }
    }

    return resultSet;
}

/*!
    Materialise a server object without needing a managed object context
    (used by fetchObjectsWithID:fetchProperties:error:).
    Relationships are not applied.
*/
- (CPManagedObject)_materializeServerObjectWithoutContext:(id)serverObj
{
    var entityName = serverObj.entity || serverObj[@"entity"];
    var serverID   = serverObj.id     || serverObj[@"id"];
    var globalID   = [self _globalIDStringForServerID:serverID];
    var values     = serverObj.values || serverObj[@"values"] || {};

    var obj   = [[CPManagedObject alloc] init];
    var objID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                 globalID:globalID
                                              isTemporary:NO];
    [objID setStore:self];
    [obj setObjectID:objID];

    var data = [[CPMutableDictionary alloc] init];
    for (var k in values)
    {
        if (values.hasOwnProperty(k))
            [data setObject:values[k] forKey:k];
    }
    [obj _setData:data];
    [obj setFault:NO];
    return obj;
}


// ---------------------------------------------------------------------------
// saveObjectsUpdated:inserted:deleted:inManagedObjectContext:error:
// ---------------------------------------------------------------------------

- (CPSet)saveObjectsUpdated:(CPSet)updatedObjects
                   inserted:(CPSet)insertedObjects
                    deleted:(CPSet)deletedObjects
     inManagedObjectContext:(CPManagedObjectContext)context
                      error:(CPError)error
{
    var insertedArray = [[CPMutableArray alloc] init],
        updatedArray  = [[CPMutableArray alloc] init],
        deletedArray  = [[CPMutableArray alloc] init];

    // Encode inserted
    var ie = [insertedObjects objectEnumerator],
        obj;
    while ((obj = [ie nextObject]))
        [insertedArray addObject:[self _encodeObjectForInsert:obj]];

    // Encode updated
    var ue = [updatedObjects objectEnumerator];
    while ((obj = [ue nextObject]))
        [updatedArray addObject:[self _encodeObjectForUpdate:obj]];

    // Encode deleted
    var de = [deletedObjects objectEnumerator];
    while ((obj = [de nextObject]))
    {
        var objID = [obj objectID];
        if ([objID validatedGlobalID])
            [deletedArray addObject:[CPDictionary dictionaryWithObject:
                                         [self _serverIDForObjectID:objID]
                                                               forKey:@"id"]];
    }

    var body = [CPDictionary dictionaryWithObjectsAndKeys:
                    insertedArray, @"inserted",
                    updatedArray,  @"updated",
                    deletedArray,  @"deleted",
                    [CPDictionary dictionaryWithObjectsAndKeys:
                         YES, @"inserted",
                         NO,  @"updated",
                         YES, @"includeRelationships", nil], @"return",
                    nil];

    var responseData = [self _postJSON:body toURL:[self _cdSaveURL]];
    if (responseData === nil)
    {
        CPLog.error(@"CPHTTPStore cdSave: no response from server");
        return [CPSet new];
    }

    var parsed;
    try { parsed = JSON.parse([responseData rawString]); }
    catch (e)
    {
        CPLog.error(@"CPHTTPStore cdSave: JSON parse error: " + e);
        return [CPSet new];
    }

    if (!parsed || !parsed.ok)
    {
        CPLog.error(@"CPHTTPStore cdSave: server error: " + JSON.stringify(parsed));
        return [CPSet new];
    }

    var resultSet = [[CPMutableSet alloc] init];
    var idMap = parsed.idMap || {};

    // --- Apply idMap: update temp IDs to real (permanent) IDs ---------------
    var ie2 = [insertedObjects objectEnumerator];
    while ((obj = [ie2 nextObject]))
    {
        var tempKey = [self _tempKeyForObject:obj];
        if (tempKey && idMap[tempKey])
        {
            var serverID    = idMap[tempKey],
                newGlobalID = [self _globalIDStringForServerID:serverID];
            [[obj objectID] setGlobalID:newGlobalID];
            [[obj objectID] setIsTemporary:NO];
        }
        [resultSet addObject:obj];
    }

    // --- Update object version numbers from response.versions ---------------
    var versions = parsed.versions || [];
    for (var i = 0; i < versions.length; i++)
    {
        var vEntry  = versions[i],
            vGlobal = [self _globalIDStringForServerID:vEntry.id],
            vSearchID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                         globalID:vGlobal
                                                      isTemporary:NO],
            regObj  = [context objectRegisteredForID:vSearchID];
        if (regObj !== nil)
            [[regObj data] setObject:vEntry.version forKey:@"version"];
    }

    // --- Materialise objects returned by return.inserted / return.updated ---
    var returnedObjects = parsed.objects || [],
        allMaterialized = [[CPMutableDictionary alloc] init];

    // First pass: scalar values
    for (var i = 0; i < returnedObjects.length; i++)
    {
        var serverObj = returnedObjects[i],
            matObj    = [self _materializeServerObject:serverObj context:context];
        if (matObj !== nil)
        {
            var gKey = [self _globalIDStringForServerID:(serverObj.id || serverObj[@"id"])];
            [allMaterialized setObject:matObj forKey:gKey];
            [resultSet addObject:matObj];
        }
    }

    // Second pass: relationships
    for (var i = 0; i < returnedObjects.length; i++)
    {
        var serverObj = returnedObjects[i],
            gKey = [self _globalIDStringForServerID:(serverObj.id || serverObj[@"id"])],
            matObj = [allMaterialized objectForKey:gKey];
        if (matObj === nil) continue;
        [self _applyRelationships:(serverObj.relationships || {})
                         toObject:matObj
                  allMaterialized:allMaterialized
                          context:context];
    }

    // Include updated and deleted in result so the context can reconcile state
    [resultSet unionSet:updatedObjects];
    [resultSet unionSet:deletedObjects];

    return resultSet;
}


// ---------------------------------------------------------------------------
// HTTP transport
// ---------------------------------------------------------------------------

/*!
    POST JSON body to a URL synchronously.

    @return  CPData on success, nil on transport error.
*/
- (CPData)_postJSON:(id)bodyDict toURL:(CPString)urlString
{
    var jsonString;
    try
    {
        jsonString = JSON.stringify([self _toNativeObject:bodyDict]);
    }
    catch (e)
    {
        CPLog.error(@"CPHTTPStore: JSON serialisation error: " + e);
        return nil;
    }

    var url        = [CPURL URLWithString:urlString],
        urlRequest = [CPURLRequest requestWithURL:url];

    [urlRequest setHTTPMethod:@"POST"];
    [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [urlRequest setHTTPBody:jsonString];

    var urlResponse;
    return [CPURLConnection sendSynchronousRequest:urlRequest
                                 returningResponse:urlResponse];
}


// ---------------------------------------------------------------------------
// Object ID helpers
// ---------------------------------------------------------------------------

/*!
    Convert a server ID dict { entity:, pk: } to a stable globalID string.

    Accepts both plain JS objects (from JSON.parse) and CPDictionary instances.

    Format:  "Entity|key=val;"
    Composite PKs: keys are sorted for deterministic output.

    Examples
        { entity:"Customer", pk:{ customerID:1075 } }
            → "Customer|customerID=1075;"
        { entity:"OrderLine", pk:{ orderID:1, lineNo:2 } }
            → "OrderLine|lineNo=2;orderID=1;"
*/
- (CPString)_globalIDStringForServerID:(id)serverID
{
    var entity, pk;

    if ([serverID isKindOfClass:[CPDictionary class]])
    {
        entity = [serverID objectForKey:@"entity"] || @"";
        pk     = [serverID objectForKey:@"pk"]     || {};
    }
    else
    {
        entity = serverID.entity || @"";
        pk     = serverID.pk     || {};
    }

    // pk may be a CPDictionary (from internal encoding) or a plain JS object
    if ([pk isKindOfClass:[CPDictionary class]])
    {
        var keys  = [[pk allKeys] sortedArrayUsingSelector:@selector(compare:)],
            parts = [];
        for (var i = 0; i < [keys count]; i++)
        {
            var k = [keys objectAtIndex:i];
            parts.push(k + @"=" + [pk objectForKey:k]);
        }
        return entity + @"|" + parts.join(@";") + @";";
    }

    // Plain JS object
    if (typeof pk === "object" && pk !== null)
    {
        var keys  = Object.keys(pk).sort(),
            parts = [];
        for (var i = 0; i < keys.length; i++)
            parts.push(keys[i] + @"=" + pk[keys[i]]);
        return entity + @"|" + parts.join(@";") + @";";
    }

    return entity + @"|pk=" + pk + @";";
}

/*!
    Convert a globalID string back to a server { entity, pk } dictionary.
*/
- (CPDictionary)_serverIDFromGlobalIDString:(CPString)globalID
                                 entityName:(CPString)entityName
{
    var barIdx = globalID.indexOf(@"|");
    if (barIdx < 0)
        return nil;

    var resolvedEntity = entityName || globalID.substring(0, barIdx),
        pkPart = globalID.substring(barIdx + 1),
        pairs  = pkPart.split(@";"),
        pk     = [[CPMutableDictionary alloc] init];

    for (var i = 0; i < pairs.length; i++)
    {
        var pair = pairs[i];
        if (pair.length === 0) continue;
        var eqIdx = pair.indexOf(@"=");
        if (eqIdx < 0) continue;
        var k = pair.substring(0, eqIdx),
            v = pair.substring(eqIdx + 1),
            n = Number(v);
        [pk setObject:(isNaN(n) ? v : n) forKey:k];
    }

    return [CPDictionary dictionaryWithObjectsAndKeys:
                resolvedEntity, @"entity",
                pk,             @"pk", nil];
}

/*!
    Encode a CPManagedObjectID to a server { entity, pk } CPDictionary.
*/
- (CPDictionary)_serverIDForObjectID:(CPManagedObjectID)objectID
{
    return [self _serverIDFromGlobalIDString:[objectID globalID]
                                  entityName:[[objectID entity] name]];
}


// ---------------------------------------------------------------------------
// Object materialisation
// ---------------------------------------------------------------------------

/*!
    Create or update a CPManagedObject from a server "objectsByID" entry.
    Only scalar values are set; relationships are applied in a second pass.
*/
- (CPManagedObject)_materializeServerObject:(id)serverObj
                                    context:(CPManagedObjectContext)context
{
    var entityName = serverObj.entity || serverObj[@"entity"],
        model      = [context model],
        entity     = [model entityWithName:entityName];

    if (entity === nil)
    {
        CPLog.warn(@"CPHTTPStore: unknown entity '" + entityName + @"'; skipping object");
        return nil;
    }

    var serverID = serverObj.id || serverObj[@"id"],
        globalID = [self _globalIDStringForServerID:serverID],
        searchID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                    globalID:globalID
                                                 isTemporary:NO],
        existing = [context objectRegisteredForID:searchID],
        obj;

    if (existing !== nil)
        obj = existing;
    else
    {
        obj = [[CPManagedObject alloc] init];
        [obj setEntity:entity];
        [obj setContext:context];
        [obj _resetObjectDataForProperties];
        var objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                     globalID:globalID
                                                  isTemporary:NO];
        [objID setStore:self];
        [obj setObjectID:objID];
    }

    // Apply scalar values
    var values    = serverObj.values || serverObj[@"values"] || {},
        propNames = [entity propertyNames];

    for (var vi = 0; vi < [propNames count]; vi++)
    {
        var propName = [propNames objectAtIndex:vi];
        if ([entity isAttributeName:propName] && values.hasOwnProperty(propName))
            [[obj data] setObject:values[propName] forKey:propName];
    }

    [obj setFault:NO];
    return obj;
}

/*!
    Create a fault CPManagedObject with only the objectID populated.
*/
- (CPManagedObject)_faultObjectForServerID:(id)serverID
                                   context:(CPManagedObjectContext)context
{
    var entityName = serverID.entity || serverID[@"entity"],
        model      = (context !== nil) ? [context model] : nil,
        entity     = (model  !== nil) ? [model entityWithName:entityName] : nil;

    if (entity === nil)
    {
        CPLog.warn(@"CPHTTPStore: unknown entity '" + entityName + @"' for fault; skipping");
        return nil;
    }

    var globalID = [self _globalIDStringForServerID:serverID],
        searchID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                    globalID:globalID
                                                 isTemporary:NO],
        existing = [context objectRegisteredForID:searchID];

    if (existing !== nil)
        return existing;

    var obj   = [[CPManagedObject alloc] init];
    var objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:globalID
                                              isTemporary:NO];
    [objID setStore:self];
    [obj setObjectID:objID];
    [obj setEntity:entity];
    [obj setContext:context];
    [obj _resetObjectDataForProperties];
    [obj setFault:YES];
    return obj;
}

/*!
    Apply relationship data to a materialised CPManagedObject.

    To-one  → stored as CPManagedObjectID in _data
    To-many → stored as CPMutableSet of CPManagedObjectID in _data
*/
- (void)_applyRelationships:(id)relationships
                   toObject:(CPManagedObject)obj
            allMaterialized:(CPDictionary)allMaterialized
                    context:(CPManagedObjectContext)context
{
    if (relationships === nil) return;

    var entity    = [obj entity],
        relsByName = [entity relationshipsByName],
        relKeys   = Object.keys(relationships);

    for (var ri = 0; ri < relKeys.length; ri++)
    {
        var relName  = relKeys[ri],
            relDesc  = [relsByName objectForKey:relName];
        if (relDesc === nil) continue;

        var relValue = relationships[relName];
        if (relValue === nil || relValue === null)
        {
            [[obj data] setObject:nil forKey:relName];
            continue;
        }

        if ([relDesc isToMany])
        {
            var idSet = [[CPMutableSet alloc] init],
                arr   = Array.isArray(relValue) ? relValue : [relValue];
            for (var ai = 0; ai < arr.length; ai++)
            {
                var relID = [self _objectIDForServerID:arr[ai]
                                               context:context
                                       allMaterialized:allMaterialized];
                if (relID !== nil)
                    [idSet addObject:relID];
            }
            [[obj data] setObject:idSet forKey:relName];
        }
        else
        {
            var relID = [self _objectIDForServerID:relValue
                                           context:context
                                   allMaterialized:allMaterialized];
            [[obj data] setObject:relID forKey:relName];
        }
    }
}

- (CPManagedObjectID)_objectIDForServerID:(id)serverID
                                  context:(CPManagedObjectContext)context
                          allMaterialized:(CPDictionary)allMaterialized
{
    var entityName = serverID.entity || serverID[@"entity"],
        model      = (context !== nil) ? [context model] : nil,
        entity     = (model !== nil) ? [model entityWithName:entityName] : nil,
        globalID   = [self _globalIDStringForServerID:serverID];

    // Check allMaterialized first (same response graph)
    if (allMaterialized !== nil)
    {
        var matObj = [allMaterialized objectForKey:globalID];
        if (matObj !== nil)
            return [matObj objectID];
    }

    // Check context registry
    if (entity !== nil && context !== nil)
    {
        var searchID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                        globalID:globalID
                                                     isTemporary:NO],
            existing = [context objectRegisteredForID:searchID];
        if (existing !== nil)
            return [existing objectID];
    }

    // Return a new (unregistered) object ID
    var newEntity = entity;
    if (newEntity === nil)
    {
        newEntity = [[CPEntityDescription alloc] init];
        [newEntity setName:entityName];
    }
    var newID = [[CPManagedObjectID alloc] initWithEntity:newEntity
                                                 globalID:globalID
                                              isTemporary:NO];
    [newID setStore:self];
    return newID;
}


// ---------------------------------------------------------------------------
// Object encoding (cdSave payload)
// ---------------------------------------------------------------------------

- (CPDictionary)_encodeObjectForInsert:(CPManagedObject)obj
{
    var result  = [[CPMutableDictionary alloc] init],
        tempKey = [self _tempKeyForObject:obj];

    [result setObject:[CPDictionary dictionaryWithObject:tempKey forKey:@"temp"] forKey:@"id"];
    [result setObject:[[obj entity] name] forKey:@"entity"];

    var valueDict = [[CPMutableDictionary alloc] init],
        relDict   = [[CPMutableDictionary alloc] init];
    [self _encodePropertiesOf:obj values:valueDict relationships:relDict];

    [result setObject:valueDict forKey:@"values"];
    if ([relDict count] > 0)
        [result setObject:relDict forKey:@"relationships"];

    return result;
}

- (CPDictionary)_encodeObjectForUpdate:(CPManagedObject)obj
{
    var result = [[CPMutableDictionary alloc] init],
        objID  = [obj objectID];

    [result setObject:[self _serverIDForObjectID:objID] forKey:@"id"];
    [result setObject:[[obj entity] name] forKey:@"entity"];

    var valueDict = [[CPMutableDictionary alloc] init],
        relDict   = [[CPMutableDictionary alloc] init];
    [self _encodePropertiesOf:obj values:valueDict relationships:relDict];

    [result setObject:valueDict forKey:@"values"];
    if ([relDict count] > 0)
        [result setObject:relDict forKey:@"relationships"];

    // Optimistic locking: send expectedVersion if the object carries one
    var version = [[obj data] objectForKey:@"version"];
    if (version !== nil)
        [result setObject:version forKey:@"expectedVersion"];

    return result;
}

- (void)_encodePropertiesOf:(CPManagedObject)obj
                     values:(CPMutableDictionary)valueDict
              relationships:(CPMutableDictionary)relDict
{
    var entity    = [obj entity],
        data      = [obj data],
        propNames = [entity propertyNames];

    for (var pi = 0; pi < [propNames count]; pi++)
    {
        var propName  = [propNames objectAtIndex:pi],
            propValue = [data objectForKey:propName];

        if ([entity isAttributeName:propName])
        {
            if (propValue !== nil)
                [valueDict setObject:propValue forKey:propName];
        }
        else if ([entity isRelationshipName:propName])
        {
            if (propValue === nil) continue;

            var relDesc = [[entity relationshipsByName] objectForKey:propName];
            if ([relDesc isToMany])
            {
                var refs    = [[CPMutableArray alloc] init],
                    relEnum = [propValue isKindOfClass:[CPSet class]]
                                ? [propValue objectEnumerator]
                                : [[propValue allObjects] objectEnumerator],
                    relItem;
                while ((relItem = [relEnum nextObject]))
                {
                    if ([relItem isKindOfClass:[CPManagedObjectID class]])
                        [refs addObject:[self _refForObjectID:relItem]];
                }
                if ([refs count] > 0)
                    [relDict setObject:refs forKey:propName];
            }
            else
            {
                // propValue may be a CPManagedObject or a CPManagedObjectID
                var relIDObj = ([propValue isKindOfClass:[CPManagedObject class]])
                                    ? [propValue objectID]
                                    : propValue;
                if ([relIDObj isKindOfClass:[CPManagedObjectID class]])
                    [relDict setObject:[self _refForObjectID:relIDObj] forKey:propName];
            }
        }
    }
}

/*!
    Return either a temp-ref  { "temp": "t_<localID>" }
    or a permanent server ID  { "entity": ..., "pk": ... }
    for a CPManagedObjectID.
*/
- (CPDictionary)_refForObjectID:(CPManagedObjectID)objectID
{
    if ([objectID isTemporary])
        return [CPDictionary dictionaryWithObject:[self _tempKeyForObjectID:objectID]
                                           forKey:@"temp"];
    return [self _serverIDForObjectID:objectID];
}

- (CPString)_tempKeyForObject:(CPManagedObject)obj
{
    return [self _tempKeyForObjectID:[obj objectID]];
}

- (CPString)_tempKeyForObjectID:(CPManagedObjectID)objectID
{
    return @"t_" + [objectID localID];
}


// ---------------------------------------------------------------------------
// Native JS object conversion (required for JSON.stringify)
// ---------------------------------------------------------------------------

/*!
    Recursively convert Cappuccino collection objects to plain JS values so
    that JSON.stringify produces a correct result.

    YES / NO are JavaScript booleans in Cappuccino and pass through as-is.
    Plain JS numbers (fetchLimit, fetchOffset, etc.) also pass through.
    CPNumber instances are unwrapped via -doubleValue.
*/
- (id)_toNativeObject:(id)obj
{
    if (obj === nil || obj === null || obj === undefined)
        return null;

    // JS primitives (boolean, number, string) pass through directly.
    // This covers YES/NO, plain numeric values, and CPString (which IS a
    // JS string in Cappuccino's runtime).
    var t = typeof obj;
    if (t === "boolean" || t === "number" || t === "string")
        return obj;

    // From here obj is guaranteed to be a Cappuccino object (supports ObjJ messaging).

    if ([obj isKindOfClass:[CPNull class]])
        return null;

    if ([obj isKindOfClass:[CPDictionary class]])
    {
        var result = {},
            keys   = [obj allKeys];
        for (var i = 0; i < [keys count]; i++)
        {
            var k = [keys objectAtIndex:i];
            result[k] = [self _toNativeObject:[obj objectForKey:k]];
        }
        return result;
    }

    if ([obj isKindOfClass:[CPArray class]])
    {
        var result = [];
        for (var i = 0; i < [obj count]; i++)
            result.push([self _toNativeObject:[obj objectAtIndex:i]]);
        return result;
    }

    if ([obj isKindOfClass:[CPSet class]])
    {
        var result = [],
            e = [obj objectEnumerator],
            item;
        while ((item = [e nextObject]))
            result.push([self _toNativeObject:item]);
        return result;
    }

    if ([obj isKindOfClass:[CPNumber class]])
        return [obj doubleValue];

    // Fallback: return as-is (plain JS value stored in a collection).
    return obj;
}

@end
