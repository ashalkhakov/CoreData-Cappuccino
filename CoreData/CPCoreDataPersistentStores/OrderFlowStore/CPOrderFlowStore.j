//
//  CPOrderFlowStore.j
//
//  HTTP incremental persistent store that communicates with an OrderFlow
//  backend using the /cdFetch and /cdSave endpoints.
//
//  Configuration keys:
//    CPOrderFlowStoreConfigurationKeyBaseURL  — base URL of the backend
//                                               e.g. "http://localhost:8080"
//

@import <Foundation/Foundation.j>

CPOrderFlowStoreConfigurationKeyBaseURL = @"CPOrderFlowStoreBaseURL";

@implementation CPOrderFlowStore : CPPersistentStore
{
}

// ---------------------------------------------------------------------------
// Configuration helpers
// ---------------------------------------------------------------------------

- (CPString)baseURL
{
    if (_configuration != nil)
    {
        var result = [_configuration objectForKey:CPOrderFlowStoreConfigurationKeyBaseURL];
        if (result != nil)
        {
            var lastCharacter = [result characterAtIndex:[result length] - 1];
            if (![lastCharacter isEqualToString:@"/"])
                result = result + @"/";
        }
        return result;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// Incremental store interface — fetch
// ---------------------------------------------------------------------------

/*!
    Execute a fetch request against the OrderFlow backend.

    Sends a POST to <baseURL>/cdFetch with a JSON body:
      {
        "entityName": "<entity name>",
        "qualifier":  "<predicate format string or null>",
        "fetchLimit": <integer>
      }

    The server is expected to return a JSON array of serialised
    CPManagedObject dictionaries (the same format produced by
    CPManagedObject -serializeToDictionary:containsChangedProperties:).

    @return a CPSet of CPManagedObject instances, or nil on error.
*/
- (CPSet)executeFetchRequest:(CPFetchRequest)aFetchRequest
      inManagedObjectContext:(CPManagedObjectContext)aContext
                       error:(CPError)error
{
    CPLog.debug(@"CPOrderFlowStore executeFetchRequest:");

    var entityName  = [[aFetchRequest entity] name];
    var predicate   = [aFetchRequest predicate];
    var fetchLimit  = [aFetchRequest fetchLimit];
    var qualifier   = (predicate != nil) ? [predicate predicateFormat] : @"";

    var body = [CPString JSONFromObject:{
        entityName: entityName,
        qualifier:  qualifier,
        fetchLimit: fetchLimit
    }];

    var responseString = [self _postBody:body toEndpoint:@"cdFetch"];

    if (responseString == nil)
    {
        CPLog.error(@"CPOrderFlowStore: cdFetch request failed");
        return [CPSet new];
    }

    var jsonArray;
    try
    {
        jsonArray = JSON.parse(responseString);
    }
    catch (e)
    {
        CPLog.error(@"CPOrderFlowStore: cdFetch response is not valid JSON: " + e);
        return [CPSet new];
    }

    if (!jsonArray || !Array.isArray(jsonArray))
        return [CPSet new];

    return [CPSet deserializeFromJSON:jsonArray withContext:aContext];
}

// ---------------------------------------------------------------------------
// Incremental store interface — save
// ---------------------------------------------------------------------------

/*!
    Save inserted, updated and deleted objects to the OrderFlow backend.

    Sends a POST to <baseURL>/cdSave with a JSON body:
      {
        "inserted": [ <serialised CPManagedObject>, ... ],
        "updated":  [ <serialised CPManagedObject>, ... ],
        "deleted":  [ <serialised CPManagedObject>, ... ]
      }

    The server is expected to return a JSON array of CPManagedObject
    dictionaries reflecting any server-side changes (e.g. permanent IDs
    assigned to inserted objects).  An empty array is also acceptable.

    @return a CPSet of CPManagedObjects returned by the server.
*/
- (CPSet)saveObjectsUpdated:(CPSet)updatedObjects
                   inserted:(CPSet)insertedObjects
                    deleted:(CPSet)deletedObjects
     inManagedObjectContext:(CPManagedObjectContext)aContext
                      error:(CPError)error
{
    CPLog.debug(@"CPOrderFlowStore saveObjectsUpdated:inserted:deleted:");

    var insertedArray = [insertedObjects serializeToArrayWithDictionaries:YES containsChangedProperties:NO];
    var updatedArray  = [updatedObjects  serializeToArrayWithDictionaries:YES containsChangedProperties:NO];
    var deletedArray  = [deletedObjects  serializeToArrayWithDictionaries:YES containsChangedProperties:NO];

    var body = [CPString JSONFromObject:{
        inserted: [insertedArray toJSObject],
        updated:  [updatedArray  toJSObject],
        deleted:  [deletedArray  toJSObject]
    }];

    var responseString = [self _postBody:body toEndpoint:@"cdSave"];

    if (responseString == nil)
    {
        CPLog.error(@"CPOrderFlowStore: cdSave request failed");
        return [CPSet new];
    }

    var jsonArray;
    try
    {
        jsonArray = JSON.parse(responseString);
    }
    catch (e)
    {
        CPLog.error(@"CPOrderFlowStore: cdSave response is not valid JSON: " + e);
        return [CPSet new];
    }

    if (!jsonArray || !Array.isArray(jsonArray) || jsonArray.length === 0)
        return [CPSet new];

    return [CPSet deserializeFromJSON:jsonArray withContext:aContext];
}

// ---------------------------------------------------------------------------
// Stub implementations for the bulk-store interface
// (not used by an incremental store, but required by callers that check
// for loadAll:/saveAll: instead of the incremental selectors)
// ---------------------------------------------------------------------------

- (CPSet)loadAll:(CPDictionary)properties
inManagedObjectContext:(CPManagedObjectContext)aContext
           error:(CPError)error
{
    // Incremental stores do not pre-load all objects.
    return [CPSet new];
}

- (void)saveAll:(CPSet)objects error:(CPError)error
{
    // Incremental stores save via saveObjectsUpdated:inserted:deleted:.
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/*!
    POST a JSON string body to the given endpoint path and return the
    response body as a string, or nil on network / HTTP error.
*/
- (CPString)_postBody:(CPString)body toEndpoint:(CPString)endpoint
{
    var base = [self baseURL];
    if (base == nil)
    {
        CPLog.error(@"CPOrderFlowStore: base URL is not configured");
        return nil;
    }

    var url     = base + endpoint;
    var request = [CPURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[body rawString]];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    CPLog.debug(@"CPOrderFlowStore _postBody:toEndpoint: " + url);

    var data = [CPURLConnection sendSynchronousRequest:request returningResponse:nil];
    if (data == nil)
        return nil;

    var resultString = [data description];
    CPLog.debug(@"CPOrderFlowStore response: " + resultString);
    return resultString;
}

@end
