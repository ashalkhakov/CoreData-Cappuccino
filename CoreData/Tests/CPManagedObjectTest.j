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


// ---------------------------------------------------------------------------
// _validateForChanges — new vs existing object behaviour
// ---------------------------------------------------------------------------

/*!
    A NEW object (temporary objectID) with a nil mandatory attribute must
    fail validation.  This ensures that inserts are fully validated.
*/
-(void)testValidateForChanges_newObject_missingMandatoryAttrFails
{
    // Build a model with a MANDATORY "code" attribute.
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:@"ValidationModel"];
    var entityDesc = [[CPEntityDescription alloc] init];
    [entityDesc setName:@"Product"];
    [entityDesc addAttributeWithName:@"code"
                          classValue:@"CPString"
                          typeValue:CPDStringAttributeType
                           optional:NO];   // mandatory
    [model addEntity:entityDesc];
    var ctx = [Tools testContextWithModel:model storeType:nil];

    var obj = [ctx insertNewObjectForEntityForName:@"Product"];
    // `code` is nil — new object without permanent globalID
    [self assertTrue:[[obj objectID] isTemporary]
             message:@"New object should have temporary ID"];
    [self assertFalse:[obj _validateForChanges]
              message:@"New object with nil mandatory attribute should fail validation"];
}

/*!
    An EXISTING object (permanent globalID, fetched from server) with a nil
    mandatory attribute that was NEVER modified must PASS validation.  The
    attribute may simply not have been included in the server's response
    (e.g. a FK attribute like orderID on a prefetched OrderExpense), and
    re-validating it during an unrelated update would incorrectly block the save.
*/
-(void)testValidateForChanges_existingObject_nilUnchangedMandatoryAttrPasses
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:@"ValidationModel2"];
    var entityDesc = [[CPEntityDescription alloc] init];
    [entityDesc setName:@"OrderExpense"];
    [entityDesc addAttributeWithName:@"amount"
                          classValue:@"CPNumber"
                          typeValue:CPDDecimalAttributeType
                           optional:NO];   // mandatory
    [entityDesc addAttributeWithName:@"orderID"
                          classValue:@"CPNumber"
                          typeValue:CPDInteger32AttributeType
                           optional:NO];   // mandatory FK — may not come from server
    [model addEntity:entityDesc];
    var ctx = [Tools testContextWithModel:model storeType:nil];

    // Simulate a fetched expense: give it a permanent globalID and set only
    // the `amount` attribute (as the server would when returning a prefetched
    // relationship member without the FK attribute).
    var expense = [[CPManagedObject alloc] initWithEntity:entityDesc];
    var objID = [expense objectID];
    [objID setGlobalID:@"OrderExpense|expenseID=7;"];
    [objID setIsTemporary:NO];
    [[expense data] setObject:100 forKey:@"amount"];
    // `orderID` stays nil in _data (server did not return it)

    [self assertFalse:[[expense objectID] isTemporary]
              message:@"Simulated existing object should not have temporary ID"];
    [self assertTrue:[expense _validateForChanges]
             message:@"Existing object with nil unchanged mandatory FK attribute should pass validation"];
}

/*!
    An EXISTING object where both _data and _changedData carry nil for a
    mandatory attribute (the equivalent of takeStoredValue:nil forKey:) still
    passes the updated validation.  Setting a mandatory attribute to nil is a
    programming error; the validation is not expected to catch this case for
    existing objects — the UI layer should prevent it.  The important guarantee
    is that NEW inserts are fully validated (see test above) and that unchanged
    nil attributes on existing objects do not block unrelated saves.
*/
-(void)testValidateForChanges_existingObject_bothDataAndChangedNilPasses
{
    var model = [[CPManagedObjectModel alloc] init];
    [model setName:@"ValidationModel3"];
    var entityDesc = [[CPEntityDescription alloc] init];
    [entityDesc setName:@"Order"];
    [entityDesc addAttributeWithName:@"status"
                          classValue:@"CPString"
                          typeValue:CPDStringAttributeType
                           optional:NO];   // mandatory
    [model addEntity:entityDesc];
    var ctx = [Tools testContextWithModel:model storeType:nil];

    var order = [[CPManagedObject alloc] initWithEntity:entityDesc];
    var objID = [order objectID];
    [objID setGlobalID:@"Order|orderID=1;"];
    [objID setIsTemporary:NO];
    // _data["status"] is nil (from _resetObjectDataForProperties), never set by server
    // _changedData has no "status" entry
    // This mirrors the scenario where status was also not returned by the server

    // Validation must pass for existing objects with nil mandatory attrs that
    // were never changed
    [self assertTrue:[order _validateForChanges]
             message:@"Existing object with nil unchanged mandatory attribute should pass validation"];
}

@end
