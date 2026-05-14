//
//  CPMemoryStore.j
//
//  Created by Raphael Bartolome on 11.01.10.
//

@import <Foundation/Foundation.j>
@import "CPPersistentStoreType.j"
@import "CPPersistentStore.j"
@import "CPManagedObject+CPCoreDataSerialization.j"
@import "CPMemoryStoreType.j"

@implementation CPMemoryStore : CPPersistentStore
{
	//CPString _storeID;
	//CPURL _URL;
	//CPMutableDictionary _configuration;
	//CPMutableDictionary _metadata;

	CPManagedObjectModel _model @accessors(property=model);
}


- (id)initWithStoreID:(CPString)aStoreID configuration:(CPDictionary)configuration
{
	self = [super init];
	
	if(self != nil)
	{
		_storeID = aStoreID;
		_configuration = configuration
	}
	
	return self;
}

- (id)initWithStoreID:(CPString)aStoreID url:(CPURL)url
{
	self = [super init];
	
	if(self != nil)
	{
		_storeID = aStoreID;
		_configuration = nil;
		_URL = url;
	}
	
	return self;
}

- (CPURL)URL
{
	return _URL;
}

- (void)setURL:(CPURL)url
{
	_URL = url;
}

- (CPString)storeID
{
  return _storeID;
}


- (void)setConfiguration:(CPDictionary)configuration
{
	_configuration = configuration;
}

- (CPDictionary)configuration
{
	return _configuration;
}


- (void)setMetadata:(CPDictionary)metadata
{
	_metadata = metadata;
}

- (CPDictionary)metadata
{
	return _metadata;
}

- (CPString)resourcesFile
{
	if(_configuration != nil)
	{
		return [[CPBundle mainBundle] pathForResource:[_configuration objectForKey:CPMemoryStoreConfigurationKeyResourcesFile]];
	}
}

- (CPString)format
{
	if(_configuration != nil)
	{
		return [_configuration objectForKey:CPMemoryStoreConfigurationKeyFileFormat];
	}
}

/*
 *	The CPManagedObjectContext calls this method before it closed
 */
- (void) saveAll:(CPSet) objects error:(@ref) error
{
}

/*!
    Execute a fetch request against the in-memory object graph.

    Returns the subset of objects currently registered in \a aContext whose
    entity matches \c [aFetchRequest entity].  A nil entity in the request is
    treated as "any entity" and all registered objects are returned.

    This method is required by \c CPManagedObjectContext._executeStoreFetchRequest:
    and by the synchronous fallback path of
    \c CPManagedObjectContext.executeStoreFetchRequestAsync:completionHandler:.
    Without it, both of those paths crash with an unrecognised-selector error
    when the store is a \c CPMemoryStore.
*/
- (CPSet)executeFetchRequest:(CPFetchRequest)aFetchRequest
      inManagedObjectContext:(CPManagedObjectContext)aContext
                      error:(@ref)error
{
    var entity = [aFetchRequest entity],
        all    = [aContext registeredObjects],
        result = [[CPMutableSet alloc] init],
        e      = [all objectEnumerator],
        obj;

    while ((obj = [e nextObject]))
    {
        if (entity === nil || [[obj entity] isEqual:entity])
            [result addObject:obj];
    }
    return result;
}

/*
 *	The CPManagedObjectContext call this method through the instantiation
 *	and update and registrate the objects from reponse
 *	@return a set of CPManagedObjects with cheap relationship
 */
- (CPSet)loadAll:(CPDictionary) properties inManagedObjectContext:(CPManagedObjectContext) aContext error:(@ref) error
{
	var resultSet = nil;
	var data = [CPURLConnection sendSynchronousRequest:[CPURLRequest requestWithURL:[self resourcesFile]] returningResponse:nil];

	if([data length] > 0)
	{
		if([[self format] isEqualToString:CPCoreDataSerializationXMLFormat])
		{
			resultSet = [CPSet deserializeFromXML:data withContext:aContext];
			error = nil;
		}
		else if([[self format] isEqualToString:CPCoreDataSerialization280NPLISTFormat])
		{
			resultSet = [CPSet deserializeFrom280NPLIST:data withContext:aContext];
			error = nil;
		}
		else if([[self format] isEqualToString:CPCoreDataSerializationJSONFormat])
		{
			var jsonArray = JSON.parse([data rawString]); 
			resultSet = [CPSet deserializeFromJSON:jsonArray withContext:aContext];
		}
		else if([[self format] isEqualToString:CPCoreDataSerializationDictionaryFormat])
		{
			CPLog.error("*** Unimplemented Format ***");
		}
	}
	else
	{
		CPLog.error("*** File not found or content not readable ***");
	}

	return resultSet;
}


@end
