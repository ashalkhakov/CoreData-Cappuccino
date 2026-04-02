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
}

- (id) initWithManagedObjectModel: (NSManagedObjectModel) model
{
	if ((self = [super init]))
	{
		_model = model;
		_undoManager = [CPUndoManager new];
		_persistentStores = [CPDictionary new];
	}
	
	return self;	
}


- (id) initWithManagedObjectModel:(CPManagedObjectModel)model
				 		storeType:(CPPersistentStoreType) aStoreType
			   storeConfiguration:(id) aConfiguration
{
	if ((self = [super init]))
	{
		_model = model
		_undoManager = [CPUndoManager new];
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

@end
