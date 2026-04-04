@import <OJUnit/OJTestCase.j>

@import "Tools.j"


// ---------------------------------------------------------------------------
// Helper: tracked managed object that records lifecycle hook calls
// ---------------------------------------------------------------------------

@implementation TrackedManagedObject : CPManagedObject
{
    CPMutableArray _lifecycleLog @accessors(property=lifecycleLog);
    BOOL _isDeletedAtPrepare @accessors(property=isDeletedAtPrepare);
}

- (id)init
{
    if (self = [super init])
    {
        _lifecycleLog = [[CPMutableArray alloc] init];
        _isDeletedAtPrepare = NO;
    }
    return self;
}

- (void)awakeFromInsert
{
    [_lifecycleLog addObject:@"awakeFromInsert"];
}

- (void)awakeFromFetch
{
    [_lifecycleLog addObject:@"awakeFromFetch"];
}

- (void)willSave
{
    [_lifecycleLog addObject:@"willSave"];
}

- (void)didSave
{
    [_lifecycleLog addObject:@"didSave"];
}

- (void)prepareForDeletion
{
    [_lifecycleLog addObject:@"prepareForDeletion"];
    // Capture whether isDeleted is already set at the time the hook fires
    _isDeletedAtPrepare = [self isDeleted];
}

@end


// ---------------------------------------------------------------------------
// Helper: a store that injects pre-built TrackedManagedObject instances
// ---------------------------------------------------------------------------

@implementation LifecycleTestStoreType : CPPersistentStoreType

+ (CPString)type
{
    return @"LifecycleTestStore";
}

+ (Class)storeClass
{
    return [LifecycleTestStore class];
}

@end


@implementation LifecycleTestStore : CPPersistentStore

- (void)saveAll:(CPSet)objects error:(@ref)error {}

- (CPSet)loadAll:(CPDictionary)properties
    inManagedObjectContext:(CPManagedObjectContext)aContext
                    error:(@ref)error
{
    return [CPSet new];
}

- (CPSet)saveObjectsUpdated:(CPSet)updated
                   inserted:(CPSet)inserted
                    deleted:(CPSet)deleted
     inManagedObjectContext:(CPManagedObjectContext)aContext
                      error:(@ref)error
{
    var result = [[CPMutableSet alloc] init];
    [result unionSet:updated];
    [result unionSet:inserted];
    [result unionSet:deleted];
    return result;
}

@end


// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

@implementation CPManagedObjectLifecycleTest : OJTestCase
{
    CPManagedObjectContext context;
    CPEntityDescription    entityDesc;
}

- (void)setUp
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:@"LifecycleModel"];

    entityDesc = [[CPEntityDescription alloc] init];
    [entityDesc setName:@"Item"];
    [entityDesc addAttributeWithName:@"title"
                          classValue:@"CPString"
                          typeValue:CPDStringAttributeType
                           optional:YES];
    [model addEntity:entityDesc];

    var coordinator = [[CPPersistentStoreCoordinator alloc]
                            initWithManagedObjectModel:model
                                             storeType:[LifecycleTestStoreType class]
                                    storeConfiguration:nil];
    context = [[CPManagedObjectContext alloc] initWithPersistentStoreCoordinator:coordinator];
}


// ---- awakeFromInsert -------------------------------------------------------

- (void)testAwakeFromInsertCalledOnNewInsert
{
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];
    [self assertTrue:[[obj lifecycleLog] containsObject:@"awakeFromInsert"]
             message:@"awakeFromInsert should be called when a new object is inserted"];
}

- (void)testAwakeFromInsertCalledOnlyOnce
{
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];
    // Insert the same object again (idempotent re-registration)
    [context insertObject:obj];
    var count = 0;
    var log = [obj lifecycleLog];
    for (var i = 0; i < [log count]; i++)
    {
        if ([[log objectAtIndex:i] isEqualToString:@"awakeFromInsert"])
            count++;
    }
    [self assert:1 equals:count message:@"awakeFromInsert should be called exactly once per new insert"];
}


// ---- awakeFromFetch --------------------------------------------------------

- (void)testAwakeFromFetchCalledWhenRegisteringFetchedObject
{
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:nil];
    [[obj objectID] setGlobalID:@"Item|id=1;"];

    // Simulate a fetch result — _registerFetchedObject: should fire awakeFromFetch
    [context _registerFetchedObject:obj];

    [self assertTrue:[[obj lifecycleLog] containsObject:@"awakeFromFetch"]
             message:@"awakeFromFetch should be called when object is registered from a fetch"];
}

- (void)testAwakeFromFetchNotCalledForAlreadyRegisteredObject
{
    // Register the object once (as a new insert)
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];
    [[obj lifecycleLog] removeAllObjects];

    // Re-registering via _registerFetchedObject: should NOT call awakeFromFetch
    // because the object is already known to the context.
    [context _registerFetchedObject:obj];

    [self assertFalse:[[obj lifecycleLog] containsObject:@"awakeFromFetch"]
              message:@"awakeFromFetch should not be called for an already-registered object"];
}


// ---- willSave / didSave ----------------------------------------------------

- (void)testWillSaveCalledBeforeSave
{
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];
    [[obj lifecycleLog] removeAllObjects];

    [context saveChanges:nil];

    [self assertTrue:[[obj lifecycleLog] containsObject:@"willSave"]
             message:@"willSave should be called on objects before save"];
}

- (void)testDidSaveCalledAfterSuccessfulSave
{
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];
    [[obj lifecycleLog] removeAllObjects];

    [context saveChanges:nil];

    [self assertTrue:[[obj lifecycleLog] containsObject:@"didSave"]
             message:@"didSave should be called on objects after a successful save"];
}

- (void)testWillSaveCalledBeforeDidSave
{
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];
    [[obj lifecycleLog] removeAllObjects];

    [context saveChanges:nil];

    var log = [obj lifecycleLog];
    var willIdx = -1, didIdx = -1;
    for (var i = 0; i < [log count]; i++)
    {
        if ([[log objectAtIndex:i] isEqualToString:@"willSave"]) willIdx = i;
        if ([[log objectAtIndex:i] isEqualToString:@"didSave"])  didIdx = i;
    }
    [self assertTrue:(willIdx < didIdx)
             message:@"willSave must be called before didSave"];
}


// ---- prepareForDeletion ----------------------------------------------------

- (void)testPrepareForDeletionCalledOnDelete
{
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];
    [[obj lifecycleLog] removeAllObjects];

    [context deleteObject:obj];

    [self assertTrue:[[obj lifecycleLog] containsObject:@"prepareForDeletion"]
             message:@"prepareForDeletion should be called when object is deleted"];
}

- (void)testPrepareForDeletionCalledBeforeObjectMarkedDeleted
{
    // prepareForDeletion fires before _solveRelationshipsWithDeleteRules and
    // before [aObject setDeleted:YES], so isDeleted should still be NO at the
    // moment the hook is invoked.  TrackedManagedObject captures this value
    // in _isDeletedAtPrepare.
    var obj = [[TrackedManagedObject alloc] initWithEntity:entityDesc
                                    inManagedObjectContext:context];

    [context deleteObject:obj];

    // After deleteObject: the object IS marked as deleted
    [self assertTrue:[obj isDeleted]
             message:@"Object should be marked as deleted after deleteObject:"];
    // But at the moment prepareForDeletion fired it was NOT yet deleted
    [self assertFalse:[obj isDeletedAtPrepare]
              message:@"isDeleted should be NO when prepareForDeletion fires"];
}

@end
