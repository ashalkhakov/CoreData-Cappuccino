
@import <OJUnit/OJTestCase.j>

@import "Tools.j"


@implementation CPManagedObjectContextTest : OJTestCase
{
    CPManagedObjectContext context;
}

-(void)setUp
{
    context = [Tools testContextWithModel:nil storeType:nil];
}

-(void)testContextCreated
{
    [self assertNotNull:context];
}

-(void)testInsertNewEntity
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [self assertNotNull:obj
                message:"No object created!"];
    [self assert:1
          equals:[[context registeredObjects] count]
         message:"No registered object in context after insert!"];
    [self assert:1
          equals:[[context insertedObjects] count]
         message:"No inserted object in context after insert!"];
}

-(void)testSaveChangesWithoutChanges
{
    [self assertTrue:[context saveChanges:nil]];
}

-(void)testSaveChangesWithInsert
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [self assertTrue:[context saveChanges:nil]];
    [self assert:0
          equals:[[context insertedObjects] count]
         message:"Inserted object in context after save!"];
    [self assert:1
          equals:[[context registeredObjects] count]
         message:"No registered object in context after save!"];
}

-(void)testSaveObjectInserted
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [self assertTrue:[context saveObject:obj error:nil]];
    [self assert:0
          equals:[[context insertedObjects] count]
         message:"Inserted object in context after save!"];
    [self assert:1
          equals:[[context registeredObjects] count]
         message:"No registered object in context after save!"];
}

-(void)testSaveOnlyOneObject
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];

    [self assert:1
          equals:[[context insertedObjects] count]
         message:"hmmmm"];

    var obj1 = [context insertNewObjectForEntityForName:"Testentity"];

    [self assert:2
          equals:[[context insertedObjects] count]
         message:"hmmmm#2"];

    [self assertTrue:[context saveObject:obj error:nil]];

    [self assert:1
          equals:[[context insertedObjects] count]
         message:"Too many inserted objects in context after save!"];
    [self assert:2
          equals:[[context registeredObjects] count]
         message:"Not enough registered objects in context after save!"];
}

-(void)testFindObjectByLocalID
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [self assert:obj
          equals:[context objectRegisteredForID:[obj objectID]]];
}

-(void)testFindObjectByGlobalID
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [[obj objectID] setGlobalID:"global"];
    [self assert:obj
          equals:[context objectRegisteredForID:[obj objectID]]];
    var ID = [[CPManagedObjectID alloc] initWithEntity:nil
                                              globalID:"unknown"
                                           isTemporary:NO];
    [self assertNull:[context objectRegisteredForID:ID]];
    [ID setGlobalID:"global"];
    [self assert:obj
          equals:[context objectRegisteredForID:ID]];
}

@end

