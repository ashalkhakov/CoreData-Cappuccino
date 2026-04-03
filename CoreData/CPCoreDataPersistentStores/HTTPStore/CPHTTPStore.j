//
//  CPHTTPStore.j
//
//  HTTP-backed persistent store targeting the OrdersAPI cdFetch / cdSave
//  endpoints.
//
//  Adds HTTP status-aware transport and proper error propagation
//  for non-200 responses (400, 409, 422) using CPURLConnection delegate API.
//
//  422 handling: map OrdersAPI error JSON into CoreData-like validation errors.
//
//  Notes
//  -----
//  - The Foundation-provided CPURLConnection synchronous helper does NOT expose
//    HTTP status codes (it returns CPData only), so we implement our own
//    "sync" wrapper around the async delegate callbacks by spinning the run loop.
//  - On non-200: parse OrdersAPI error JSON if present, populate the `error`
//    out-param, and raise an exception (CoreData-like failure behaviour).
//

@import <Foundation/Foundation.j>
@import "../../CPPersistentStore.j"
@import "../../CPPersistentStoreType.j"
@import "CPHTTPStoreType.j"
@import "CPHTTPPredicateEncoder.j"

CPErrorLocalizedDescriptionKey = @"CPErrorLocalizedDescriptionKey";

@implementation CPHTTPStore : CPPersistentStore
{
    // Transport state for our synchronous wrapper
    CPURLConnection  _activeConnection;
    int             _activeStatusCode;
    id              _activeResponse;     // CPHTTPURLResponse (or CPURLResponse)
    CPString        _activeResponseText;
    BOOL            _activeDone;
    id              _activeTransportError;
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
                                 depth,             @"depth"]
                     forKey:@"include"];
        }
    }

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

// - HTTP transport (status-aware)

/*!
    POST JSON body to a URL and return a dictionary:
        { statusCode: <int>, text: <string>, url: <string> }

    On transport-level failure (no response), sets *error and raises.
*/
- (CPDictionary)_postJSONAndReturnHTTPResult:(id)bodyDict
                                      toURL:(CPString)urlString
                                      error:(@ref)error
{
    // Serialize body
    var jsonString;
    try
    {
        jsonString = JSON.stringify([self _toNativeObject:bodyDict]);
    }
    catch (e)
    {
        if (error)
            @deref(error) = [self _cpErrorWithDomain:@"CPHTTPStore"
                                                code:1001
                                             message:@"JSON serialisation error"
                                          httpStatus:0
                                            apiError:nil
                                            userInfo:@{ @"exception": String(e) }];
        [self _raiseForError:error message:@"CPHTTPStore: JSON serialisation error"];
        return nil;
    }

    // Build request
    var url = [CPURL URLWithString:urlString],
        req = [CPURLRequest requestWithURL:url];

    [req setHTTPMethod:@"POST"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setHTTPBody:jsonString];

    // Reset state
    _activeConnection     = nil;
    _activeStatusCode     = 0;
    _activeResponse       = nil;
    _activeResponseText   = [[CPString alloc] init];
    _activeDone           = NO;
    _activeTransportError = nil;

    // Fire async request
    _activeConnection = [CPURLConnection connectionWithRequest:req delegate:self];

    // "Synchronous" wait: spin run loop until delegate marks done
    var runLoop = [CPRunLoop currentRunLoop];
    while (!_activeDone)
        [runLoop limitDateForMode:CPDefaultRunLoopMode];

    // Transport failure?
    if (_activeTransportError !== nil)
    {
        if (error)
            error = [self _cpErrorWithDomain:@"CPHTTPStore"
                                        code:1002
                                     message:@"Transport error"
                                   httpStatus:0
                                    apiError:nil
                                    userInfo:@{ @"transportError": _activeTransportError,
                                                @"url": urlString }];
        [self _raiseForError:error message:@"CPHTTPStore: transport error"];
        return nil;
    }

    return [CPDictionary dictionaryWithObjectsAndKeys:
                _activeStatusCode, @"statusCode",
                [CPString stringWithString:_activeResponseText], @"text",
                urlString, @"url"];
}

- (void)connection:(CPURLConnection)connection didReceiveResponse:(CPHTTPURLResponse)response
{
    _activeResponse = response;
    _activeStatusCode = [response respondsToSelector:@selector(statusCode)] ? [response statusCode] : 0;
}

- (void)connection:(CPURLConnection)connection didReceiveData:(id)data
{
    // data is a string for CPURLConnection in this runtime
    if (data !== nil)
        [_activeResponseText appendString:data];
}

- (void)connectionDidFinishLoading:(CPURLConnection)connection
{
    _activeDone = YES;
}

- (void)connection:(CPURLConnection)connection didFailWithError:(id)err
{
    _activeTransportError = err;
    _activeDone = YES;
}

/*!
    Parse OrdersAPI JSON from an HTTP result, and convert non-200 / ok:false
    into CPError + exception.

    For 422 specifically: create CoreData-like validation error(s) based on the
    OrdersAPI `error.errors[]` array (entity, temp/id, path, kind, message, op, index).

    Returns parsed JS object on success (HTTP 200 and parsed.ok == true).
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
                error = [self _cpCoreDataValidationErrorFromOrdersAPIError:apiErr
                                                                httpStatus:422
                                                                       url:url
                                                                    action:action
                                                              responseText:text];

            [self _raiseForError:error message:@"CPHTTPStore: validation failed (422)"];
            return nil;
        }

        if (error)
            error = [self _cpErrorForOrdersAPIError:apiErr
                                         httpStatus:statusCode
                                            message:(apiErr && apiErr.message) ? apiErr.message : @"HTTP error"
                                               url:url
                                            action:action
                                      responseText:text];

        [self _raiseForError:error
                     message:@"CPHTTPStore: server returned non-200"];
        return nil;
    }

    // HTTP 200 but body is not valid JSON
    if (!parsed)
    {
        if (error)
            error = [self _cpErrorWithDomain:@"CPHTTPStore"
                                        code:1100
                                     message:@"Invalid JSON from server"
                                   httpStatus:200
                                    apiError:nil
                                    userInfo:@{ @"url": url,
                                                @"action": action,
                                                @"responseText": text }];
        [self _raiseForError:error message:@"CPHTTPStore: invalid JSON"];
        return nil;
    }

    // HTTP 200 but ok:false: treat as error
    if (!parsed.ok)
    {
        var apiErr = parsed.error || nil;

        // Some servers may return ok:false with 200; if domain suggests validation,
        // we still want CoreData-like validation errors.
        var isValidation = apiErr && apiErr.domain && (apiErr.domain === "Validation");
        if (isValidation)
        {
            if (error)
                error = [self _cpCoreDataValidationErrorFromOrdersAPIError:apiErr
                                                                httpStatus:200
                                                                       url:url
                                                                    action:action
                                                              responseText:text];
            [self _raiseForError:error message:@"CPHTTPStore: validation failed (ok:false)"];
            return nil;
        }

        if (error)
            error = [self _cpErrorForOrdersAPIError:apiErr
                                         httpStatus:200
                                            message:(apiErr && apiErr.message) ? apiErr.message : @"Server error"
                                               url:url
                                            action:action
                                      responseText:text];

        [self _raiseForError:error message:@"CPHTTPStore: ok:false"];
        return nil;
    }

    return parsed;
}

// - 422 / validation mapping

/*!
    Convert OrdersAPI 422 payload into a CoreData-like validation error.

    OrdersAPI error envelope shape:
      { domain, code, message, requestID, errors:[ {entity, kind, message, path, temp, id, op, index}, ... ] }

    We generate:
      - a top-level CPError with domain=apiErr.domain (e.g. "Validation" or "Persistence")
        code=422
      - userInfo contains:
          - httpStatus, url, action, api.code, api.requestID, api.message
          - api.errors  (original array)
          - coredata.validationErrors: array of per-field error dictionaries
            (best-effort mapping)
          - coredata.affectedEntities: grouping by entity/temp/id

    This is intentionally “CoreData-like” but not a perfect clone; it gives your
    client enough structured information to show field errors and decide which
    managed object failed (using temp/id/entity).
*/
- (CPError)_cpCoreDataValidationErrorFromOrdersAPIError:(id)apiErr
                                            httpStatus:(int)httpStatus
                                                   url:(CPString)url
                                                action:(CPString)action
                                          responseText:(CPString)responseText
{
    var domain = (apiErr && apiErr.domain) ? apiErr.domain : @"Validation";
    var apiCode = (apiErr && apiErr.code) ? apiErr.code : @"validation_failed";
    var apiMsg  = (apiErr && apiErr.message) ? apiErr.message : @"Validation failed";

    var ui = [CPMutableDictionary dictionary];
    [ui setObject:httpStatus forKey:@"httpStatus"];
    if (url)    [ui setObject:url forKey:@"url"];
    if (action) [ui setObject:action forKey:@"action"];
    [ui setObject:apiCode forKey:@"api.code"];
    [ui setObject:apiMsg  forKey:@"api.message"];

    if (apiErr && apiErr.requestID)
        [ui setObject:apiErr.requestID forKey:@"api.requestID"];

    if (apiErr && apiErr.errors)
        [ui setObject:apiErr.errors forKey:@"api.errors"];

    if (responseText)
        [ui setObject:responseText forKey:@"responseText"];

    // Build per-item validation errors
    var vErrs = [[CPMutableArray alloc] init];
    var affected = [CPMutableDictionary dictionary]; // key -> {entity,temp,id,errors:[]}

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

        var entry = @{
            @"entity": ent,
            @"temp": temp,
            @"id": gid,
            @"kind": kind,
            @"message": msg,
            @"path": path,
            @"property": propertyName,
            @"op": op,
            @"index": idx
        };
        [vErrs addObject:entry];

        // Group by entity+temp/id
        var key = ent + @"|" + (temp ? ("temp=" + temp) : (gid ? ("id=" + JSON.stringify(gid)) : "unknown"));
        var bucket = [affected objectForKey:key];
        if (!bucket)
        {
            bucket = [CPMutableDictionary dictionary];
            [bucket setObject:ent forKey:@"entity"];
            if (temp) [bucket setObject:temp forKey:@"temp"];
            if (gid)  [bucket setObject:gid  forKey:@"id"];
            [bucket setObject:[CPMutableArray array] forKey:@"errors"];
            [affected setObject:bucket forKey:key];
        }
        [[bucket objectForKey:@"errors"] addObject:entry];
    }

    [ui setObject:vErrs forKey:@"coredata.validationErrors"];
    [ui setObject:affected forKey:@"coredata.affectedEntities"];

    // Top-level error uses HTTP code as code, domain from server
    // (so callers can distinguish Validation vs Persistence vs Conflict etc.)
    return [CPError errorWithDomain:domain code:httpStatus userInfo:ui];
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

- (void)_raiseForError:(CPError)err message:(CPString)msg
{
    var info = [CPMutableDictionary dictionary];
    if (err) [info setObject:err forKey:@"error"];
    if (msg) [info setObject:msg forKey:@"message"];

    [CPException raise:@"CPHTTPStoreError" reason:(msg || @"CPHTTPStore error") userInfo:info];
}

// - Object ID helpers (unchanged from original)

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
    [newID setStore:self];
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

    if ([obj isKindOfClass:[CPNumber class]])
        return [obj doubleValue];

    return obj;
}

@end
