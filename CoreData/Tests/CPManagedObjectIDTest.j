
@import <OJUnit/OJTestCase.j>

@import "../CPManagedObjectID.j"


@implementation CPManagedObjectIDTest : OJTestCase
{
}

-(void)testProperties
{
    var moID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                globalID:"global1"
                                             isTemporary:YES];
    [self assert:"global1"
            equals:[moID globalID]];
    [self assertTrue:[moID isTemporary]];
}

-(void)testEqualIDsSameGlobalID
{
    var id1 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:"global1"
                                            isTemporary:NO];
    var id2 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:"global1"
                                            isTemporary:NO];
    [self assertTrue:[id1 isEqual:id2]
             message:"Two IDs with the same globalID should be equal"];
}

-(void)testNotEqualIDsDifferentGlobalIDs
{
    var id1 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:"global1"
                                            isTemporary:NO];
    var id2 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:"global2"
                                            isTemporary:NO];
    [self assertFalse:[id1 isEqual:id2]
              message:"Two IDs with different globalIDs should not be equal"];
}

-(void)testTemporaryIDsNotEqual
{
    var id1 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:nil
                                            isTemporary:YES];
    var id2 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:nil
                                            isTemporary:YES];
    [self assertFalse:[id1 isEqual:id2]
              message:"Two temporary IDs should not be equal to each other"];
}

-(void)testTemporaryVsPermanentNotEqual
{
    var tempID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                  globalID:nil
                                               isTemporary:YES];
    var permID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                  globalID:"global1"
                                               isTemporary:NO];
    [self assertFalse:[tempID isEqual:permID]
              message:"A temporary ID should not equal a permanent ID"];
}

-(void)testHashConsistencyWithIsEqual
{
    var id1 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:"global1"
                                            isTemporary:NO];
    var id2 = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:"global1"
                                            isTemporary:NO];
    [self assertTrue:[id1 isEqual:id2]
             message:"Precondition: IDs should be equal"];
    [self assert:[id1 hash]
          equals:[id2 hash]
         message:"Equal IDs must have the same hash"];
}

-(void)testIsTemporaryYes
{
    var tempID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                  globalID:nil
                                               isTemporary:YES];
    [self assertTrue:[tempID isTemporary]
             message:"ID created with isTemporary:YES should be temporary"];
}

-(void)testIsTemporaryNo
{
    var permID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                  globalID:"global1"
                                               isTemporary:NO];
    [self assertFalse:[permID isTemporary]
              message:"ID created with globalID and isTemporary:NO should not be temporary"];
}

-(void)testValidatedLocalIDIsSet
{
    var moID = [[CPManagedObjectID alloc] initWithEntity:nil
                                               globalID:nil
                                            isTemporary:YES];
    [self assertTrue:[moID validatedLocalID]
             message:"New temporary ID should have a localID set"];
}

-(void)testValidatedGlobalIDWithGlobalID
{
    var permID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                  globalID:"global1"
                                               isTemporary:NO];
    [self assertTrue:[permID validatedGlobalID]
             message:"ID with a globalID should have validatedGlobalID=YES"];
}

-(void)testValidatedGlobalIDWithoutGlobalID
{
    var tempID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                  globalID:nil
                                               isTemporary:YES];
    [self assertFalse:[tempID validatedGlobalID]
              message:"ID without a globalID should have validatedGlobalID=NO"];
}

@end

