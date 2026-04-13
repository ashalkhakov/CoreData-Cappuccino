
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
        [[CPSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];
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
        [[CPSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];

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
        [[CPSortDescriptor alloc] initWithKey:@"category" ascending:YES],
        [[CPSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];

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

// ---- insert not matching predicate → no delegate notification ---------------

- (void)testInsertObjectNotMatchingPredicateDoesNotNotifyDelegate
{
    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entityDesc];
    [req setPredicate:[CPPredicate predicateWithFormat:@"priority < 10"]];
    [req setSortDescriptors:[CPArray arrayWithObjects:
        [[CPSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];

    var frc = [CPFetchedResultsController
                  fetchedResultsControllerWithFetchRequest:req
                                      managedObjectContext:context
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
    [frc setDelegate:delegate];
    [frc performFetch:nil];

    // Insert an object that does NOT match the predicate
    var obj = [[CPManagedObject alloc] initWithEntity:entityDesc
                               inManagedObjectContext:context];
    [obj setValue:@"Zulu" forKey:@"title"];
    [obj setValue:99 forKey:@"priority"];
    [context saveChanges:nil];

    [self assert:0
          equals:[[delegate willChangeLog] count]
         message:@"controllerWillChangeContent: should NOT be called for non-matching insert"];
    [self assert:0
          equals:[[delegate objectChanges] count]
         message:@"No object-change notification expected for non-matching insert"];
    [self assert:0
          equals:[[frc fetchedObjects] count]
         message:@"fetchedObjects should remain empty for non-matching insert"];
}

// ---- update that makes object match predicate → treated as insert -----------

- (void)testUpdateMakingObjectMatchPredicateTreatedAsInsert
{
    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entityDesc];
    [req setPredicate:[CPPredicate predicateWithFormat:@"priority < 10"]];
    [req setSortDescriptors:[CPArray arrayWithObjects:
        [[CPSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];

    // Insert outside the predicate range first
    var obj = [[CPManagedObject alloc] initWithEntity:entityDesc
                               inManagedObjectContext:context];
    [obj setValue:@"India" forKey:@"title"];
    [obj setValue:99 forKey:@"priority"];
    [context saveChanges:nil];

    var frc = [CPFetchedResultsController
                  fetchedResultsControllerWithFetchRequest:req
                                      managedObjectContext:context
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
    [frc setDelegate:delegate];
    [frc performFetch:nil];

    [self assert:0 equals:[[frc fetchedObjects] count]
         message:@"Should start with 0 objects (none match predicate)"];

    // Now update so the object enters the predicate range
    [obj setValue:5 forKey:@"priority"];
    [context saveChanges:nil];

    [self assert:1 equals:[[frc fetchedObjects] count]
         message:@"fetchedObjects should contain the object after it starts matching"];

    var insertChanges = [[CPMutableArray alloc] init];
    var changes = [delegate objectChanges];
    for (var i = 0; i < [changes count]; i++)
    {
        if ([[changes objectAtIndex:i] objectForKey:@"type"] === CPFetchedResultsChangeInsert)
            [insertChanges addObject:[changes objectAtIndex:i]];
    }
    [self assertTrue:([insertChanges count] > 0)
             message:@"CPFetchedResultsChangeInsert should be sent when object newly matches predicate"];
}

// ---- multiple deletions in one save ----------------------------------------

- (void)testMultipleDeletesInOneSave
{
    var obj1 = [self insertItemWithTitle:@"Juliett" priority:10];
    var obj2 = [self insertItemWithTitle:@"Kilo"    priority:11];
    var obj3 = [self insertItemWithTitle:@"Lima"    priority:12];

    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];
    [self assert:3 equals:[[frc fetchedObjects] count]];

    [[delegate willChangeLog] removeAllObjects];
    [[delegate didChangeLog]  removeAllObjects];
    [[delegate objectChanges] removeAllObjects];

    [context deleteObject:obj1];
    [context deleteObject:obj2];
    [context saveChanges:nil];

    [self assert:1 equals:[[delegate willChangeLog] count]
         message:@"controllerWillChangeContent: should be called exactly once for a batch delete"];
    [self assert:1 equals:[[delegate didChangeLog] count]
         message:@"controllerDidChangeContent: should be called exactly once for a batch delete"];

    var deleteChanges = [[CPMutableArray alloc] init];
    var changes = [delegate objectChanges];
    for (var i = 0; i < [changes count]; i++)
    {
        if ([[changes objectAtIndex:i] objectForKey:@"type"] === CPFetchedResultsChangeDelete)
            [deleteChanges addObject:[changes objectAtIndex:i]];
    }
    [self assert:2 equals:[deleteChanges count]
         message:@"Two CPFetchedResultsChangeDelete notifications expected"];
    [self assert:1 equals:[[frc fetchedObjects] count]
         message:@"One object should remain after deleting two of three"];
}

// ---- delete object not matching predicate → no notification ----------------

- (void)testDeleteObjectNotMatchingPredicateDoesNotNotifyDelegate
{
    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entityDesc];
    [req setPredicate:[CPPredicate predicateWithFormat:@"priority < 10"]];
    [req setSortDescriptors:[CPArray arrayWithObjects:
        [[CPSortDescriptor alloc] initWithKey:@"title" ascending:YES], nil]];

    // Insert outside the predicate range
    var obj = [[CPManagedObject alloc] initWithEntity:entityDesc
                               inManagedObjectContext:context];
    [obj setValue:@"Mike" forKey:@"title"];
    [obj setValue:99 forKey:@"priority"];
    [context saveChanges:nil];

    var frc = [CPFetchedResultsController
                  fetchedResultsControllerWithFetchRequest:req
                                      managedObjectContext:context
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
    [frc setDelegate:delegate];
    [frc performFetch:nil];

    [self assert:0 equals:[[frc fetchedObjects] count]];

    // Delete the non-matching object
    [context deleteObject:obj];
    [context saveChanges:nil];

    [self assert:0 equals:[[delegate willChangeLog] count]
         message:@"controllerWillChangeContent: should NOT be called when a non-matching object is deleted"];
    [self assert:0 equals:[[delegate objectChanges] count]
         message:@"No object-change notifications expected when a non-matching object is deleted"];
}

// ---- multiple inserts maintain sort order ----------------------------------

- (void)testMultipleInsertsAreSortedCorrectly
{
    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];

    // Insert three items out of alphabetical order, then verify sort
    [self insertItemWithTitle:@"November" priority:1];
    [self insertItemWithTitle:@"Oscar"    priority:2];
    [self insertItemWithTitle:@"Mike"     priority:3];

    var objs = [frc fetchedObjects];
    [self assert:3 equals:[objs count]
         message:@"All three inserted objects should appear in fetchedObjects"];
    [self assert:@"Mike"     equals:[[objs objectAtIndex:0] valueForKey:@"title"]
         message:@"First item should be Mike"];
    [self assert:@"November" equals:[[objs objectAtIndex:1] valueForKey:@"title"]
         message:@"Second item should be November"];
    [self assert:@"Oscar"    equals:[[objs objectAtIndex:2] valueForKey:@"title"]
         message:@"Third item should be Oscar"];
}

// ---- mixed changes in one save (insert + delete + update + move) -----------

- (void)testMixedChangesInOneSave
{
    // Set up initial state: Papa (p=1), Quebec (p=2), Romeo (p=3)
    var papa    = [self insertItemWithTitle:@"Papa"   priority:1];
    var quebec  = [self insertItemWithTitle:@"Quebec" priority:2];
    var romeo   = [self insertItemWithTitle:@"Romeo"  priority:3];

    var frc = [self makeFRCWithRequest:[self fetchRequestSortedByTitle]];
    [frc performFetch:nil];
    [self assert:3 equals:[[frc fetchedObjects] count]];

    [[delegate willChangeLog] removeAllObjects];
    [[delegate didChangeLog]  removeAllObjects];
    [[delegate objectChanges] removeAllObjects];

    // In one batch:
    //   - Delete Quebec
    //   - Update Papa's priority (non-sort key) → update notification
    //   - Rename Romeo → "Alpha" so it moves to front → move notification
    //   - Insert a new object Sierra
    [context deleteObject:quebec];
    [papa setValue:99 forKey:@"priority"];
    [romeo setValue:@"Alpha" forKey:@"title"];
    var sierra = [[CPManagedObject alloc] initWithEntity:entityDesc inManagedObjectContext:context];
    [sierra setValue:@"Sierra" forKey:@"title"];
    [sierra setValue:5 forKey:@"priority"];
    [context saveChanges:nil];

    [self assert:1 equals:[[delegate willChangeLog] count]
         message:@"controllerWillChangeContent: should be called once for mixed changes"];
    [self assert:1 equals:[[delegate didChangeLog] count]
         message:@"controllerDidChangeContent: should be called once for mixed changes"];

    var insertCount = 0;
    var deleteCount = 0;
    var changes = [delegate objectChanges];
    for (var i = 0; i < [changes count]; i++)
    {
        var t = [[changes objectAtIndex:i] objectForKey:@"type"];
        if (t === CPFetchedResultsChangeInsert) insertCount++;
        if (t === CPFetchedResultsChangeDelete) deleteCount++;
    }
    [self assert:1 equals:insertCount
         message:@"One insert notification expected in mixed-change batch"];
    [self assert:1 equals:deleteCount
         message:@"One delete notification expected in mixed-change batch"];

    // Final state: Alpha (was Romeo), Papa, Sierra  →  3 objects
    [self assert:3 equals:[[frc fetchedObjects] count]
         message:@"Three objects should remain after mixed-change batch"];
    [self assert:@"Alpha"  equals:[[[frc fetchedObjects] objectAtIndex:0] valueForKey:@"title"]
         message:@"First object should be Alpha (renamed Romeo)"];
    [self assert:@"Papa"   equals:[[[frc fetchedObjects] objectAtIndex:1] valueForKey:@"title"]
         message:@"Second object should be Papa"];
    [self assert:@"Sierra" equals:[[[frc fetchedObjects] objectAtIndex:2] valueForKey:@"title"]
         message:@"Third object should be Sierra (newly inserted)"];
}

@end
