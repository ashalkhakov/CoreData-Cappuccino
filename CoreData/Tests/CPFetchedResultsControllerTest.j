
@import <OJUnit/OJTestCase.j>

@import "Tools.j"


// ---------------------------------------------------------------------------
// Helper: a minimal delegate that records every callback
// ---------------------------------------------------------------------------

@implementation FRCTestDelegate : CPObject
{
    CPMutableArray _willChangeLog    @accessors(property=willChangeLog);
    CPMutableArray _didChangeLog     @accessors(property=didChangeLog);
    CPMutableArray _objectChanges    @accessors(property=objectChanges);
    CPMutableArray _sectionChanges   @accessors(property=sectionChanges);
}

- (id)init
{
    if ((self = [super init]))
    {
        _willChangeLog  = [[CPMutableArray alloc] init];
        _didChangeLog   = [[CPMutableArray alloc] init];
        _objectChanges  = [[CPMutableArray alloc] init];
        _sectionChanges = [[CPMutableArray alloc] init];
    }
    return self;
}

- (void)controllerWillChangeContent:(CPFetchedResultsController)controller
{
    [_willChangeLog addObject:controller];
}

- (void)controllerDidChangeContent:(CPFetchedResultsController)controller
{
    [_didChangeLog addObject:controller];
}

- (void)controller:(CPFetchedResultsController)controller
   didChangeObject:(id)object
       atIndexPath:(CPIndexPath)indexPath
     forChangeType:(CPInteger)type
      newIndexPath:(CPIndexPath)newIndexPath
{
    [_objectChanges addObject:[CPDictionary dictionaryWithObjectsAndKeys:
        controller,  @"controller",
        object,      @"object",
        type,        @"type",
        indexPath  ? indexPath  : [CPNull null], @"indexPath",
        newIndexPath ? newIndexPath : [CPNull null], @"newIndexPath"
    ]];
}

- (void)controller:(CPFetchedResultsController)controller
  didChangeSection:(CPFetchedResultsSectionInfo)sectionInfo
           atIndex:(CPInteger)sectionIndex
     forChangeType:(CPInteger)type
{
    [_sectionChanges addObject:[CPDictionary dictionaryWithObjectsAndKeys:
        controller,  @"controller",
        sectionInfo, @"sectionInfo",
        sectionIndex, @"sectionIndex",
        type,        @"type"
    ]];
}

@end


// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

@implementation CPFetchedResultsControllerTest : OJTestCase
{
    CPManagedObjectContext context;
    CPEntityDescription    entityDesc;
    FRCTestDelegate        delegate;
}

- (void)setUp
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:@"FRCTestModel"];

    entityDesc = [[CPEntityDescription alloc] init];
    [entityDesc setName:@"Item"];
    [entityDesc addAttributeWithName:@"title"
                          classValue:@"CPString"
                          typeValue:CPDStringAttributeType
                           optional:YES];
    [entityDesc addAttributeWithName:@"priority"
                          classValue:@"CPNumber"
                          typeValue:CPDInteger32AttributeType
                           optional:YES];
    [entityDesc addAttributeWithName:@"category"
                          classValue:@"CPString"
                          typeValue:CPDStringAttributeType
                           optional:YES];
    [model addEntity:entityDesc];

    var coordinator = [[CPPersistentStoreCoordinator alloc]
                            initWithManagedObjectModel:model
                                             storeType:[StorageWithSaveObjectsUpdatedType class]
                                    storeConfiguration:nil];
    context  = [[CPManagedObjectContext alloc] initWithPersistentStoreCoordinator:coordinator];
    delegate = [[FRCTestDelegate alloc] init];
}

// ---- Helper ----------------------------------------------------------------

- (CPFetchRequest)fetchRequestSortedByTitle
{
    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entityDesc];
    [req setSortDescriptors:[CPArray arrayWithObjects:
        [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];
    return req;
}

- (CPFetchedResultsController)makeFRCWithRequest:(CPFetchRequest)req
{
    var frc = [CPFetchedResultsController
                  fetchedResultsControllerWithFetchRequest:req
                                      managedObjectContext:context
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
    [frc setDelegate:delegate];
    return frc;
}

- (CPManagedObject)insertItemWithTitle:(CPString)title priority:(CPInteger)priority
{
    var obj = [[CPManagedObject alloc] initWithEntity:entityDesc
                               inManagedObjectContext:context];
    [obj setValue:title    forKey:@"title"];
    [obj setValue:priority forKey:@"priority"];
    [context saveChanges:nil];
    return obj;
}

// ---- fetchedObjects is nil before performFetch: ----------------------------

- (void)testFetchedObjectsNilBeforePerformFetch
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [self assertNull:[frc fetchedObjects]
             message:@"fetchedObjects should be nil before performFetch:"];
}

- (void)testSectionsNilBeforePerformFetch
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [self assertNull:[frc sections]
             message:@"sections should be nil before performFetch:"];
}

// ---- performFetch returns results ------------------------------------------

- (void)testPerformFetchReturnsYES
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [self assertTrue:[frc performFetch:nil]
             message:@"performFetch: should return YES on success"];
}

- (void)testFetchedObjectsNotNilAfterPerformFetch
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];
    [self assertNotNull:[frc fetchedObjects]
                message:@"fetchedObjects should not be nil after performFetch:"];
}

// ---- objects are in sort order after fetch ---------------------------------

- (void)testFetchedObjectsAreSortedAfterFetch
{
    [self insertItemWithTitle:@"Bravo"   priority:2];
    [self insertItemWithTitle:@"Alpha"   priority:1];
    [self insertItemWithTitle:@"Charlie" priority:3];

    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    var objs = [frc fetchedObjects];
    [self assert:3 equals:[objs count] message:@"Expected 3 fetched objects"];
    [self assert:@"Alpha"   equals:[[objs objectAtIndex:0] valueForKey:@"title"]];
    [self assert:@"Bravo"   equals:[[objs objectAtIndex:1] valueForKey:@"title"]];
    [self assert:@"Charlie" equals:[[objs objectAtIndex:2] valueForKey:@"title"]];
}

// ---- insert into context → FRC adds object, delegate notified -------------

- (void)testInsertObjectNotifiesDelegate
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    [self insertItemWithTitle:@"Delta" priority:4];

    [self assert:1
          equals:[[delegate willChangeLog] count]
         message:@"controllerWillChangeContent: should be called once"];
    [self assert:1
          equals:[[delegate didChangeLog] count]
         message:@"controllerDidChangeContent: should be called once"];
    [self assert:1
          equals:[[delegate objectChanges] count]
         message:@"One object-change notification expected"];

    var change = [[delegate objectChanges] objectAtIndex:0];
    [self assert:CPFetchedResultsChangeInsert
          equals:[change objectForKey:@"type"]
         message:@"Change type should be CPFetchedResultsChangeInsert"];
}

- (void)testInsertObjectAppearsInFetchedObjects
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    var obj = [self insertItemWithTitle:@"Delta" priority:4];

    [self assert:1
          equals:[[frc fetchedObjects] count]
         message:@"fetchedObjects should contain the inserted object"];
    [self assert:obj
          equals:[[frc fetchedObjects] objectAtIndex:0]
         message:@"The inserted object should appear in fetchedObjects"];
}

// ---- delete from context → FRC removes object, delegate notified ----------

- (void)testDeleteObjectNotifiesDelegate
{
    var obj = [self insertItemWithTitle:@"Echo" priority:5];
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];
    [self assert:1 equals:[[frc fetchedObjects] count]];

    [context deleteObject:obj];
    [context saveChanges:nil];

    [self assert:1
          equals:[[delegate willChangeLog] count]
         message:@"controllerWillChangeContent: should be called once on delete"];
    [self assert:1
          equals:[[delegate objectChanges] count]
         message:@"One object-change notification expected for delete"];

    var change = [[delegate objectChanges] objectAtIndex:0];
    [self assert:CPFetchedResultsChangeDelete
          equals:[change objectForKey:@"type"]
         message:@"Change type should be CPFetchedResultsChangeDelete"];
}

- (void)testDeleteObjectRemovedFromFetchedObjects
{
    var obj = [self insertItemWithTitle:@"Foxtrot" priority:6];
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    [context deleteObject:obj];
    [context saveChanges:nil];

    [self assert:0
          equals:[[frc fetchedObjects] count]
         message:@"fetchedObjects should be empty after deleting the only object"];
}

// ---- update that changes sort key → move -----------------------------------

- (void)testUpdateWithSortKeyChangeSendsMove
{
    var obj1 = [self insertItemWithTitle:@"Alpha" priority:1];
    var obj2 = [self insertItemWithTitle:@"Zulu"  priority:2];

    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    // Alpha is at section 0, row 0
    var firstIP = [CPIndexPath indexPathWithIndexes:[CPArray arrayWithObjects:0, 0, nil]];
    [self assert:@"Alpha" equals:[[frc objectAtIndexPath:firstIP] valueForKey:@"title"]];

    // Rename Zulu → "Aardvark" so it moves before Alpha
    [obj2 setValue:@"Aardvark" forKey:@"title"];
    [context saveChanges:nil];

    var moveChanges = [[CPMutableArray alloc] init];
    var changes = [delegate objectChanges];
    for (var i = 0; i < [changes count]; i++)
    {
        var ch = [changes objectAtIndex:i];
        if ([ch objectForKey:@"type"] === CPFetchedResultsChangeMove)
            [moveChanges addObject:ch];
    }

    [self assertTrue:([moveChanges count] > 0)
             message:@"At least one CPFetchedResultsChangeMove expected when sort key changes"];
}

// ---- update that doesn't affect sort → update ------------------------------

- (void)testUpdateWithoutSortKeyChangeSendsUpdate
{
    var obj = [self insertItemWithTitle:@"Golf" priority:7];
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];
    [[delegate objectChanges] removeAllObjects];
    [[delegate willChangeLog] removeAllObjects];

    // Change a non-sort key (priority)
    [obj setValue:99 forKey:@"priority"];
    [context saveChanges:nil];

    var updateChanges = [[CPMutableArray alloc] init];
    var changes = [delegate objectChanges];
    for (var i = 0; i < [changes count]; i++)
    {
        var ch = [changes objectAtIndex:i];
        if ([ch objectForKey:@"type"] === CPFetchedResultsChangeUpdate)
            [updateChanges addObject:ch];
    }

    [self assertTrue:([updateChanges count] > 0)
             message:@"At least one CPFetchedResultsChangeUpdate expected when non-sort key changes"];
}

// ---- update that fails predicate → treated as delete ----------------------

- (void)testUpdateFailingPredicateTreatedAsDelete
{
    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entityDesc];
    [req setPredicate:[CPPredicate predicateWithFormat:@"priority < 10"]];
    [req setSortDescriptors:[CPArray arrayWithObjects:
        [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];

    var obj = [self insertItemWithTitle:@"Hotel" priority:5];
    var frc = [CPFetchedResultsController
                  fetchedResultsControllerWithFetchRequest:req
                                      managedObjectContext:context
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
    [frc setDelegate:delegate];
    [frc performFetch:nil];

    [self assert:1 equals:[[frc fetchedObjects] count]];

    // Push priority above predicate threshold
    [obj setValue:20 forKey:@"priority"];
    [context saveChanges:nil];

    [self assert:0
          equals:[[frc fetchedObjects] count]
         message:@"Object should be removed when it no longer satisfies the predicate"];

    var deleteChanges = [[CPMutableArray alloc] init];
    var changes = [delegate objectChanges];
    for (var i = 0; i < [changes count]; i++)
    {
        if ([[changes objectAtIndex:i] objectForKey:@"type"] === CPFetchedResultsChangeDelete)
            [deleteChanges addObject:[changes objectAtIndex:i]];
    }
    [self assertTrue:([deleteChanges count] > 0)
             message:@"CPFetchedResultsChangeDelete should be sent when object no longer matches predicate"];
}

// ---- sections with sectionNameKeyPath -------------------------------------

- (void)testSectionsWithSectionNameKeyPath
{
    // Insert items for two categories
    var a = [[CPManagedObject alloc] initWithEntity:entityDesc inManagedObjectContext:context];
    [a setValue:@"A-item" forKey:@"title"];
    [a setValue:@"fruits" forKey:@"category"];
    var b = [[CPManagedObject alloc] initWithEntity:entityDesc inManagedObjectContext:context];
    [b setValue:@"B-item" forKey:@"title"];
    [b setValue:@"veggies" forKey:@"category"];
    var c = [[CPManagedObject alloc] initWithEntity:entityDesc inManagedObjectContext:context];
    [c setValue:@"C-item" forKey:@"title"];
    [c setValue:@"fruits" forKey:@"category"];
    [context saveChanges:nil];

    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entityDesc];
    [req setSortDescriptors:[CPArray arrayWithObjects:
        [[NSSortDescriptor alloc] initWithKey:@"category" ascending:YES],
        [[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];

    var frc = [CPFetchedResultsController
                  fetchedResultsControllerWithFetchRequest:req
                                      managedObjectContext:context
                                        sectionNameKeyPath:@"category"
                                                 cacheName:nil];
    [frc performFetch:nil];

    var sections = [frc sections];
    [self assert:2 equals:[sections count] message:@"Expected 2 sections"];
    [self assert:@"fruits"  equals:[[sections objectAtIndex:0] name]];
    [self assert:@"veggies" equals:[[sections objectAtIndex:1] name]];
    [self assert:2 equals:[[sections objectAtIndex:0] numberOfObjects]];
    [self assert:1 equals:[[sections objectAtIndex:1] numberOfObjects]];
}

// ---- objectAtIndexPath: / indexPathForObject: round-trip ------------------

- (void)testIndexPathRoundTrip
{
    var obj1 = [self insertItemWithTitle:@"Alpha"   priority:1];
    var obj2 = [self insertItemWithTitle:@"Bravo"   priority:2];
    var obj3 = [self insertItemWithTitle:@"Charlie" priority:3];

    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    for (var i = 0; i < [[frc fetchedObjects] count]; i++)
    {
        var obj = [[frc fetchedObjects] objectAtIndex:i];
        var ip  = [frc indexPathForObject:obj];
        [self assertNotNull:ip
                    message:@"indexPathForObject: should return a non-nil CPIndexPath"];
        var retrieved = [frc objectAtIndexPath:ip];
        [self assert:obj equals:retrieved
             message:@"objectAtIndexPath: should return the same object"];
    }
}

- (void)testIndexPathForObjectNotInResultsReturnsNil
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    var untracked = [[CPManagedObject alloc] initWithEntity:entityDesc
                                      inManagedObjectContext:nil];
    [self assertNull:[frc indexPathForObject:untracked]
             message:@"indexPathForObject: for an untracked object should return nil"];
}

@end
