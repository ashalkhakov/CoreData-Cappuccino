//
//  CPPersistentStoreCoordinator.j
//
//  Created by Raphael Bartolome on 25.01.10.
//

@import <Foundation/Foundation.j>

@class CPManagedObjectModel;
@class CPPersistentStore;

@implementation CPPersistentStoreCoordinator : CPObject
{
	CPManagedObjectModel _model @accessors(property=managedObjectModel);
	CPDictionary _persistentStores @accessors(property=persistentStores);
	CPPersistentStore _persistentStore @accessors(property=persistentStore);
	CPUndoManager _undoManager;

	// Shared row cache: globalID string -> CPDictionary of attribute values.
	// Populated whenever any context materialises an object from the store;
	// consulted by all contexts before issuing a network fetch for a fault.
	CPMutableDictionary _rowCache;
}

- (id) init
{
	if ((self = [super init]))
	{
		_undoManager = [CPUndoManager new];
		_persistentStores = [CPDictionary new];
		_rowCache = [CPMutableDictionary new];
	}

	return self;
}

- (id) initWithManagedObjectModel: (NSManagedObjectModel) model
{
	if ((self = [self init]))
	{
		_model = model;
	}
	
	return self;	
}


- (id) initWithManagedObjectModel:(CPManagedObjectModel)model
				 		storeType:(CPPersistentStoreType) aStoreType
			   storeConfiguration:(id) aConfiguration
{
	if ((self = [self init]))
	{
		_model = model
		[self addPersistentStoreWithType:aStoreType configuration:aConfiguration];		
	}
	
	return self;
}


// Managing the persistent stores.
- (id) addPersistentStoreWithType: (CPPersistentStoreType) aStoreType
                    configuration: (id) aConfiguration
{
	var storeClass = [aStoreType storeClass];
	var store = [[storeClass alloc] init];
	[store setConfiguration: aConfiguration];
	[store setStoreCoordinator:self];
	_persistentStore = store;
}

- (BOOL) removePersistentStore: (id) aPersistentStore
                         error: (@ref)errorPointer
{
	//Unimplemented
}

- (id) migratePersistentStore: (id) aPersistentStore
                        toURL: (NSURL) aURL
                      options: (NSDictionary) options
                     withType: (NSString) newStoreType
                        error: (@ref) errorPointer
{
	//Unimplemented
}


- (CPUndoManager) undoManager
{
  return _undoManager;
}

- (void) setUndoManager: (CPUndoManager) aManager
{
	_undoManager = aManager;
}


- (void) undo
{
	[_undoManager undo];
}

- (void) redo
{
	[_undoManager redo];
}

// --- Row cache -----------------------------------------------------------------

/*!
    Store a snapshot of an object's attribute values in the coordinator-level
    row cache, keyed by the object's global ID string.

    The snapshot is a plain CPDictionary mapping attribute name -> value.
    Relationship keys are intentionally excluded (they are context-specific).
*/
- (void)cacheRowData:(CPDictionary)data forGlobalID:(CPString)globalID
{
	if (globalID === nil || globalID === null || globalID === "")
		return;
	[_rowCache setObject:[data copy] forKey:globalID];
}

/*!
    Return the cached attribute snapshot for globalID, or nil if not cached.
*/
- (CPDictionary)cachedRowDataForGlobalID:(CPString)globalID
{
	if (globalID === nil || globalID === null)
		return nil;
	return [_rowCache objectForKey:globalID];
}

/*!
    Remove the cache entry for globalID (e.g. after the object is deleted or
    its canonical data changes on the server).
*/
- (void)invalidateRowDataForGlobalID:(CPString)globalID
{
	if (globalID === nil || globalID === null)
		return;
	[_rowCache removeObjectForKey:globalID];
}

@end
