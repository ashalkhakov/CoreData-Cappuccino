
// This import imports all coredata modules and tests the systax of all files
@import "CoreData.j"


@implementation Tools : CPObject

/*!
    Provide a simple model.
*/
+(CPManagedObjectModel)testModel
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:"Testmodel"];
    var entityDescription = [[CPEntityDescription alloc] init];
    [entityDescription setName:"Testentity"];
    [model addEntity:entityDescription];
    return model
}


/*!
    Provide a test storage implementing saveObjectsUpdated:...
*/
+(CPPersitentStore)testStorageWithSaveObjectsUpdated
{
    return [StorageWithSaveObjectsUpdated new];
}


+(CPManagedObjectContext)testContextWithModel:(CPManagedObjectModel)aModel
                                    storeType:(CPStorageType)aStoreType
{
    var model = aModel || [Tools testModel];
    var storeType = storeType || [StorageWithSaveObjectsUpdatedType class];
    var coordinator = [[CPPersistentStoreCoordinator alloc]
                                 initWithManagedObjectModel:model
                                                  storeType:storeType
                                         storeConfiguration:nil];
    return [[CPManagedObjectContext alloc] initWithPersistentStoreCoordinator:coordinator];
}

@end


@implementation StorageWithSaveObjectsUpdatedType : CPPersistentStoreType

+ (CPString)type
{
    return @"StorageWithSaveObjectsUpdated";
}

+ (Class)storeClass
{
    return [StorageWithSaveObjectsUpdated class];
}

@end


@implementation StorageWithSaveObjectsUpdated : CPPersistentStore


-(id)initWithStoreID:(CPString)aStoreID
{
    return [self initWithStoreID:aStoreID url:""];
}

- (void)saveAll:(CPSet) objects error:(@ref) error
{
}

- (CPSet)           loadAll:(CPDictionary)properties
     inManagedObjectContext:(CPManagedObjectContext)aContext
                      error:(@ref) error
{
    return [CPSet new];
}

- (CPSet) saveObjectsUpdated:(CPSet) updatedObjects
                    inserted:(CPSet) insertedObjects
                     deleted:(CPSet) deletedObjects
      inManagedObjectContext:(CPManagedObjectContext) aContext
                       error:(@ref) error
{
    var resultSet = [[CPMutableSet alloc] init];
    [resultSet unionSet:updatedObjects];
    [resultSet unionSet:insertedObjects];
    [resultSet unionSet:deletedObjects];
    return resultSet;
}

@end

