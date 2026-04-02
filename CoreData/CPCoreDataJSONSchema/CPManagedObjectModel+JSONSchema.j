@import <Foundation/Foundation.j>
@import "CPManagedObjectModel.j"

/*!
    Create a managed object model from a JSON Schema.
*/
@implementation CPManagedObjectModel (CPManagedObjectModelJSONSchema)

/*!
    Load the schemas from URLs.
*/
+(id)modelWithJSONSchemaURLs:(CPDictionary)URLs
                       named:(CPString)aModelName
{
    var iter = [URLs keyEnumerator],
        schemas = [[CPMutableDictionary alloc] init];
    var name;
    while (name = [iter nextObject])
    {
        var URL = [URLs objectForKey:name];
        var request = [[CPURLRequest alloc] initWithURL:[CPURL URLWithString:URL]];
        [request setHTTPMethod:@"GET"];
        [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
        var data = [CPURLConnection sendSynchronousRequest:request returningResponse:nil];
        [schemas setObject:[data rawString] forKey:name];
    }
    return [[CPManagedObjectModel alloc] initWithJSONSchemas:schemas
                                                       named:aModelName];
}

/*!
    Asynchronous load schemas from URLs.

    The model returned has no entities assigned. The delegate will receive
    these callbacks:
     -(void)model:didLoadEntity: for every entity loaded
     -(void)didFinishLoading: after all URLs are successfully loaded (last)

    Error:
     -(void)model:didFailWithURL: (last)
*/
+(id)modelWithJSONSchemaURLs:(CPDictionary)URLs
                       named:(CPString)aModelName
                    delegate:(id)aDelegate
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:aModelName];
    [model loadWithURLs:URLs
               delegate:aDelegate];
    return model;
}

-(void)loadWithURLs:(CPDictionary)URLs
           delegate:(id)aDelegate
{
    var loader = [CPManagedObjectModelLoader loaderWithModel:self
                                              JSONSchemaURLs:URLs
                                                    delegate:aDelegate];
    [loader start];
}

-(id)initWithJSONSchemas:(CPDictionary)schemas
                   named:(CPString)aModelname
{
    self = [self init];
    if (self)
    {
        _name = aModelname;
        var iter = [schemas keyEnumerator],
            name;
        while (name = [iter nextObject])
        {
            var schema = [schemas objectForKey:name];
            [self addJSONSchemaWithName:name
                                 schema:[schema objectFromJSON]];
        }
    }
    return self;
}

-(CPEntityDescription)addJSONSchemaWithName:(CPString)aName
                                     schema:(id)JSONSchema

{
    var entity = [CPEntityDescription entityWithJSONSchema:JSONSchema
                                                   forName:aName];
    [self addEntity:entity];
    return entity
}

@end


@implementation CPManagedObjectModelLoader : CPObject
{
    CPManagedObjectModel _model;
    CPDictionary _URLs;
    id _delegate;
    id _iter;
    CPString _currentName;
    int _statusReceived;
    CPString _dataReceived;

    int _retryCount;
}

+(id)loaderWithModel:(CPManagedObjectModel)aModel
      JSONSchemaURLs:(CPDictionary)aURLs
            delegate:(id)aDelegate
{
    return [[CPManagedObjectModelLoader alloc] initWithModel:aModel
                                              JSONSchemaURLs:aURLs
                                                    delegate:aDelegate];
}

-(id)initWithModel:(CPManagedObjectModel)aModel
    JSONSchemaURLs:(CPDictionary)aURLs
          delegate:(id)aDelegate
{
    self = [self init];
    if (self)
    {
        _model = aModel;
        _URLs = aURLs;
        _delegate = aDelegate;
        _iter = [_URLs keyEnumerator];
    }
    return self;
}

-(void)start
{
    [self loadNext];
}

-(void)loadNext
{
    _currentName = [_iter nextObject];
    if (_currentName == nil)
    {
        [_delegate didFinishLoading:_model];
    }
    else
    {
        [self retry];
    }
}

-(void)retry
{
    if (_currentName == nil)
    {
        [self loadNext];
    }
    else
    {
        if (_retryCount < 10)
        {
            _retryCount += 1;
        }
        var URL = [_URLs objectForKey:_currentName];
        var request = [[CPURLRequest alloc] initWithURL:[CPURL URLWithString:URL]];
        [request setHTTPMethod:@"GET"];
        [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
        [CPURLConnection connectionWithRequest:request
                                      delegate:self];
    }
}

-(void)     connection:(CPURLConnection)connection
    didReceiveResponse:(CPHTTPURLResponse)response
{
    _statusReceived = [response statusCode];
    _dataReceived = @"";
}

-(void)connection:(CPURLConnection)connection
    didReceiveData:(id)responseData
{
    _dataReceived = [_dataReceived stringByAppendingString:responseData];
}

-(void)connectionDidFinishLoading:(CPURLConnection)connection
{
    if (_statusReceived == 200)
    {
        var entity = [_model addJSONSchemaWithName:_currentName
                                            schema:[_dataReceived objectFromJSON]];
        [_delegate model:_model
           didLoadEntity:entity];
        [self loadNext];
        _retryCount = 0;
    }
    else
    {
        [_delegate        model:_model
          didFailWithEntityName:_currentName
                 retryInSeconds:_retryCount];
        [CPTimer scheduledTimerWithTimeInterval:_retryCount
                                         target:self
                                       selector:@selector(retry)
                                       userInfo:nil
                                        repeats:NO];
    }
}

-(void)   connection:(CPURLConnection)connection
    didFailWithError:(id)error
{
    [_delegate        model:_model
      didFailWithEntityName:_currentName
             retryInSeconds:_retryCount];
    [CPTimer scheduledTimerWithTimeInterval:_retryCount
                                     target:self
                                   selector:@selector(retry)
                                   userInfo:nil
                                    repeats:NO];
}

@end

