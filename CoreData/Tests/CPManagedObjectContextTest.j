
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

-(void)testInsertedNotUpdated
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [self assert:1
          equals:[[context insertedObjects] count]
         message:"Inserted object should be in insertedObjects"];
    [self assert:0
          equals:[[context updatedObjects] count]
         message:"Newly inserted object should not be in updatedObjects"];
}

-(void)testDeleteObjectWithNoGlobalID
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [context deleteObject:obj];
    [self assert:0
          equals:[[context insertedObjects] count]
         message:"Deleted object (no globalID) should be removed from insertedObjects"];
    [self assert:0
          equals:[[context registeredObjects] count]
         message:"Deleted object (no globalID) should be removed from registeredObjects"];
    [self assert:0
          equals:[[context deletedObjects] count]
         message:"Object without globalID should not appear in deletedObjects"];
}

-(void)testDeleteObjectWithGlobalID
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [[obj objectID] setGlobalID:"global1"];
    [context deleteObject:obj];
    [self assert:1
          equals:[[context deletedObjects] count]
         message:"Deleted object with globalID should appear in deletedObjects"];
}

-(void)testDeletedObjectsEmptyAfterSave
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [[obj objectID] setGlobalID:"global1"];
    [context deleteObject:obj];
    [context saveChanges:nil];
    [self assert:0
          equals:[[context deletedObjects] count]
         message:"deletedObjects should be empty after save"];
}

-(void)testInsertThreeObjects
{
    [context insertNewObjectForEntityForName:"Testentity"];
    [context insertNewObjectForEntityForName:"Testentity"];
    [context insertNewObjectForEntityForName:"Testentity"];
    [self assert:3
          equals:[[context insertedObjects] count]
         message:"insertedObjects count should be 3 after three inserts"];
    [self assert:3
          equals:[[context registeredObjects] count]
         message:"registeredObjects count should be 3 after three inserts"];
}

-(void)testUpdateObjectAfterSave
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:"UpdateTestModel"];
    var entityDesc = [[CPEntityDescription alloc] init];
    [entityDesc setName:"UpdateEntity"];
    [entityDesc addAttributeWithName:"name"
                          classValue:"CPString"
                          typeValue:CPDStringAttributeType
                           optional:YES];
    [model addEntity:entityDesc];
    var ctx = [Tools testContextWithModel:model storeType:nil];
    var obj = [ctx insertNewObjectForEntityForName:"UpdateEntity"];
    [ctx saveChanges:nil];
    [self assert:0
          equals:[[ctx insertedObjects] count]
         message:"insertedObjects should be empty after save"];
    [obj setValue:nil forKey:"name"];
    [self assert:1
          equals:[[ctx updatedObjects] count]
         message:"Object should appear in updatedObjects after setValue:forKey:"];
}

-(void)testRollback
{
    [context insertNewObjectForEntityForName:"Testentity"];
    [context rollback];
    [self assertTrue:YES
             message:"rollback should not throw"];
}

-(void)testObjectRegisteredForIDReturnsNilForUnknown
{
    var unknownID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                     globalID:"unknown"
                                                  isTemporary:NO];
    [self assertNull:[context objectRegisteredForID:unknownID]
             message:"objectRegisteredForID: should return nil for an unknown ID"];
}

-(void)testInsertSameObjectTwiceNoDoubling
{
    var obj = [context insertNewObjectForEntityForName:"Testentity"];
    [context insertObject:obj];
    [self assert:1
          equals:[[context registeredObjects] count]
         message:"Inserting same object twice should not duplicate registeredObjects"];
}

-(void)testTwoInsertedObjectsHaveDistinctIDs
{
    var obj1 = [context insertNewObjectForEntityForName:"Testentity"];
    var obj2 = [context insertNewObjectForEntityForName:"Testentity"];
    [self assertFalse:[[obj1 objectID] isEqual:[obj2 objectID]]
              message:"Two inserted objects should have distinct IDs"];
}

@end

