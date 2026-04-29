//
//  CPHTTPStore.j
//
//  HTTP-backed persistent store targeting the OrdersAPI cdFetch / cdSave
//  endpoints.
//
//  Adds HTTP status-aware transport and proper error propagation
//  for non-200 responses (400, 409, 422) using CPURLConnection delegate API.
//
//  422 handling: map OrdersAPI error JSON into standard CoreData validation errors
//  (CPCoreDataErrorDomain / CPValidationMultipleErrorsError / CPDetailedErrorsKey)
//  so callers cannot distinguish server-side from client-side validation failures.
//
//  Notes
//  -----
//  - The Foundation-provided CPURLConnection synchronous helper does NOT expose
//    HTTP status codes (it returns CPData only), so we implement our own
//    "sync" wrapper around the async delegate callbacks by spinning the run loop.
//  - On non-200: parse OrdersAPI error JSON if present and populate the `error`
//    out-param.  Returns nil without raising, consistent with NSIncrementalStore.
//

@import <Foundation/Foundation.j>
@import "CPPersistentStore.j"
@import "CPPersistentStoreType.j"
@import "CPHTTPStoreType.j"
@import "CPHTTPPredicateEncoder.j"

CPErrorLocalizedDescriptionKey = @"CPErrorLocalizedDescriptionKey";

@implementation CPHTTPStore : CPPersistentStore
{
}

// - Configuration

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

// - loadAll / saveAll (stubs)

- (CPSet)          loadAll:(CPDictionary)properties
    inManagedObjectContext:(CPManagedObjectContext)context
                     error:(@ref)error
{
    return [CPSet new];
}

- (void)saveAll:(CPSet)objects error:(@ref)error
{
    // not used; saveObjectsUpdated:inserted:deleted:... is the primary save path
}

// - executeFetchRequest

- (CPSet)executeFetchRequest:(CPFetchRequest)request
      inManagedObjectContext:(CPManagedObjectContext)context
                       error:(@ref)error
{
    var body = [self _buildFetchBody:request];

    var http = [self _postJSONAndReturnHTTPResult:body toURL:[self _cdFetchURL] error:error];
    if (http === nil)
        return [CPSet new];

    var parsed = [self _parseOrdersAPIResponseFromHTTP:http
                                              action:@"cdFetch"
                                               error:error];
    if (parsed === nil)
        return [CPSet new];

    // --- count result type ---------------------------------------------------
    if (parsed.count !== undefined)
    {
        var countObj = [[CPManagedObject alloc] init];
        [countObj _setData:[CPDictionary dictionaryWithObject:parsed.count forKey:@"count"]];
        return [CPSet setWithObject:countObj];
    }

    var rootIDs     = parsed.root        || [],
        objectsByID  = parsed.objectsByID || {},
        onlyIDs      = [request transparentFetch];

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

    // Return objects in the server-specified root order so callers see the
    // same ordering as the server intended.  Any materialised objects that
    // were included only for relationship prefetching (not listed in root)
    // are appended afterwards so they can still be registered by the context.
    var resultArray = [[CPMutableArray alloc] init];
    var inRoot = [[CPMutableSet alloc] init];
    for (var i = 0; i < rootIDs.length; i++)
    {
        var key = [self _globalIDStringForServerID:rootIDs[i]];
        var matObj = [allMaterialized objectForKey:key];
        if (matObj !== nil)
        {
            [resultArray addObject:matObj];
            [inRoot addObject:matObj];
        }
        else
        {
            var faultObj = [self _faultObjectForServerID:rootIDs[i] context:context];
            if (faultObj !== nil)
            {
                [resultArray addObject:faultObj];
                [inRoot addObject:faultObj];
            }
        }
    }
    // Append any materialised objects not listed in root (e.g. prefetched
    // relationship targets) so the context can still register them.
    var matEnum = [allMaterialized objectEnumerator];
    var matObj;
    while ((matObj = [matEnum nextObject]))
    {
        if (![inRoot containsObject:matObj])
            [resultArray addObject:matObj];
    }
    return resultArray;
}

/*!
    Build the cdFetch request body from a CPFetchRequest.
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
                                      [sd key],                         @"key",
                                      [sd ascending] ? @"asc" : @"desc", @"dir"]];
        [body setObject:sortArray forKey:@"sort"];
    }

    // paging
    if ([request fetchLimit] > 0)
        [body setObject:[request fetchLimit] forKey:@"limit"];
    if ([request fetchOffset] > 0)
        [body setObject:[request fetchOffset] forKey:@"offset"];

    // include / resultType
    var relationshipKeyPaths = [request relationshipKeyPathsForPrefetching];
    if (relationshipKeyPaths !== nil && [relationshipKeyPaths count] > 0)
    {
        var configDepth = [_configuration objectForKey:CPHTTPStoreDefaultIncludeDepth] || 1;
        var computedDepth = 1;
        for (var pi = 0; pi < [relationshipKeyPaths count]; pi++)
        {
            var keyPath = [relationshipKeyPaths objectAtIndex:pi],
                parts   = [keyPath componentsSeparatedByString:@"."],
                d       = [parts count];
            if (d > computedDepth)
                computedDepth = d;
        }
        var depth = computedDepth > configDepth ? computedDepth : configDepth;
        [body setObject:[CPDictionary dictionaryWithObjectsAndKeys:
                             relationshipKeyPaths, @"relationships",
                             depth,                @"depth"]
                 forKey:@"include"];
    }

    if ([request resultType] === CPCountResultType)
        [body setObject:@"count" forKey:@"resultType"];

    // onlyIDs mode
    if ([request transparentFetch])
        [body setObject:[CPDictionary dictionaryWithObject:YES forKey:@"onlyIDs"]
                 forKey:@"return"];

    return body;
}

// - Fault fulfilment fetch

- (CPSet)fetchObjectsWithID:(CPSet)objectIDs
            fetchProperties:(CPDictionary)fetchProperties
                      error:(@ref)error
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

    var firstID = [[objectIDs objectEnumerator] nextObject];
    var entityName = (firstID !== nil && [firstID entity] !== nil)
                        ? [[firstID entity] name]
                        : @"";
    var body = [CPDictionary dictionaryWithObjectsAndKeys:
                    entityName, @"entity",
                    idsArray,   @"ids"];

    var http = [self _postJSONAndReturnHTTPResult:body toURL:[self _cdFetchURL] error:error];
    if (http === nil)
        return [CPSet new];

    var parsed = [self _parseOrdersAPIResponseFromHTTP:http
                                              action:@"cdFetch(ids)"
                                               error:error];
    if (parsed === nil)
        return [CPSet new];

    if (!parsed.objectsByID)
        return [CPSet new];

    var objectsByID = parsed.objectsByID || {};
    var resultSet   = [[CPMutableSet alloc] init];

    for (var globalIDKey in objectsByID)
    {
        if (!objectsByID.hasOwnProperty(globalIDKey)) continue;
        var matObj = [self _materializeServerObjectWithoutContext:objectsByID[globalIDKey]];
        if (matObj !== nil)
            [resultSet addObject:matObj];
    }

    return resultSet;
}

- (CPManagedObject)_materializeServerObjectWithoutContext:(id)serverObj
{
    var serverID   = serverObj.id     || serverObj[@"id"];
    var globalID   = [self _globalIDStringForServerID:serverID];
    var values     = serverObj.values || serverObj[@"values"] || {};

    // Try to look up the entity model via the store coordinator so we can
    // coerce typed values (e.g. Date strings → CPDate) just like the
    // context-aware path does.
    var entityName = serverObj.entity || serverObj[@"entity"],
        model      = [[self storeCoordinator] managedObjectModel],
        entity     = (model !== nil && entityName) ? [model entityWithName:entityName] : nil;

    var obj   = [[CPManagedObject alloc] init];
    var objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:globalID
                                              isTemporary:NO];
    [objID setPersistentStore:self];
    [obj setObjectID:objID];

    var data = [[CPMutableDictionary alloc] init];
    for (var k in values)
    {
        if (values.hasOwnProperty(k))
        {
            var val = values[k];
            if (entity !== nil && [entity isAttributeName:k])
            {
                var attrDesc = [[entity attributesByName] objectForKey:k],
                    attrType = (attrDesc !== nil) ? [attrDesc typeValue] : CPDUndefinedAttributeType;
                val = [self _coerceJSONValue:val toAttributeType:attrType];
            }
            [data setObject:val forKey:k];
        }
    }
    [obj _setData:data];
    [obj setFault:NO];

    // Cache the attribute snapshot at coordinator level.
    var coordinator = [self storeCoordinator];
    if (coordinator !== nil && globalID !== nil)
        [coordinator cacheRowData:data forGlobalID:globalID];

    return obj;
}

// - Save

- (CPSet)saveObjectsUpdated:(CPSet)updatedObjects
                   inserted:(CPSet)insertedObjects
                    deleted:(CPSet)deletedObjects
     inManagedObjectContext:(CPManagedObjectContext)context
                      error:(@ref)error
{
    var insertedArray = [[CPMutableArray alloc] init],
        updatedArray  = [[CPMutableArray alloc] init],
        deletedArray  = [[CPMutableArray alloc] init];

    // Encode inserted
    var ie = [insertedObjects objectEnumerator],
        obj;
    while ((obj = [ie nextObject]))
        [insertedArray addObject:[self _encodeObjectForInsert:obj]];

    // Encode updated — skip objects that have no actual changes to send
    // (e.g. a fetched entity whose only _changedData entries are inverse
    // to-many relationships that were never loaded from the server)
    var ue = [updatedObjects objectEnumerator];
    while ((obj = [ue nextObject]))
    {
        var encoded = [self _encodeObjectForUpdate:obj];
        if (encoded !== nil)
            [updatedArray addObject:encoded];
    }

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
                         YES, @"includeRelationships"], @"return"];

    var http = [self _postJSONAndReturnHTTPResult:body toURL:[self _cdSaveURL] error:error];
    if (http === nil)
        return [CPSet new];

    var parsed = [self _parseOrdersAPIResponseFromHTTP:http
                                              action:@"cdSave"
                                               error:error];
    if (parsed === nil)
        return [CPSet new];

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
        var vEntry   = versions[i],
            vGlobal  = [self _globalIDStringForServerID:vEntry.id],
            vSearchID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                         globalID:vGlobal
                                                      isTemporary:NO],
            regObj   = [context objectRegisteredForID:vSearchID];
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

// - HTTP transport

/*!
    POST a JSON body asynchronously.  Returns immediately; the completionHandler
    is called from CPURLConnection delegate callbacks once the response arrives
    (or the connection fails).

    completionHandler signature:  function(httpDict, transportError)
      httpDict       -- CPDictionary{ @"statusCode", @"text", @"url" } on success
      transportError -- non-nil on transport-level failure (httpDict is nil)
*/
- (void)_postJSONAsync:(id)bodyDict
                 toURL:(CPString)urlString
     completionHandler:(Function)handler
{
    // Serialize body
    var jsonString;
    try
    {
        jsonString = JSON.stringify([self _toNativeObject:bodyDict]);
    }
    catch (e)
    {
        var serErr = [self _cpErrorWithDomain:@"CPHTTPStore"
                                         code:1001
                                      message:@"JSON serialisation error"
                                    httpStatus:0
                                      apiError:nil
                                      userInfo:@{ @"exception": String(e) }];
        handler(nil, serErr);
        return;
    }

    // Build request
    var url = [CPURL URLWithString:urlString],
        req = [CPURLRequest requestWithURL:url];

    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setHTTPBody:jsonString];

    // Each request gets its own delegate object -- multiple concurrent requests
    // are safe because per-request state is isolated in CPHTTPStoreRequest.
    var storeReq = [CPHTTPStoreRequest requestWithURL:urlString
                                    completionHandler:handler];
    [CPURLConnection connectionWithRequest:req delegate:storeReq];
}

/*!
    Synchronous wrapper around _postJSONAsync:toURL:completionHandler:.

    @deprecated  In browser environments this BLOCKS the run loop (freezes UI).
                 Use executeFetchRequestAsync:inManagedObjectContext:completionHandler:
                 or saveObjectsUpdated:inserted:deleted:inManagedObjectContext:completionHandler:
                 instead.

    Retained for backward compatibility with code that calls the synchronous
    CPPersistentStore protocol (executeFetchRequest:inManagedObjectContext:error:,
    saveObjectsUpdated:inserted:deleted:inManagedObjectContext:error:).
*/
- (CPDictionary)_postJSONAndReturnHTTPResult:(id)bodyDict
                                       toURL:(CPString)urlString
                                       error:(@ref)error
{
    var done           = NO,
        httpResult     = nil,
        transportErr   = nil;

    [self _postJSONAsync:bodyDict toURL:urlString completionHandler:function(http, err) {
        httpResult   = http;
        transportErr = err;
        done = YES;
    }];

    // Spin the run loop until the async response arrives.
    // WARNING: This blocks the browser's rendering pipeline.
    // Prefer the async API for browser-hosted apps.
    var runLoop = [CPRunLoop currentRunLoop];
    while (!done)
        [runLoop limitDateForMode:CPDefaultRunLoopMode];

    if (transportErr !== nil)
    {
        var cpErr = [self _cpErrorWithDomain:@"CPHTTPStore"
                                        code:1002
                                     message:@"Transport error"
                                   httpStatus:0
                                     apiError:nil
                                     userInfo:@{ @"transportError": transportErr,
                                                 @"url": urlString }];
        if (error)
            @deref(error) = cpErr;
        return nil;
    }

    return httpResult;
}

// - Async fetch

/*!
    Non-blocking counterpart of executeFetchRequest:inManagedObjectContext:error:.
    Fires the HTTP request and returns immediately; the completionHandler is
    called once the response arrives.

    completionHandler signature:  function(resultSet CPSet, error CPError)
*/
- (void)executeFetchRequestAsync:(CPFetchRequest)request
          inManagedObjectContext:(CPManagedObjectContext)context
               completionHandler:(Function)handler
{
    var body  = [self _buildFetchBody:request],
        self_ = self;

    [self _postJSONAsync:body toURL:[self _cdFetchURL] completionHandler:function(http, transportError) {
        if (transportError !== nil || http === nil)
        {
            handler([CPSet new], transportError);
            return;
        }

        var localError = nil,
            errRef = @ref(localError),
            parsed = [self_ _parseOrdersAPIResponseFromHTTP:http action:@"cdFetch" error:errRef];

        if (parsed === nil)
        {
            handler([CPSet new], localError);
            return;
        }

        // count result type
        if (parsed.count !== undefined)
        {
            var countObj = [[CPManagedObject alloc] init];
            [countObj _setData:[CPDictionary dictionaryWithObject:parsed.count forKey:@"count"]];
            handler([CPSet setWithObject:countObj], nil);
            return;
        }

        var rootIDs     = parsed.root        || [],
            objectsByID = parsed.objectsByID || {},
            onlyIDs     = [request transparentFetch];

        // IDs-only mode
        if (onlyIDs || !parsed.objectsByID)
        {
            var resultSet = [[CPMutableSet alloc] init];
            for (var i = 0; i < rootIDs.length; i++)
            {
                var faultObj = [self_ _faultObjectForServerID:rootIDs[i] context:context];
                if (faultObj !== nil)
                    [resultSet addObject:faultObj];
            }
            handler(resultSet, nil);
            return;
        }

        // Full graph materialisation
        var allMaterialized = [[CPMutableDictionary alloc] init];
        for (var globalIDKey in objectsByID)
        {
            if (!objectsByID.hasOwnProperty(globalIDKey)) continue;
            var matObj = [self_ _materializeServerObject:objectsByID[globalIDKey] context:context];
            if (matObj !== nil)
                [allMaterialized setObject:matObj forKey:globalIDKey];
        }
        for (var globalIDKey in objectsByID)
        {
            if (!objectsByID.hasOwnProperty(globalIDKey)) continue;
            var matObj = [allMaterialized objectForKey:globalIDKey];
            if (matObj === nil) continue;
            [self_ _applyRelationships:(objectsByID[globalIDKey].relationships || {})
                              toObject:matObj
                       allMaterialized:allMaterialized
                               context:context];
        }

        var resultArray = [[CPMutableArray alloc] init];
        var inRoot = [[CPMutableSet alloc] init];
        for (var i = 0; i < rootIDs.length; i++)
        {
            var key = [self_ _globalIDStringForServerID:rootIDs[i]];
            var matObj = [allMaterialized objectForKey:key];
            if (matObj !== nil)
            {
                [resultArray addObject:matObj];
                [inRoot addObject:matObj];
            }
            else
            {
                var faultObj = [self_ _faultObjectForServerID:rootIDs[i] context:context];
                if (faultObj !== nil)
                {
                    [resultArray addObject:faultObj];
                    [inRoot addObject:faultObj];
                }
            }
        }
        var matEnum = [allMaterialized objectEnumerator];
        var matObj;
        while ((matObj = [matEnum nextObject]))
        {
            if (![inRoot containsObject:matObj])
                [resultArray addObject:matObj];
        }
        handler(resultArray, nil);
    }];
}

// - Async save

/*!
    Non-blocking counterpart of saveObjectsUpdated:inserted:deleted:inManagedObjectContext:error:.
    Fires the HTTP request and returns immediately; the completionHandler is
    called once the response arrives.

    completionHandler signature:  function(resultSet CPSet, error CPError)
*/
- (void)saveObjectsUpdated:(CPSet)updatedObjects
                  inserted:(CPSet)insertedObjects
                   deleted:(CPSet)deletedObjects
    inManagedObjectContext:(CPManagedObjectContext)context
         completionHandler:(Function)handler
{
    var insertedArray = [[CPMutableArray alloc] init],
        updatedArray  = [[CPMutableArray alloc] init],
        deletedArray  = [[CPMutableArray alloc] init];

    var ie = [insertedObjects objectEnumerator],
        obj;
    while ((obj = [ie nextObject]))
        [insertedArray addObject:[self _encodeObjectForInsert:obj]];

    // Skip objects with no actual changes to send (see sync path comment above)
    var ue = [updatedObjects objectEnumerator];
    while ((obj = [ue nextObject]))
    {
        var encoded = [self _encodeObjectForUpdate:obj];
        if (encoded !== nil)
            [updatedArray addObject:encoded];
    }

    var de = [deletedObjects objectEnumerator];
    while ((obj = [de nextObject]))
    {
        var objID = [obj objectID];
        if ([objID validatedGlobalID])
            [deletedArray addObject:[CPDictionary dictionaryWithObject:
                                         [self _serverIDForObjectID:objID]
                                                               forKey:@"id"]];
    }

    var body  = [CPDictionary dictionaryWithObjectsAndKeys:
                     insertedArray, @"inserted",
                     updatedArray,  @"updated",
                     deletedArray,  @"deleted",
                     [CPDictionary dictionaryWithObjectsAndKeys:
                          YES, @"inserted",
                          NO,  @"updated",
                          YES, @"includeRelationships"], @"return"],
        self_ = self;

    [self _postJSONAsync:body toURL:[self _cdSaveURL] completionHandler:function(http, transportError) {
        if (transportError !== nil || http === nil)
        {
            handler([CPSet new], transportError);
            return;
        }

        var localError = nil,
            errRef = @ref(localError),
            parsed = [self_ _parseOrdersAPIResponseFromHTTP:http action:@"cdSave" error:errRef];

        if (parsed === nil)
        {
            handler([CPSet new], localError);
            return;
        }

        var resultSet = [[CPMutableSet alloc] init],
            idMap     = parsed.idMap || {};

        // Apply idMap: update temp IDs to permanent IDs
        var ie2 = [insertedObjects objectEnumerator];
        while ((obj = [ie2 nextObject]))
        {
            var tempKey = [self_ _tempKeyForObject:obj];
            if (tempKey && idMap[tempKey])
            {
                var serverID    = idMap[tempKey],
                    newGlobalID = [self_ _globalIDStringForServerID:serverID];
                [[obj objectID] setGlobalID:newGlobalID];
                [[obj objectID] setIsTemporary:NO];
            }
            [resultSet addObject:obj];
        }

        // Update object version numbers
        var versions = parsed.versions || [];
        for (var i = 0; i < versions.length; i++)
        {
            var vEntry    = versions[i],
                vGlobal   = [self_ _globalIDStringForServerID:vEntry.id],
                vSearchID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                             globalID:vGlobal
                                                          isTemporary:NO],
                regObj    = [context objectRegisteredForID:vSearchID];
            if (regObj !== nil)
                [[regObj data] setObject:vEntry.version forKey:@"version"];
        }

        // Materialise objects returned by return.inserted / return.updated
        var returnedObjects = parsed.objects || [],
            allMaterialized = [[CPMutableDictionary alloc] init];

        for (var i = 0; i < returnedObjects.length; i++)
        {
            var serverObj = returnedObjects[i],
                matObj    = [self_ _materializeServerObject:serverObj context:context];
            if (matObj !== nil)
            {
                var gKey = [self_ _globalIDStringForServerID:(serverObj.id || serverObj[@"id"])];
                [allMaterialized setObject:matObj forKey:gKey];
                [resultSet addObject:matObj];
            }
        }

        for (var i = 0; i < returnedObjects.length; i++)
        {
            var serverObj = returnedObjects[i],
                gKey      = [self_ _globalIDStringForServerID:(serverObj.id || serverObj[@"id"])],
                matObj    = [allMaterialized objectForKey:gKey];
            if (matObj === nil) continue;
            [self_ _applyRelationships:(serverObj.relationships || {})
                              toObject:matObj
                       allMaterialized:allMaterialized
                               context:context];
        }

        [resultSet unionSet:updatedObjects];
        [resultSet unionSet:deletedObjects];
        handler(resultSet, nil);
    }];
}

/*!
    Parse OrdersAPI JSON from an HTTP result, and convert non-200 / ok:false
    into a CPError via the error out-parameter.

    For 422 specifically: create CoreData-like validation error(s) based on the
    OrdersAPI `error.errors[]` array (entity, temp/id, path, kind, message, op, index).

    Returns parsed JS object on success (HTTP 200 and parsed.ok == true).
    Returns nil and populates the error out-param on any failure.
    Never raises an exception, consistent with NSIncrementalStore.
*/
- (id)_parseOrdersAPIResponseFromHTTP:(CPDictionary)http
                              action:(CPString)action
                               error:(@ref)error
{
    var statusCode = [http objectForKey:@"statusCode"],
        text       = [http objectForKey:@"text"] || @"",
        url        = [http objectForKey:@"url"] || @"";

    var parsed = nil;
    if (text && [text length] > 0)
    {
        try { parsed = JSON.parse(text); }
        catch (e) { parsed = nil; }
    }

    // Non-200: prefer OrdersAPI error envelope if present
    if (statusCode !== 200)
    {
        var apiErr = (parsed && parsed.error) ? parsed.error : nil;

        // 422: map into validation-style error(s)
        if (statusCode === 422)
        {
            if (error)
                @deref(error) = [self _cpCoreDataValidationErrorFromOrdersAPIError:apiErr
                                                                httpStatus:422
                                                                       url:url
                                                                    action:action];

            return nil;
        }

        if (error)
            @deref(error) = [self _cpErrorForOrdersAPIError:apiErr
                                         httpStatus:statusCode
                                            message:(apiErr && apiErr.message) ? apiErr.message : @"HTTP error"
                                               url:url
                                            action:action
                                      responseText:text];

        return nil;
    }

    // HTTP 200 but body is not valid JSON
    if (!parsed)
    {
        if (error)
            @deref(error) = [self _cpErrorWithDomain:@"CPHTTPStore"
                                        code:1100
                                     message:@"Invalid JSON from server"
                                   httpStatus:200
                                    apiError:nil
                                    userInfo:@{ @"url": url,
                                                @"action": action,
                                                @"responseText": text }];
        return nil;
    }

    // HTTP 200 but ok:false: treat as error
    if (!parsed.ok)
    {
        var apiErr = parsed.error || nil;

        // Some servers may return ok:false with 200; if domain suggests validation,
        // propagate as a standard CoreData validation error.
        var isValidation = apiErr && apiErr.domain && (apiErr.domain === "Validation");
        if (isValidation)
        {
            if (error)
                @deref(error) = [self _cpCoreDataValidationErrorFromOrdersAPIError:apiErr
                                                                httpStatus:200
                                                                       url:url
                                                                    action:action];
            return nil;
        }

        if (error)
            @deref(error) = [self _cpErrorForOrdersAPIError:apiErr
                                         httpStatus:200
                                            message:(apiErr && apiErr.message) ? apiErr.message : @"Server error"
                                               url:url
                                            action:action
                                      responseText:text];

        return nil;
    }

    return parsed;
}

// - 422 / validation mapping

/*!
    Convert OrdersAPI 422 payload into a standard CoreData validation error.

    OrdersAPI error envelope shape:
      { domain, code, message, requestID, errors:[ {entity, kind, message, path, temp, id, op, index}, ... ] }

    The returned error matches the format produced by
    CPManagedObjectContext._validateUpdatedObject:insertedObjects:error: so that
    clients do not need to distinguish server-side from client-side validation
    failures:

      domain = CPCoreDataErrorDomain
      code   = CPValidationMultipleErrorsError (1550)
      userInfo = {
          CPLocalizedDescriptionKey : human-readable summary
          CPDetailedErrorsKey       : [ CPError, ... ]  -- one per server error entry
                                        each sub-error: domain=CPCoreDataErrorDomain,
                                        code=CPValidationMissingMandatoryPropertyError (1570),
                                        userInfo carries field-level info (entity, property, kind, ...)
          // server-specific extras preserved for diagnostics:
          "httpStatus"    : <int>
          "url"           : <string>
          "action"        : <string>
          "api.code"      : <string>
          "api.message"   : <string>
          "api.requestID" : <string>  (if present)
          "api.errors"    : <raw JS array>  (if present)
      }
*/
- (CPError)_cpCoreDataValidationErrorFromOrdersAPIError:(id)apiErr
                                            httpStatus:(int)httpStatus
                                                   url:(CPString)url
                                                action:(CPString)action
{
    var apiCode = (apiErr && apiErr.code) ? apiErr.code : @"validation_failed";
    var apiMsg  = (apiErr && apiErr.message) ? apiErr.message : @"Validation failed";

    // Build one CPError per server-reported field/entity error and collect them
    // into CPDetailedErrors, exactly as local validation does.
    var detailedErrors = [[CPMutableArray alloc] init];

    var errs = (apiErr && apiErr.errors) ? apiErr.errors : [];
    for (var i = 0; i < errs.length; i++)
    {
        var e = errs[i] || {};
        var ent  = e.entity || @"";
        var temp = e.temp || null;
        var gid  = e.id   || null;
        var kind = e.kind || @"validation";
        var msg  = e.message || @"Validation error";
        var path = e.path || null;
        var op   = e.op   || null;
        var idx  = (e.index !== undefined) ? e.index : null;

        // Best-effort: interpret JSON path
        // values.city -> propertyName="city"
        // relationships.shippingAddress -> propertyName="shippingAddress"
        var propertyName = null;
        if (path)
        {
            var dot = path.indexOf(".");
            if (dot >= 0 && dot + 1 < path.length)
                propertyName = path.substring(dot + 1);
            else
                propertyName = path;
        }

        var subUI = [CPMutableDictionary dictionary];
        [subUI setObject:msg forKey:CPLocalizedDescriptionKey];
        if (ent)          [subUI setObject:ent          forKey:@"entity"];
        if (temp)         [subUI setObject:temp         forKey:@"temp"];
        if (gid)          [subUI setObject:gid          forKey:@"id"];
        if (kind)         [subUI setObject:kind         forKey:@"kind"];
        if (propertyName) [subUI setObject:propertyName forKey:@"property"];
        if (path)         [subUI setObject:path         forKey:@"path"];
        if (op)           [subUI setObject:op           forKey:@"op"];
        if (idx !== null) [subUI setObject:idx          forKey:@"index"];

        var subErr = [CPError errorWithDomain:CPCoreDataErrorDomain
                                         code:CPValidationMissingMandatoryPropertyError
                                     userInfo:subUI];
        [detailedErrors addObject:subErr];
    }

    // Top-level error matches CPManagedObjectContext validation error format.
    var ui = [CPMutableDictionary dictionary];
    [ui setObject:apiMsg         forKey:CPLocalizedDescriptionKey];
    [ui setObject:detailedErrors forKey:CPDetailedErrorsKey];

    // Preserve server-specific diagnostics for callers that want them.
    [ui setObject:httpStatus forKey:@"httpStatus"];
    if (url)    [ui setObject:url    forKey:@"url"];
    if (action) [ui setObject:action forKey:@"action"];
    [ui setObject:apiCode forKey:@"api.code"];
    [ui setObject:apiMsg  forKey:@"api.message"];
    if (apiErr && apiErr.requestID)
        [ui setObject:apiErr.requestID forKey:@"api.requestID"];
    if (apiErr && apiErr.errors)
        [ui setObject:apiErr.errors forKey:@"api.errors"];

    return [CPError errorWithDomain:CPCoreDataErrorDomain
                               code:CPValidationMultipleErrorsError
                           userInfo:ui];
}

// - Generic error construction helpers

- (CPError)_cpErrorForOrdersAPIError:(id)apiErr
                          httpStatus:(int)httpStatus
                             message:(CPString)fallbackMessage
                                 url:(CPString)url
                              action:(CPString)action
                        responseText:(CPString)responseText
{
    var domain = (apiErr && apiErr.domain) ? apiErr.domain : @"OrdersAPI";
    var code   = (apiErr && apiErr.code)   ? apiErr.code   : @"unknown";

    var ui = [CPMutableDictionary dictionary];
    [ui setObject:httpStatus forKey:@"httpStatus"];
    if (url)    [ui setObject:url forKey:@"url"];
    if (action) [ui setObject:action forKey:@"action"];
    if (code)   [ui setObject:code forKey:@"api.code"];

    if (apiErr && apiErr.requestID)
        [ui setObject:apiErr.requestID forKey:@"api.requestID"];
    if (apiErr && apiErr.errors)
        [ui setObject:apiErr.errors forKey:@"api.errors"];
    if (apiErr && apiErr.message)
        [ui setObject:apiErr.message forKey:@"api.message"];
    if (responseText)
        [ui setObject:responseText forKey:@"responseText"];

    // Provide a localized description key when available in this runtime
    if (fallbackMessage)
        [ui setObject:fallbackMessage forKey:CPErrorLocalizedDescriptionKey];

    return [CPError errorWithDomain:domain
                               code:httpStatus
                           userInfo:ui];
}

- (CPError)_cpErrorWithDomain:(CPString)domain
                         code:(int)code
                      message:(CPString)message
                    httpStatus:(int)httpStatus
                     apiError:(id)apiErr
                     userInfo:(CPDictionary)extra
{
    var ui = [CPMutableDictionary dictionary];
    if (message)
        [ui setObject:message forKey:CPErrorLocalizedDescriptionKey];

    if (httpStatus)
        [ui setObject:httpStatus forKey:@"httpStatus"];

    if (apiErr)
        [ui setObject:apiErr forKey:@"apiError"];

    if (extra)
    {
        var keys = [extra allKeys];
        for (var i = 0; i < [keys count]; i++)
        {
            var k = [keys objectAtIndex:i];
            [ui setObject:[extra objectForKey:k] forKey:k];
        }
    }

    return [CPError errorWithDomain:(domain || @"CPHTTPStore")
                               code:code
                           userInfo:ui];
}

// - Object ID helpers (unchanged from original)

- (CPString)_globalIDStringForServerID:(id)serverID
{
    var entity, pk;

    if (serverID && serverID.isa && [serverID isKindOfClass:[CPDictionary class]])
    {
        entity = [serverID objectForKey:@"entity"] || @"";
        pk     = [serverID objectForKey:@"pk"]     || {};
    }
    else
    {
        entity = serverID.entity || @"";
        pk     = serverID.pk     || {};
    }

    if (pk && pk.isa && [pk isKindOfClass:[CPDictionary class]])
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
                pk,             @"pk"];
}

- (CPDictionary)_serverIDForObjectID:(CPManagedObjectID)objectID
{
    return [self _serverIDFromGlobalIDString:[objectID globalID]
                                  entityName:[[objectID entity] name]];
}

// - Object materialisation (unchanged)

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
        obj = [entity createObject];
        [obj setContext:context];
        var objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                     globalID:globalID
                                                  isTemporary:NO];
        [objID setPersistentStore:self];
        [obj setObjectID:objID];
    }

    var values    = serverObj.values || serverObj[@"values"] || {},
        propNames = [entity propertyNames];

    for (var vi = 0; vi < [propNames count]; vi++)
    {
        var propName = [propNames objectAtIndex:vi];
        if ([entity isAttributeName:propName] && values.hasOwnProperty(propName))
        {
            var attrDesc   = [[entity attributesByName] objectForKey:propName],
                attrType   = (attrDesc !== nil) ? [attrDesc typeValue] : CPDUndefinedAttributeType,
                coercedVal = [self _coerceJSONValue:values[propName]
                                    toAttributeType:attrType];
            [[obj data] setObject:coercedVal forKey:propName];
        }
    }

    [obj setFault:NO];

    // Cache the attribute snapshot in the coordinator's row cache so that
    // other contexts sharing this coordinator can resolve faults cheaply
    // without a network round-trip.
    var coordinator = [self storeCoordinator];
    if (coordinator !== nil && globalID !== nil)
        [coordinator cacheRowData:[obj data] forGlobalID:globalID];

    return obj;
}

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

    var obj   = [entity createObject];
    var objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:globalID
                                              isTemporary:NO];
    [objID setPersistentStore:self];
    [obj setObjectID:objID];
    [obj setContext:context];
    [obj setFault:YES];
    return obj;
}

- (void)_applyRelationships:(id)relationships
                   toObject:(CPManagedObject)obj
            allMaterialized:(CPDictionary)allMaterialized
                    context:(CPManagedObjectContext)context
{
    if (relationships === nil) return;

    var entity     = [obj entity],
        relsByName = [entity relationshipsByName],
        relKeys    = Object.keys(relationships);

    for (var ri = 0; ri < relKeys.length; ri++)
    {
        var relName = relKeys[ri],
            relDesc = [relsByName objectForKey:relName];
        if (relDesc === nil) continue;

        var relValue = relationships[relName];
        if (relValue === nil || relValue === null)
        {
            [[obj data] setObject:nil forKey:relName];
            [obj noteRelationshipLoaded:relName];
            continue;
        }

        if ([relDesc isToMany])
        {
            var idSet = [[CPMutableSet alloc] init],
                arr;
            if (Array.isArray(relValue))
                arr = relValue;
            else if (relValue !== null && typeof relValue === "object" && !Array.isArray(relValue))
                arr = [relValue];
            else
                arr = [];

            for (var ai = 0; ai < arr.length; ai++)
            {
                var relID = [self _objectIDForServerID:arr[ai]
                                              context:context
                                      allMaterialized:allMaterialized];
                if (relID !== nil)
                {
                    [idSet addObject:relID];

                    // Propagate the inverse to-one relationship on the related
                    // object so it points back to `obj`.  Apple's CoreData
                    // maintains referential integrity automatically; this
                    // mirrors that behaviour so that, e.g., an OrderExpense
                    // fetched via Order.expenses has its `order` navigation
                    // property filled in even when the server did not include
                    // it in the expense's own relationships block.
                    var inverseRelName = [relDesc inversePropertyName];
                    if (inverseRelName !== nil)
                    {
                        var relGlobalID = [relID globalID],
                            relObj = (relGlobalID !== nil)
                                        ? [allMaterialized objectForKey:relGlobalID]
                                        : nil;
                        if (relObj === nil && context !== nil)
                            relObj = [context objectRegisteredForID:relID];

                        if (relObj !== nil)
                        {
                            var relEntity     = [relObj entity],
                                relRelsByName = [relEntity relationshipsByName],
                                inverseDesc   = [relRelsByName objectForKey:inverseRelName];

                            // Only fill a to-one inverse and only when the
                            // server did not already supply a value for it.
                            if (   inverseDesc !== nil
                                && ![inverseDesc isToMany]
                                && [[relObj data] objectForKey:inverseRelName] === nil
                               )
                            {
                                [[relObj data] setObject:[obj objectID] forKey:inverseRelName];
                                [relObj noteRelationshipLoaded:inverseRelName];
                            }
                        }
                    }
                }
            }
            [[obj data] setObject:idSet forKey:relName];
            [obj noteRelationshipLoaded:relName];
        }
        else
        {
            var relID = [self _objectIDForServerID:relValue
                                          context:context
                                  allMaterialized:allMaterialized];
            [[obj data] setObject:relID forKey:relName];
            [obj noteRelationshipLoaded:relName];

            // Propagate the inverse to-many relationship on the related object
            // so it includes `obj`.  This mirrors Apple's CoreData behaviour.
            var inverseRelName = [relDesc inversePropertyName];
            if (inverseRelName !== nil && relID !== nil)
            {
                var relGlobalID = [relID globalID],
                    relObj = (relGlobalID !== nil)
                                ? [allMaterialized objectForKey:relGlobalID]
                                : nil;
                if (relObj === nil && context !== nil)
                    relObj = [context objectRegisteredForID:relID];

                if (relObj !== nil)
                {
                    var relEntity     = [relObj entity],
                        relRelsByName = [relEntity relationshipsByName],
                        inverseDesc   = [relRelsByName objectForKey:inverseRelName];

                    // Only fill a to-many inverse.
                    if (inverseDesc !== nil && [inverseDesc isToMany])
                    {
                        var existingSet = [[relObj data] objectForKey:inverseRelName];
                        if (existingSet === nil || existingSet === null)
                            existingSet = [[CPMutableSet alloc] init];
                        if (![existingSet containsObject:[obj objectID]])
                        {
                            [existingSet addObject:[obj objectID]];
                            [[relObj data] setObject:existingSet forKey:inverseRelName];
                            [relObj noteRelationshipLoaded:inverseRelName];
                        }
                    }
                }
            }
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

    if (allMaterialized !== nil)
    {
        var matObj = [allMaterialized objectForKey:globalID];
        if (matObj !== nil)
            return [matObj objectID];
    }

    if (entity !== nil && context !== nil)
    {
        var searchID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                        globalID:globalID
                                                     isTemporary:NO],
            existing = [context objectRegisteredForID:searchID];
        if (existing !== nil)
            return [existing objectID];
    }

    var newEntity = entity;
    if (newEntity === nil)
    {
        newEntity = [[CPEntityDescription alloc] init];
        [newEntity setName:entityName];
    }
    var newID = [[CPManagedObjectID alloc] initWithEntity:newEntity
                                                 globalID:globalID
                                              isTemporary:NO];
    [newID setPersistentStore:self];
    return newID;
}

// - Object encoding (unchanged)

- (CPDictionary)_encodeObjectForInsert:(CPManagedObject)obj
{
    var result  = [[CPMutableDictionary alloc] init],
        tempKey = [self _tempKeyForObject:obj];

    [result setObject:[CPDictionary dictionaryWithObject:tempKey forKey:@"temp"] forKey:@"id"];
    [result setObject:[[obj entity] name] forKey:@"entity"];

    var valueDict = [[CPMutableDictionary alloc] init],
        relDict   = [[CPMutableDictionary alloc] init];
    [self _encodePropertiesOf:obj values:valueDict relationships:relDict
              changedDataOnly:NO skipUnloadedToMany:NO baselineData:nil];

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

    // Retrieve the last-known server state from the coordinator row cache.
    // Attribute values in _changedData that still equal the cached server value
    // (e.g. re-set by UI bindings during form load) are silently skipped so
    // that only genuinely modified attributes are sent to the server.
    var coordinator  = [self storeCoordinator],
        globalID     = [objID globalID],
        baselineData = (coordinator !== nil && globalID !== nil)
                           ? [coordinator cachedRowDataForGlobalID:globalID]
                           : nil;

    // Only encode properties that were explicitly changed by the application.
    // This ensures:
    //   (a) Only modified fields are sent to the server (not the entire object).
    //   (b) Objects whose only "changes" came from inverse-relationship
    //       maintenance on an unloaded to-many (e.g. a fetched Product gaining
    //       a lineItem reference via the inverse of lineItem.product) produce an
    //       empty payload and are skipped from the update set altogether.
    [self _encodePropertiesOf:obj values:valueDict relationships:relDict
              changedDataOnly:YES skipUnloadedToMany:YES baselineData:baselineData];

    // Nothing actually changed that the server needs to know about.
    if ([valueDict count] == 0 && [relDict count] == 0)
        return nil;

    [result setObject:valueDict forKey:@"values"];
    if ([relDict count] > 0)
        [result setObject:relDict forKey:@"relationships"];

    var version = [[obj data] objectForKey:@"version"];
    if (version !== nil)
        [result setObject:version forKey:@"expectedVersion"];

    return result;
}

- (void)_encodePropertiesOf:(CPManagedObject)obj
                     values:(CPMutableDictionary)valueDict
              relationships:(CPMutableDictionary)relDict
            changedDataOnly:(BOOL)changedDataOnly
        skipUnloadedToMany:(BOOL)skipUnloadedToMany
              baselineData:(CPDictionary)baselineData
{
    var entity      = [obj entity],
        // When encoding only changed properties, read values from _changedData
        // so that only the explicitly-modified fields (and their current values)
        // are included in the update payload sent to the server.
        valueSource = changedDataOnly ? [obj changedData] : [obj data],
        propNames   = changedDataOnly
                          ? [valueSource allKeys]
                          : [entity propertyNames];

    for (var pi = 0; pi < [propNames count]; pi++)
    {
        var propName  = [propNames objectAtIndex:pi],
            propValue = [valueSource objectForKey:propName];

        if ([entity isAttributeName:propName])
        {
            if (propValue !== nil)
            {
                // When a baseline (coordinator row cache) is available, skip
                // attribute values that haven't actually changed from the last
                // server-fetched state.  This prevents spurious updates caused
                // by UI bindings that re-set a field to its existing value.
                if (changedDataOnly && baselineData !== nil)
                {
                    var baselineValue = [baselineData objectForKey:propName];
                    if ([self _valuesAreEqual:propValue and:baselineValue])
                        continue;
                }
                [valueDict setObject:propValue forKey:propName];
            }
        }
        else if ([entity isRelationshipName:propName])
        {
            if (propValue === nil) continue;

            var relDesc = [[entity relationshipsByName] objectForKey:propName];
            if ([relDesc isToMany])
            {
                // Skip to-many relationships that were never loaded from the
                // server on updated objects.  Their content is incomplete
                // (only items added client-side via inverse maintenance) so
                // encoding them would overwrite the authoritative server-side
                // collection with a partial set.
                if (skipUnloadedToMany && ![obj isRelationshipLoaded:propName])
                    continue;

                var refs    = [[CPMutableArray alloc] init],
                    relEnum = nil,
                    relItem;

                if ([propValue isKindOfClass:[CPSet class]] || [propValue isKindOfClass:[CPArray class]])
                    relEnum = [propValue objectEnumerator];
                else if (propValue !== nil)
                    CPLog.warn(@"CPHTTPStore: unexpected to-many value type for '" + propName + @"'; skipping");

                if (relEnum !== nil)
                {
                    while ((relItem = [relEnum nextObject]))
                    {
                        if ([relItem isKindOfClass:[CPManagedObjectID class]])
                            [refs addObject:[self _refForObjectID:relItem]];
                    }
                }
                if ([refs count] > 0)
                    [relDict setObject:refs forKey:propName];
            }
            else
            {
                var relIDObj = ([propValue isKindOfClass:[CPManagedObject class]])
                                    ? [propValue objectID]
                                    : propValue;
                if ([relIDObj isKindOfClass:[CPManagedObjectID class]])
                    [relDict setObject:[self _refForObjectID:relIDObj] forKey:propName];
            }
        }
    }
}

- (CPDictionary)_refForObjectID:(CPManagedObjectID)objectID
{
    // Use the temp key when the ID is temporary OR when it has no server-assigned
    // globalID yet (i.e. obtainPermanentIDsForObjects: promoted isTemporary→NO
    // as a placeholder, but the server hasn't responded with a real ID yet).
    if ([objectID isTemporary] || ![objectID validatedGlobalID])
        return [CPDictionary dictionaryWithObject:[self _tempKeyForObjectID:objectID]
                                           forKey:@"temp"];
    return [self _serverIDForObjectID:objectID];
}

/*!
    Compare two property values for equality.

    Handles nil, ObjJ objects (via isEqual:), and JS primitives (via ===).
    Used to detect whether an attribute value in _changedData has actually
    changed relative to the last-known server state (baseline).
*/
- (BOOL)_valuesAreEqual:(id)a and:(id)b
{
    if (a === b)
        return YES;
    if (a === nil || a === null || a === undefined)
        return (b === nil || b === null || b === undefined);
    if (b === nil || b === null || b === undefined)
        return NO;
    // Use isEqual: for ObjJ objects (handles CPDate, CPString, etc.)
    if (typeof a === 'object' && [a respondsToSelector:@selector(isEqual:)])
        return [a isEqual:b];
    return NO;
}

/*!
    Promote the temporary IDs of newly-inserted objects to permanent
    placeholder IDs without a server round-trip.

    This is called by CPManagedObjectContext before validation runs.
    Setting isTemporary = NO makes _validateForChanges treat inserted objects
    the same as existing objects: it skips nil-checks for attributes that were
    never explicitly set by the application (such as server-assigned primary
    keys).  The globalID remains nil until the server responds after the save
    and idMap assigns the real IDs.

    @param objects  A CPSet of CPManagedObject instances about to be inserted.
    @param error    Unused; provided for API symmetry with Apple's
                    NSIncrementalStore -obtainPermanentIDsForObjects:error:.
    @return YES always.
*/
- (BOOL)obtainPermanentIDsForObjects:(CPSet)objects error:(@ref)error
{
    var e = [objects objectEnumerator],
        obj;
    while ((obj = [e nextObject]))
    {
        var objectID = [obj objectID];
        if (objectID !== nil && [objectID isTemporary])
            [objectID setIsTemporary:NO];
    }
    return YES;
}

- (CPString)_tempKeyForObject:(CPManagedObject)obj
{
    return [self _tempKeyForObjectID:[obj objectID]];
}

- (CPString)_tempKeyForObjectID:(CPManagedObjectID)objectID
{
    return @"t_" + [objectID localID];
}

// - JSON conversion helper (unchanged)

- (id)_toNativeObject:(id)obj
{
    if (obj === nil || obj === null || obj === undefined)
        return null;

    var t = typeof obj;
    if (t === "boolean" || t === "number" || t === "string")
        return obj;

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

    if ([obj isKindOfClass:[CPDate class]])
    {
        var jsDate = new Date([obj timeIntervalSince1970] * 1000.0);
        return jsDate.toISOString();
    }

    if ([obj isKindOfClass:[CPNumber class]])
        return [obj doubleValue];

    return obj;
}

/*!
    Coerce a raw JSON wire value to the Cappuccino type dictated by the
    attribute's CPD*AttributeType.  Currently handles:
      - CPDDateAttributeType  : number (Unix epoch seconds) or ISO-8601 string
                                → CPDate
    All other types are returned unchanged (JSON number / string / boolean
    map directly to their ObjJ equivalents).
*/
- (id)_coerceJSONValue:(id)value toAttributeType:(int)attrType
{
    if (value === nil || value === null || value === undefined)
        return value;

    if (attrType === CPDDateAttributeType)
    {
        if ([value isKindOfClass:[CPDate class]])
            return value;

        if (typeof value === "number")
            return [CPDate dateWithTimeIntervalSince1970:value];

        if (typeof value === "string" && value.length > 0)
        {
            var jsDate = new Date(value);
            if (!isNaN(jsDate.getTime()))
                return [CPDate dateWithTimeIntervalSince1970:jsDate.getTime() / 1000.0];
            CPLog.warn(@"CPHTTPStore: could not parse date string '" + value + @"'; storing raw value");
        }
    }

    return value;
}

@end


// ---------------------------------------------------------------------------
// CPHTTPStoreRequest
//
// Per-request state holder that acts as its own CPURLConnection delegate.
// Decoupling per-request state from the store lets multiple requests be
// dispatched concurrently without clobbering each other.
//
// completionHandler signature:  function(httpDict, transportError)
//   httpDict       — CPDictionary{ @"statusCode", @"text", @"url" } on success
//   transportError — non-nil on transport-level failure (httpDict is nil)
// ---------------------------------------------------------------------------

@implementation CPHTTPStoreRequest : CPObject
{
    CPString _requestURL;
    Function _completionHandler;
    int      _statusCode;
    CPString _responseText;
}

+ (CPHTTPStoreRequest)requestWithURL:(CPString)url
                   completionHandler:(Function)handler
{
    var r              = [[CPHTTPStoreRequest alloc] init];
    r._requestURL      = url;
    r._completionHandler = handler;
    r._statusCode      = 0;
    r._responseText    = [[CPString alloc] init];
    return r;
}

- (void)connection:(CPURLConnection)connection
    didReceiveResponse:(CPHTTPURLResponse)response
{
    _statusCode   = [response respondsToSelector:@selector(statusCode)] ? [response statusCode] : 0;
    _responseText = [[CPString alloc] init];
}

- (void)connection:(CPURLConnection)connection
      didReceiveData:(id)data
{
    if (data !== nil)
        _responseText = [_responseText stringByAppendingString:data];
}

- (void)connectionDidFinishLoading:(CPURLConnection)connection
{
    if (_completionHandler)
    {
        _completionHandler(
            [CPDictionary dictionaryWithObjectsAndKeys:
                 _statusCode,                                   @"statusCode",
                 [CPString stringWithString:_responseText],     @"text",
                 _requestURL,                                   @"url"],
            nil
        );
        _completionHandler = nil;
    }
}

- (void)connection:(CPURLConnection)connection
   didFailWithError:(id)error
{
    if (_completionHandler)
    {
        _completionHandler(nil, error);
        _completionHandler = nil;
    }
}

@end
