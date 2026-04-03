@import <OJUnit/OJTestCase.j>

@import "Tools.j"


@implementation CPManagedObjectTest : OJTestCase
{
    CPManagedObjectContext context;
}

-(void)setUp
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:"PersonModel"];
    var entityDesc = [[CPEntityDescription alloc] init];
    [entityDesc setName:"Person"];
    [entityDesc addAttributeWithName:"firstName"
                          classValue:"CPString"
                          typeValue:CPDStringAttributeType
                           optional:YES];
    [model addEntity:entityDesc];
    context = [Tools testContextWithModel:model storeType:nil];
}

-(void)testInitCreatesObjectID
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertNotNull:[obj objectID]
                message:"Newly created object should have a non-nil objectID"];
}

-(void)testNewObjectIDIsTemporary
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertTrue:[[obj objectID] isTemporary]
             message:"Newly created object should have a temporary objectID"];
}

-(void)testNewObjectIsFaultNo
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertFalse:[obj isFault]
              message:"Newly created object should not be a fault"];
}

-(void)testNewObjectIsDeletedNo
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertFalse:[obj isDeleted]
              message:"Newly created object should not be deleted"];
}

-(void)testNewObjectIsUpdatedNo
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertFalse:[obj isUpdated]
              message:"Newly created object should not be updated"];
}

-(void)testValueForKeyReturnsDefault
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertNull:[obj valueForKey:"firstName"]
             message:"valueForKey: on a declared attribute with no value set should return nil"];
}

-(void)testSetValueStoredAndRetrieved
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [obj setValue:"John" forKey:"firstName"];
    [self assert:"John"
          equals:[obj valueForKey:"firstName"]
         message:"valueForKey: should return the value set by setValue:forKey:"];
}

-(void)testSetValueMarksObjectUpdated
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [context saveChanges:nil];
    [self assert:0
          equals:[[context insertedObjects] count]
         message:"insertedObjects should be empty after save"];
    [obj setValue:"Jane" forKey:"firstName"];
    [self assert:1
          equals:[[context updatedObjects] count]
         message:"Object should appear in updatedObjects after setValue:forKey: on a saved object"];
}

-(void)testFaultStateSetAndClear
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertFalse:[obj isFault]
              message:"New object should not be a fault"];
    [obj setFault:YES];
    [self assertTrue:[obj isFault]
             message:"After setFault:YES, isFault should be YES"];
    [obj setFault:NO];
    [self assertFalse:[obj isFault]
              message:"After setFault:NO, isFault should be NO"];
}

-(void)testEntityReturned
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assertNotNull:[obj entity]
                message:"[obj entity] should return the entity description"];
}

-(void)testEntityNameCorrect
{
    var obj = [context insertNewObjectForEntityForName:"Person"];
    [self assert:"Person"
          equals:[[obj entity] name]
         message:"[[obj entity] name] should return 'Person'"];
}

@end
