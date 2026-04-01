//
//  CPHTTPIncrementalStore.j
//
//  HTTP incremental persistent store for Cappuccino CoreData.
//  Talks to OrderFlow backend OrdersAPI endpoints /cdFetch and /cdSave.
//
//  Backend contract
//  ────────────────
//  POST /cdFetch  { entity, predicate?, sort?, limit?, offset?, include?, return }
//      response (graph mode): { ok, root:[{entity,pk},...], objectsByID:{<key>:{id,entity,values,relationships},...} }
//      response (IDs-only):   { ok, root:[{entity,pk},...] }
//
//  POST /cdSave   { inserted:[{id,entity,values,relationships},...], updated:[...], deleted:[...], return }
//      response: { ok, objects:[...], versions:[...], idMap:{tempKey:{entity,pk},...}, idMapByRef:{} }
//
//  Global-ID string format (stable, reversible):
//      "EntityName|pkKey1=jsonVal1;pkKey2=jsonVal2;"   (keys sorted alphabetically)
//

@import <Foundation/Foundation.j>

// Prefix used when encoding a temporary (client-side) object ID for the server.
CPHTTPIncrementalStoreTempIDPrefix = "t_";

// Conversion factor: JavaScript Date.getTime() returns milliseconds; the server
// expects Unix epoch seconds.
CPHTTPIncrementalStoreMillisecondsPerSecond = 1000.0;


@implementation CPHTTPIncrementalStore : CPPersistentStore
{
}


// ─── Configuration ───────────────────────────────────────────────────────────

- (CPString)baseURL
{
    if (_configuration != nil)
    {
        var result = [_configuration objectForKey:CPHTTPIncrementalStoreConfigurationKeyBaseURL];
        if (result != nil && [result length] > 0)
        {
            var lastChar = [result characterAtIndex:[result length] - 1];
            if (![lastChar isEqualToString:@"/"])
                result = result + @"/";
        }
        return result;
    }
    return nil;
}

- (void)setConfiguration:(CPDictionary)configuration
{
    _configuration = configuration;
}

- (CPDictionary)configuration
{
    return _configuration;
}


// ─── Global-ID encoding / decoding ───────────────────────────────────────────

/*!
    Encode a server {entity, pk} pair into a stable globalID string.
    Format: "EntityName|pkKey1=jsonVal1;pkKey2=jsonVal2;"  (keys sorted alphabetically).
    pk is a plain JavaScript object.
*/
- (CPString)_globalIDStringForEntity:(CPString)entityName pk:(id)pk
{
    var keys = Object.keys(pk).sort();
    var result = entityName + "|";
    var i;
    for (i = 0; i < keys.length; i++)
    {
        var k = keys[i];
        var v = pk[k];
        result = result + k + "=" + JSON.stringify(v) + ";";
    }
    return result;
}

/*!
    Decode a globalID string back to a plain JS object {entity, pk}.
    Returns nil if the string is not in the expected format.
*/
- (id)_entityAndPKFromGlobalIDString:(CPString)idString
{
    var rawString = [idString rawString] || idString;
    var pipeIdx = rawString.indexOf("|");
    if (pipeIdx < 0)
        return nil;

    var entityName = rawString.substring(0, pipeIdx);
    var rest       = rawString.substring(pipeIdx + 1);
    var pk         = {};
    var parts      = rest.split(";");
    var i;
    for (i = 0; i < parts.length; i++)
    {
        var part = parts[i];
        if (part.length === 0) continue;
        var eqIdx = part.indexOf("=");
        if (eqIdx < 0) continue;
        var key    = part.substring(0, eqIdx);
        var valStr = part.substring(eqIdx + 1);
        var val;
        try { val = JSON.parse(valStr); } catch (e) { val = valStr; }
        pk[key] = val;
    }
    return {entity: entityName, pk: pk};
}

/*!
    Build a server ID JS object {entity, pk} from a globalID string.
*/
- (id)_serverIDFromGlobalIDString:(CPString)gid
{
    var decoded = [self _entityAndPKFromGlobalIDString:gid];
    if (decoded == nil) return nil;
    return {entity: decoded.entity, pk: decoded.pk};
}


// ─── Object-ID helpers ───────────────────────────────────────────────────────

/*!
    Create a CPManagedObjectID for a server ID dictionary {entity, pk}.
    The serverID argument may be a CPDictionary (from a parsed JSON response)
    or a plain JS object.
*/
- (CPManagedObjectID)_objectIDForServerID:(id)serverID inContext:(CPManagedObjectContext)aContext
{
    var entityName, pk;
    if ([serverID isKindOfClass:[CPDictionary class]])
    {
        entityName = [serverID objectForKey:@"entity"];
        var pkDict = [serverID objectForKey:@"pk"];
        pk = [pkDict JSObject] !== undefined ? [pkDict JSObject] : pkDict;
    }
    else
    {
        entityName = serverID.entity;
        pk = serverID.pk;
    }

    if (entityName == nil || pk == nil)
        return nil;

    var entity = [[aContext model] entityWithName:entityName];
    if (entity == nil)
    {
        CPLog.warn(@"CPHTTPIncrementalStore: unknown entity '%@'", entityName);
        return nil;
    }

    var gid    = [self _globalIDStringForEntity:entityName pk:pk];
    var objID  = [[CPManagedObjectID alloc] initWithEntity:entity globalID:gid isTemporary:NO];
    [objID setStore:self];
    return objID;
}


// ─── Object materialisation ──────────────────────────────────────────────────

/*!
    Create a CPManagedObject from a server snapshot CPDictionary.
    The snapshot has the shape: {id, entity, values, relationships}.
*/
- (CPManagedObject)_materialiseSnapshot:(CPDictionary)snap inContext:(CPManagedObjectContext)aContext
{
    var entityName = [snap objectForKey:@"entity"];
    var entity     = [[aContext model] entityWithName:entityName];
    if (entity == nil)
    {
        CPLog.warn(@"CPHTTPIncrementalStore: unknown entity '%@' in snapshot", entityName);
        return nil;
    }

    var serverID = [snap objectForKey:@"id"];
    var objID    = [self _objectIDForServerID:serverID inContext:aContext];
    if (objID == nil)
        return nil;

    var obj = [[CPManagedObject alloc] init];
    [obj setEntity:entity];
    [obj setObjectID:objID];
    [obj setStore:self];

    var data = [[CPMutableDictionary alloc] init];

    // Attributes
    var values = [snap objectForKey:@"values"];
    if (values != nil)
    {
        var attrsByName = [entity attributesByName];
        var attrKeys    = [attrsByName allKeys];
        var i;
        for (i = 0; i < [attrKeys count]; i++)
        {
            var aKey = [attrKeys objectAtIndex:i];
            var aVal = [values objectForKey:aKey];
            if (aVal != nil)
                [data setObject:aVal forKey:aKey];
        }
    }

    // Relationships – store as CPManagedObjectID (or CPMutableSet for to-many)
    var relationships = [snap objectForKey:@"relationships"];
    if (relationships != nil)
    {
        var relsByName = [entity relationshipsByName];
        var relKeys    = [relsByName allKeys];
        var i;
        for (i = 0; i < [relKeys count]; i++)
        {
            var relName = [relKeys objectAtIndex:i];
            var relDef  = [relsByName objectForKey:relName];
            var relVal  = [relationships objectForKey:relName];
            if (relVal == nil) continue;

            if ([relDef isToMany])
            {
                var relSet = [[CPMutableSet alloc] init];
                var arr;
                if ([relVal isKindOfClass:[CPArray class]])
                    arr = relVal;
                else
                    arr = [relVal allObjects];

                var j;
                for (j = 0; j < [arr count]; j++)
                {
                    var relObjID = [self _objectIDForServerID:[arr objectAtIndex:j] inContext:aContext];
                    if (relObjID != nil)
                        [relSet addObject:relObjID];
                }
                [data setObject:relSet forKey:relName];
            }
            else
            {
                var relObjID = [self _objectIDForServerID:relVal inContext:aContext];
                if (relObjID != nil)
                    [data setObject:relObjID forKey:relName];
            }
        }
    }

    [obj _setData:data];
    [obj _setChangedData:[[CPMutableDictionary alloc] init]];
    return obj;
}


// ─── Predicate encoding ──────────────────────────────────────────────────────

/*!
    Encode a CPPredicate (or raw CPDictionary AST) to the server AST format.

    Supported cases:
      - CPDictionary: passed through as-is (raw AST from the caller).
      - nil: returns nil (no predicate filter).
      - Other CPPredicate: logs a warning and returns nil
        (the server will return all objects for the entity).

    Callers that need predicate filtering should pass a CPDictionary with the
    server AST directly, e.g.:
        [fetchRequest setPredicate:[CPDictionary dictionaryWithJSObject:
            {op:"beginswith", key:"fullName", value:"I"} recursively:YES]];
*/
- (id)_encodePredicate:(id)predicate
{
    if (predicate == nil)
        return nil;

    if ([predicate isKindOfClass:[CPDictionary class]])
    {
        // Raw AST dictionary – convert to plain JS object for JSON serialisation.
        var result = {};
        var keys   = [predicate allKeys];
        var i;
        for (i = 0; i < [keys count]; i++)
        {
            var k = [keys objectAtIndex:i];
            var v = [predicate objectForKey:k];
            result[[k rawString] || k] = v;
        }
        return result;
    }

    CPLog.warn(@"CPHTTPIncrementalStore: unsupported CPPredicate type; predicate will be ignored");
    return nil;
}


// ─── HTTP helpers ────────────────────────────────────────────────────────────

/*!
    POST bodyObject (serialised as JSON) to path (relative to baseURL).
    Returns the parsed JSON response object, or nil on network / parse error.
*/
- (id)_sendPostToPath:(CPString)path body:(id)bodyObject
{
    var baseURL = [self baseURL];
    if (baseURL == nil)
    {
        CPLog.error(@"CPHTTPIncrementalStore: no base URL configured");
        return nil;
    }

    var urlString  = baseURL + path;
    var bodyString = JSON.stringify(bodyObject);

    var request = [CPURLRequest requestWithURL:urlString];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[bodyString rawString]];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    CPLog.debug(@"CPHTTPIncrementalStore POST %@ : %@", urlString, bodyString);

    var data = [CPURLConnection sendSynchronousRequest:request returningResponse:nil];
    if (data == nil)
    {
        CPLog.error(@"CPHTTPIncrementalStore: no response from %@", urlString);
        return nil;
    }

    var responseString = [data description];
    CPLog.debug(@"CPHTTPIncrementalStore response: %@", responseString);

    try
    {
        return JSON.parse(responseString);
    }
    catch (e)
    {
        CPLog.error(@"CPHTTPIncrementalStore: failed to parse JSON response: %@", e);
        return nil;
    }
}


// ─── Save encoding helpers ───────────────────────────────────────────────────

/*!
    Encode a CPManagedObject as a server save-payload entry.
    tempIDMap is a CPMutableDictionary mapping localID (string) → temp key (string).
    If the object has a temporary ID, a new temp key ("t_" + localID) is registered.
*/
- (id)_encodeObjectForSave:(CPManagedObject)obj tempIDMap:(CPMutableDictionary)tempIDMap
{
    var objID      = [obj objectID];
    var entityName = [[obj entity] name];
    var result     = {};

    // ID
    if ([objID isTemporary] || ![objID validatedGlobalID])
    {
        var localID  = [objID localID];
        var tempKey  = CPHTTPIncrementalStoreTempIDPrefix + localID;
        [tempIDMap setObject:tempKey forKey:localID];
        result.id = {temp: tempKey};
    }
    else
    {
        result.id = [self _serverIDFromGlobalIDString:[objID globalID]];
    }

    result.entity = entityName;

    // Attribute values
    var data        = [obj data];
    var attrsByName = [[obj entity] attributesByName];
    var attrKeys    = [attrsByName allKeys];
    var values      = {};
    var i;
    for (i = 0; i < [attrKeys count]; i++)
    {
        var aKey = [attrKeys objectAtIndex:i];
        var aVal = [data objectForKey:aKey];
        if (aVal != nil && aVal !== CPNull)
        {
            if ([aVal isKindOfClass:[CPDate class]])
                values[[aKey rawString] || aKey] = aVal.getTime() / CPHTTPIncrementalStoreMillisecondsPerSecond;
            else
                values[[aKey rawString] || aKey] = aVal;
        }
    }
    result.values = values;

    // Relationships
    var relsByName     = [[obj entity] relationshipsByName];
    var relKeys        = [relsByName allKeys];
    var relationships  = {};
    var hasRel         = NO;
    for (i = 0; i < [relKeys count]; i++)
    {
        var relName = [relKeys objectAtIndex:i];
        var relDef  = [relsByName objectForKey:relName];
        var relVal  = [data objectForKey:relName];
        if (relVal == nil) continue;

        hasRel = YES;
        if ([relDef isToMany])
        {
            var arr    = [];
            var relArr;
            if ([relVal isKindOfClass:[CPSet class]])
                relArr = [relVal allObjects];
            else if ([relVal isKindOfClass:[CPArray class]])
                relArr = relVal;
            else
                relArr = [CPArray arrayWithObject:relVal];

            var j;
            for (j = 0; j < [relArr count]; j++)
            {
                var ref = [self _encodeObjectRef:[relArr objectAtIndex:j] tempIDMap:tempIDMap];
                if (ref != nil)
                    arr.push(ref);
            }
            relationships[[relName rawString] || relName] = arr;
        }
        else
        {
            var ref = [self _encodeObjectRef:relVal tempIDMap:tempIDMap];
            if (ref != nil)
                relationships[[relName rawString] || relName] = ref;
        }
    }
    if (hasRel)
        result.relationships = relationships;

    return result;
}

/*!
    Encode a relationship target (CPManagedObjectID or CPManagedObject) as a
    server reference.  Temp IDs are encoded as {temp: "t_xxx"}; permanent IDs
    as {entity, pk}.
*/
- (id)_encodeObjectRef:(id)ref tempIDMap:(CPMutableDictionary)tempIDMap
{
    var objID;
    if ([ref isKindOfClass:[CPManagedObjectID class]])
        objID = ref;
    else if ([ref isKindOfClass:[CPManagedObject class]])
        objID = [ref objectID];
    else
        return nil;

    if ([objID isTemporary] || ![objID validatedGlobalID])
    {
        var localID = [objID localID];
        var tempKey = [tempIDMap objectForKey:localID];
        if (tempKey == nil)
        {
            tempKey = CPHTTPIncrementalStoreTempIDPrefix + localID;
            [tempIDMap setObject:tempKey forKey:localID];
        }
        return {temp: tempKey};
    }
    else
    {
        return [self _serverIDFromGlobalIDString:[objID globalID]];
    }
}


// ─── CPPersistentStore overrides ─────────────────────────────────────────────

/*!
    HTTP incremental stores fetch on demand; return an empty set here so the
    context does not try to bulk-load everything at initialisation time.
*/
- (CPSet)loadAll:(CPDictionary)properties
inManagedObjectContext:(CPManagedObjectContext)aContext
           error:(CPError)error
{
    CPLog.debug(@"CPHTTPIncrementalStore: loadAll – incremental store, returning empty set");
    return [CPSet new];
}

/*!
    saveAll is not used by the incremental store; saveObjectsUpdated:inserted:deleted:
    handles persistence.
*/
- (void)saveAll:(CPSet)objects error:(CPError)error
{
    CPLog.debug(@"CPHTTPIncrementalStore: saveAll – not used by incremental store");
}


// ─── executeFetchRequest → POST /cdFetch ─────────────────────────────────────

/*!
    Execute a fetch request against the OrdersAPI /cdFetch endpoint.

    The returned CPSet contains CPManagedObject instances materialised from
    the server response (graph mode).  IDs-only mode is logged but not yet
    materialised (the context will request individual objects as needed).
*/
- (CPSet)executeFetchRequest:(CPFetchRequest)aFetchRequest
      inManagedObjectContext:(CPManagedObjectContext)aContext
                       error:(CPError)error
{
    var entityName = [[aFetchRequest entity] name];
    var body       = {entity: entityName};

    // Predicate
    var predicate = [aFetchRequest predicate];
    if (predicate != nil)
    {
        var encodedPredicate = [self _encodePredicate:predicate];
        if (encodedPredicate != nil)
            body.predicate = encodedPredicate;
    }

    // Sort descriptors
    var sortDescriptors = [aFetchRequest sortDescriptors];
    if (sortDescriptors != nil && [sortDescriptors count] > 0)
    {
        var sort = [];
        var i;
        for (i = 0; i < [sortDescriptors count]; i++)
        {
            var sd = [sortDescriptors objectAtIndex:i];
            sort.push({key: [sd key], dir: [sd ascending] ? "asc" : "desc"});
        }
        body.sort = sort;
    }

    // Limit / offset
    if ([aFetchRequest fetchLimit] > 0)
        body.limit = [aFetchRequest fetchLimit];
    if ([aFetchRequest fetchOffset] > 0)
        body.offset = [aFetchRequest fetchOffset];

    body["return"] = {onlyIDs: false};

    var response = [self _sendPostToPath:@"cdFetch" body:body];
    if (response == nil || !response.ok)
    {
        CPLog.error(@"CPHTTPIncrementalStore: cdFetch failed for entity '%@'", entityName);
        return [CPSet new];
    }

    var resultSet    = [[CPMutableSet alloc] init];
    var objectsByID  = response.objectsByID;

    if (objectsByID != nil)
    {
        // Graph mode – materialise each snapshot
        var ids = Object.keys(objectsByID);
        var i;
        for (i = 0; i < ids.length; i++)
        {
            var snap     = objectsByID[ids[i]];
            var snapDict = [CPDictionary dictionaryWithJSObject:snap recursively:YES];
            var obj      = [self _materialiseSnapshot:snapDict inContext:aContext];
            if (obj != nil)
                [resultSet addObject:obj];
        }
    }
    else if (response.root != nil)
    {
        CPLog.debug(@"CPHTTPIncrementalStore: cdFetch returned IDs-only mode; "
                  + @"objects will be fetched on demand");
    }

    return resultSet;
}


// ─── saveObjectsUpdated:inserted:deleted: → POST /cdSave ─────────────────────

/*!
    Persist changes to the OrdersAPI /cdSave endpoint.

    Returns a CPSet of stub CPManagedObject instances whose objectIDs carry the
    permanent global IDs assigned by the server.  The context uses these to
    update the IDs of its registered objects.
*/
- (CPSet)saveObjectsUpdated:(CPSet)updatedObjects
                   inserted:(CPSet)insertedObjects
                    deleted:(CPSet)deletedObjects
     inManagedObjectContext:(CPManagedObjectContext)aContext
                      error:(CPError)error
{
    var tempIDMap  = [[CPMutableDictionary alloc] init];
    var inserted   = [];
    var updated    = [];
    var deleted    = [];
    var e, obj;

    // Encode inserted objects
    e = [insertedObjects objectEnumerator];
    while ((obj = [e nextObject]))
        inserted.push([self _encodeObjectForSave:obj tempIDMap:tempIDMap]);

    // Encode updated objects
    e = [updatedObjects objectEnumerator];
    while ((obj = [e nextObject]))
        updated.push([self _encodeObjectForSave:obj tempIDMap:tempIDMap]);

    // Encode deleted objects (only ID + entity name needed)
    e = [deletedObjects objectEnumerator];
    while ((obj = [e nextObject]))
    {
        var objID      = [obj objectID];
        var entityName = [[obj entity] name];
        var delEntry   = {entity: entityName};
        if ([objID validatedGlobalID])
            delEntry.id = [self _serverIDFromGlobalIDString:[objID globalID]];
        deleted.push(delEntry);
    }

    var body = {
        inserted: inserted,
        updated:  updated,
        deleted:  deleted,
        "return": {inserted: true, updated: true, includeRelationships: true}
    };

    var response = [self _sendPostToPath:@"cdSave" body:body];
    if (response == nil || !response.ok)
    {
        CPLog.error(@"CPHTTPIncrementalStore: cdSave failed");
        return [CPSet new];
    }

    var resultSet = [[CPMutableSet alloc] init];

    // Process idMap: map temporary keys → permanent server IDs
    var idMap = response.idMap;
    if (idMap != nil)
    {
        var tempKeys = Object.keys(idMap);
        var i;
        for (i = 0; i < tempKeys.length; i++)
        {
            var tempKey    = tempKeys[i];
            var serverDict = idMap[tempKey];
            var gid        = [self _globalIDStringForEntity:serverDict.entity pk:serverDict.pk];

            // Find the localID that mapped to this tempKey
            var localIDEnum = [tempIDMap keyEnumerator];
            var localID;
            while ((localID = [localIDEnum nextObject]))
            {
                if (![[tempIDMap objectForKey:localID] isEqualToString:tempKey])
                    continue;

                var entityName = serverDict.entity;
                var entity     = [[aContext model] entityWithName:entityName];
                if (entity == nil) break;

                var newObjID = [[CPManagedObjectID alloc] initWithEntity:entity globalID:gid isTemporary:NO];
                [newObjID setLocalID:localID];
                [newObjID setStore:self];

                var stub = [[CPManagedObject alloc] init];
                [stub setEntity:entity];
                [stub setObjectID:newObjID];
                [stub setStore:self];
                [stub _setData:[[CPMutableDictionary alloc] init]];
                [stub _setChangedData:[[CPMutableDictionary alloc] init]];
                [resultSet addObject:stub];
                break;
            }
        }
    }

    return resultSet;
}


// ─── fetchObjectsWithID: → POST /cdFetch (by IDs) ────────────────────────────

/*!
    Fetch specific objects by their CPManagedObjectIDs.

    Called by CPManagedObjectContext._fetchObjectWithID: when a relationship
    target is not yet registered in the context.  Grouped by entity and sent
    as a cdFetch request with an "ids" filter.
*/
- (CPSet)fetchObjectsWithID:(CPSet)objectIDs
           fetchProperties:(CPDictionary)properties
    inManagedObjectContext:(CPManagedObjectContext)aContext
                     error:(CPError)error
{
    var resultSet   = [[CPMutableSet alloc] init];

    // Group IDs by entity name
    var idsByEntity = [[CPMutableDictionary alloc] init];
    var idEnum      = [objectIDs objectEnumerator];
    var objID;
    while ((objID = [idEnum nextObject]))
    {
        if (![objID validatedGlobalID]) continue;
        var decoded    = [self _entityAndPKFromGlobalIDString:[objID globalID]];
        if (decoded == nil) continue;

        var entityName = decoded.entity;
        var existing   = [idsByEntity objectForKey:entityName];
        if (existing == nil)
        {
            existing = [[CPMutableArray alloc] init];
            [idsByEntity setObject:existing forKey:entityName];
        }
        [existing addObject:decoded.pk];
    }

    // One cdFetch request per entity
    var entityEnum = [idsByEntity keyEnumerator];
    var entityName;
    while ((entityName = [entityEnum nextObject]))
    {
        var pks  = [idsByEntity objectForKey:entityName];
        var body = {
            entity:    entityName,
            ids:       pks,
            "return":  {onlyIDs: false}
        };

        var response = [self _sendPostToPath:@"cdFetch" body:body];
        if (response == nil || !response.ok) continue;

        var objectsByID = response.objectsByID;
        if (objectsByID != nil)
        {
            var ids = Object.keys(objectsByID);
            var i;
            for (i = 0; i < ids.length; i++)
            {
                var snap     = objectsByID[ids[i]];
                var snapDict = [CPDictionary dictionaryWithJSObject:snap recursively:YES];
                var obj      = [self _materialiseSnapshot:snapDict inContext:aContext];
                if (obj != nil)
                    [resultSet addObject:obj];
            }
        }
    }

    return resultSet;
}

@end
