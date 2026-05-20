@import <OJUnit/OJTestCase.j>

@import "CoreData.j"


/*!
    Unit tests for CPMemoryStore.

    These tests exercise the in-memory fetch path that does not require file I/O
    or a live HTTP connection.
*/
@implementation CPMemoryStoreTest : OJTestCase
{
}

// ---------------------------------------------------------------------------
// CPMemoryStore – executeFetchRequest:inManagedObjectContext:error:
// ---------------------------------------------------------------------------

/*!
    Verifies that CPMemoryStore implements executeFetchRequest:inManagedObjectContext:error:
    and returns the objects already registered in the context that match the
    fetch request's entity.

    This method is required by CPManagedObjectContext._executeStoreFetchRequest:
    and by the sync fallback path of executeStoreFetchRequestAsync:.  Without
    it, both paths raise an unrecognised-selector error against CPMemoryStore.
*/
- (void)testExecuteFetchRequest_returnsMatchingRegisteredObjects
{
    var model        = [[CPManagedObjectModel alloc] init],
        orderEntity  = [[CPEntityDescription alloc] init],
        personEntity = [[CPEntityDescription alloc] init];

    [orderEntity  setName:@"Order"];
    [personEntity setName:@"Person"];
    [model addEntity:orderEntity];
    [model addEntity:personEntity];

    var store       = [[CPMemoryStore alloc] initWithStoreID:@"memTest" configuration:nil],
        coordinator = [[CPPersistentStoreCoordinator alloc] initWithManagedObjectModel:model],
        context     = [[CPManagedObjectContext alloc] initWithPersistentStoreCoordinator:coordinator];

    // Manually insert two Order objects and one Person into the context,
    // simulating what loadAll: would have done.
    var order1 = [orderEntity createObject];
    [context insertObject:order1];

    var order2 = [orderEntity createObject];
    [context insertObject:order2];

    var person = [personEntity createObject];
    [context insertObject:person];

    // Build a fetch request for the Order entity.
    var request = [[CPFetchRequest alloc] init];
    [request setEntity:orderEntity];

    var error;
    var resultSet = [store executeFetchRequest:request
                        inManagedObjectContext:context
                                         error:@ref(error)];

    [self assertNotNull:resultSet
                message:@"executeFetchRequest:inManagedObjectContext:error: must not return nil"];

    [self assert:2 equals:[resultSet count]
         message:@"Should return exactly the two Order objects registered in the context"];

    [self assertTrue:[resultSet containsObject:order1]
              message:@"Result set must contain order1"];
    [self assertTrue:[resultSet containsObject:order2]
              message:@"Result set must contain order2"];

    [self assertFalse:[resultSet containsObject:person]
               message:@"Result set must not contain the Person object"];
}

/*!
    Verifies that a nil entity in the fetch request causes all registered objects
    to be returned (no entity filter applied).
*/
- (void)testExecuteFetchRequest_nilEntityReturnsAllRegisteredObjects
{
    var model       = [[CPManagedObjectModel alloc] init],
        orderEntity = [[CPEntityDescription alloc] init];

    [orderEntity setName:@"Order"];
    [model addEntity:orderEntity];

    var store       = [[CPMemoryStore alloc] initWithStoreID:@"memTest2" configuration:nil],
        coordinator = [[CPPersistentStoreCoordinator alloc] initWithManagedObjectModel:model],
        context     = [[CPManagedObjectContext alloc] initWithPersistentStoreCoordinator:coordinator];

    var obj1 = [orderEntity createObject];
    [context insertObject:obj1];
    var obj2 = [orderEntity createObject];
    [context insertObject:obj2];

    // Fetch request with no entity set.
    var request = [[CPFetchRequest alloc] init];
    // entity defaults to nil

    var error;
    var resultSet = [store executeFetchRequest:request
                        inManagedObjectContext:context
                                         error:@ref(error)];

    [self assertNotNull:resultSet
                message:@"Result must not be nil for nil-entity request"];

    [self assert:2 equals:[resultSet count]
         message:@"Nil-entity fetch should return all 2 registered objects"];
}

@end
